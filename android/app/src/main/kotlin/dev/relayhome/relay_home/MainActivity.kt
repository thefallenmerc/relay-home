package dev.relayhome.relay_home

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

class MainActivity : FlutterActivity() {
    private val connectivity by lazy { getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager }
    private val wifi by lazy { applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var permissionResult: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var previousBinding: Network? = null
    private var isBound = false
    private val permissionRequest = 6042

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.relayhome/network").setMethodCallHandler(::handleMethod)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.relayhome/network_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
                registerNetworkCallback()
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
                unregisterNetworkCallback()
            }
        })
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> {
                if (call.argument<Boolean>("requestPermission") == true) requestWifiPermission(result)
                else result.success(snapshot())
            }
            "beginProvisioning" -> {
                val network = wifiNetwork()
                if (network == null) {
                    result.error("NO_WIFI", "Connect to a 2.4 GHz Wi-Fi network first.", null)
                    return
                }
                try {
                    releaseProvisioning()
                    previousBinding = connectivity.boundNetworkForProcess
                    if (!connectivity.bindProcessToNetwork(network)) {
                        result.error("BIND_FAILED", "The Wi-Fi connection changed. Try again.", null)
                        return
                    }
                    isBound = true
                    multicastLock = wifi.createMulticastLock("relay-home-esptouch").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
                    result.success(null)
                } catch (_: Exception) {
                    releaseProvisioning()
                    result.error("WIFI_ACCESS", "Wi-Fi setup access is unavailable. Check permissions.", null)
                }
            }
            "endProvisioning" -> { releaseProvisioning(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun permissions(): Array<String> {
        // SSID/BSSID are location-sensitive even on versions with Nearby Wi-Fi.
        val names = mutableListOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= 33) names.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        return names.toTypedArray()
    }
    private fun hasPermission(name: String) = checkSelfPermission(name) == PackageManager.PERMISSION_GRANTED
    private fun requestWifiPermission(result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("PERMISSION_BUSY", "Finish the current permission request first.", null)
            return
        }
        val missing = permissions().filter { !hasPermission(it) }
        if (missing.isEmpty()) { result.success(snapshot()); return }
        permissionResult = result
        requestPermissions(missing.toTypedArray(), permissionRequest)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequest) {
            val result = permissionResult
            permissionResult = null
            result?.success(snapshot())
        }
    }

    private fun wifiNetwork(): Network? {
        val active = connectivity.activeNetwork
        if (active != null && connectivity.getNetworkCapabilities(active)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) return active
        @Suppress("DEPRECATION")
        return connectivity.allNetworks.firstOrNull { connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true }
    }
    @Suppress("DEPRECATION")
    private fun snapshot(): Map<String, Any?> {
        val network = wifiNetwork()
        val capabilities = network?.let { connectivity.getNetworkCapabilities(it) }
        val link = network?.let { connectivity.getLinkProperties(it) }
        val info = if (Build.VERSION.SDK_INT >= 29) capabilities?.transportInfo as? WifiInfo else null
        // getNetworkCapabilities may redact location-sensitive fields. The legacy
        // connection API remains a fallback for the current Wi-Fi association.
        // Both APIs still enforce the user's permission/location-service choices.
        val legacyInfo = runCatching { wifi.connectionInfo }.getOrNull()
        val address = link?.linkAddresses?.firstOrNull { it.address is Inet4Address }
        fun visibleSsid(value: String?) = value?.removeSurrounding("\"")?.takeUnless { it == "<unknown ssid>" || it.isEmpty() }
        fun visibleBssid(value: String?) = value?.takeUnless { it == "02:00:00:00:00:00" || it == "00:00:00:00:00:00" }
        val ssid = visibleSsid(info?.ssid) ?: visibleSsid(legacyInfo?.ssid)
        val bssid = visibleBssid(info?.bssid) ?: visibleBssid(legacyInfo?.bssid)
        val mask = address?.prefixLength?.let { prefix ->
            val bits = if (prefix == 0) 0L else (0xffffffffL shl (32 - prefix)) and 0xffffffffL
            listOf(24, 16, 8, 0).joinToString(".") { ((bits shr it) and 255).toString() }
        }
        return mapOf(
            "isWifi" to (network != null),
            "permissionGranted" to permissions().all { hasPermission(it) },
            "ssid" to ssid,
            "bssid" to bssid,
            "ipv4" to address?.address?.hostAddress,
            "subnetMask" to mask,
            "frequencyMhz" to (info?.frequency?.takeIf { it > 0 } ?: legacyInfo?.frequency?.takeIf { it > 0 })
        )
    }
    private fun emitChange() { mainHandler.post { eventSink?.success(mapOf("changed" to true)) } }
    private fun registerNetworkCallback() {
        if (callback != null) return
        val observer = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = emitChange()
            override fun onLost(network: Network) = emitChange()
            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) = emitChange()
            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) = emitChange()
        }
        callback = observer
        connectivity.registerNetworkCallback(NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(), observer)
    }
    private fun unregisterNetworkCallback() {
        callback?.let { try { connectivity.unregisterNetworkCallback(it) } catch (_: Exception) { } }
        callback = null
    }
    private fun releaseProvisioning() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        if (isBound) connectivity.bindProcessToNetwork(previousBinding)
        isBound = false
        previousBinding = null
    }
    override fun onDestroy() {
        releaseProvisioning()
        unregisterNetworkCallback()
        permissionResult?.error("ACTIVITY_CLOSED", "The activity closed.", null)
        permissionResult = null
        super.onDestroy()
    }
}
