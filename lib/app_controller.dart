import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'models.dart';
import 'services/network_service.dart';
import 'services/provisioning_service.dart';
import 'services/relay_transport.dart';
import 'services/storage_service.dart';

class AppController extends ChangeNotifier {
  final RelayTransport _transport;
  final NetworkService _networkService;
  final AppStorage _storage;
  final ProvisioningService _provisioning;
  final RelayImageService _images;
  AppController({
    RelayTransport? transport,
    NetworkService? networkService,
    AppStorage? storage,
    ProvisioningService? provisioning,
    RelayImageService? images,
  }) : _transport = transport ?? TcpRelayTransport(),
       _networkService = networkService ?? AndroidNetworkService(),
       _storage = storage ?? PreferencesStorage(),
       _provisioning = provisioning ?? EspTouchProvisioningService(),
       _images = images ?? RelayImageService();

  List<RelayDevice> _real = [], _demo = [];
  bool _demoMode = false,
      _initialized = false,
      _refreshing = false,
      _disposed = false;
  ThemeMode _themeMode = ThemeMode.system;
  NetworkSnapshot? _network;
  String? _networkError;
  int _discoveryGeneration = 0, _networkGeneration = 0;
  final Map<String, int> _busy = {};
  // Transient visual targets are never written into saved command history.
  final Map<String, (int, bool)> _pendingTargets = {};
  Future<void> _writes = Future.value();
  StreamSubscription<void>? _networkSubscription;
  Timer? _networkDebounce;
  bool _provisioningActive = false, _nativeProvisioningHeld = false;

  List<RelayDevice> get devices => List.unmodifiable(_demoMode ? _demo : _real);
  bool get demoMode => _demoMode;
  ThemeMode get themeMode => _themeMode;
  NetworkSnapshot? get network => _network;
  String? get networkError => _networkError;
  bool get refreshing => _refreshing;
  bool get initialized => _initialized;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _real = decodeDevices(
        await _storage.read('real_devices_v1'),
      ).map((d) => d.copyWith(demo: false)).toList();
      _demo = decodeDevices(
        await _storage.read('demo_devices_v1'),
      ).map((d) => d.copyWith(demo: true)).toList();
      _demoMode = await _storage.read('demo_mode') == 'true';
      final theme = await _storage.read('theme_mode');
      _themeMode =
          ThemeMode.values.where((v) => v.name == theme).firstOrNull ??
          ThemeMode.system;
      if (_demoMode && _demo.isEmpty) _demo = _exampleDevices();
    } on Object {
      _networkError =
          'Saved settings could not be loaded. Existing storage has not been overwritten.';
    }
    _initialized = true;
    _networkSubscription = _networkService.changes.listen(
      (_) {
        _networkDebounce?.cancel();
        _networkDebounce = Timer(const Duration(milliseconds: 500), () {
          if (!_disposed) unawaited(_handleNetworkChange());
        });
      },
      onError: (Object _) {
        _networkError =
            'Network changes could not be monitored. Pull down to refresh.';
        _notify();
      },
    );
    _notify();
    await refreshNetwork();
    await refreshDevices();
  }

  Future<void> _write(String key, String value) {
    final operation = _writes
        .catchError((Object _) {})
        .then((_) => _storage.write(key, value));
    _writes = operation;
    return operation;
  }

  Future<void> _persist(bool mode) => _write(
    mode ? 'demo_devices_v1' : 'real_devices_v1',
    encodeDevices(mode ? _demo : _real),
  );
  void _replace(RelayDevice device, bool mode) {
    final records = mode ? _demo : _real;
    final index = records.indexWhere((d) => d.id == device.id);
    if (index >= 0) records[index] = device;
    _notify();
  }

  RelayDevice? _find(String id, bool mode) =>
      (mode ? _demo : _real).where((d) => d.id == id).firstOrNull;
  @override
  void dispose() {
    _disposed = true;
    _networkDebounce?.cancel();
    unawaited(_networkSubscription?.cancel());
    cancelDiscovery();
    _provisioning.dispose();
    _transport.dispose();
    _networkService.dispose();
    super.dispose();
  }

  Future<void> setDemoMode(bool value) async {
    if (value == _demoMode) return;
    cancelDiscovery();
    await cancelProvisioning();
    _demoMode = value;
    if (value && _demo.isEmpty) _demo = _exampleDevices();
    await _write('demo_mode', '$value');
    if (value) await _persist(true);
    _notify();
    await refreshDevices();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    _notify();
    await _write('theme_mode', value.name);
  }

  Future<void> refreshNetwork({bool requestPermission = false}) async {
    try {
      _network = await _networkService.snapshot(
        requestPermission: requestPermission,
      );
      _networkError = null;
    } on Object {
      _networkError =
          'Wi-Fi details are unavailable. You can enter the network name manually.';
    }
    _notify();
  }

  Future<void> _handleNetworkChange() async {
    final old = '${_network?.ssid}/${_network?.ipv4}/${_network?.bssid}';
    await refreshNetwork();
    final changed =
        old != '${_network?.ssid}/${_network?.ipv4}/${_network?.bssid}';
    if (!changed) return;
    _networkGeneration++;
    cancelDiscovery();
    if (_provisioningActive) await cancelProvisioning();
    _real = _real
        .map((d) => d.copyWith(reachability: Reachability.offline))
        .toList();
    _notify();
    await refreshDevices();
  }

  Future<void> refreshDevices() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    _notify();
    try {
      await Future.wait(devices.map((d) => checkDevice(d.id)));
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  Future<bool> checkDevice(String id) async {
    final mode = _demoMode;
    final device = _find(id, mode);
    if (device == null) return false;
    if (mode) {
      final online = !device.id.contains('offline');
      _replace(
        device.copyWith(
          reachability: online ? Reachability.online : Reachability.offline,
        ),
        mode,
      );
      return online;
    }
    if (_network?.isWifi != true) {
      _replace(device.copyWith(reachability: Reachability.offline), mode);
      return false;
    }
    if (_busy.containsKey('real:$id')) {
      return device.reachability == Reachability.online;
    }
    final generation = _networkGeneration;
    _replace(device.copyWith(reachability: Reachability.checking), mode);
    final reachable = await _transport.check(device.ip, port: device.port);
    final current = _find(id, mode);
    if (current == null ||
        current.ip != device.ip ||
        generation != _networkGeneration) {
      return false;
    }
    _replace(
      current.copyWith(
        reachability: reachable ? Reachability.online : Reachability.offline,
        lastSeen: reachable ? DateTime.now() : null,
      ),
      mode,
    );
    return reachable;
  }

  RelayDevice? deviceById(String id) => _find(id, _demoMode);
  bool isDeviceBusy(String id) =>
      _busy.containsKey('${_demoMode ? 'demo' : 'real'}:$id');
  bool isSending(String id, int channel) {
    final key = '${_demoMode ? 'demo' : 'real'}:$id';
    return _busy[key] == channel || _pendingTargets[key]?.$1 == channel;
  }

  bool? pendingRelayState(String id, int channel) {
    final pending = _pendingTargets['${_demoMode ? 'demo' : 'real'}:$id'];
    return pending?.$1 == channel ? pending!.$2 : null;
  }

  Future<CommandResult> toggleRelay(String id, int channel, bool on) async {
    final mode = _demoMode, key = '${_demoMode ? 'demo' : 'real'}:$id';
    if (_busy.containsKey(key)) {
      return const CommandResult(
        success: false,
        message: 'Wait for this board’s current command to finish.',
      );
    }
    final device = _find(id, mode);
    if (device == null || channel < 1 || channel > 4) {
      return const CommandResult(
        success: false,
        message: 'This relay is unavailable.',
      );
    }
    if (mode && device.reachability != Reachability.online) {
      return const CommandResult(
        success: false,
        message: 'This demo board is offline.',
      );
    }
    _busy[key] = channel;
    _pendingTargets[key] = (channel, on);
    _notify();
    try {
      return await _send(id, channel, on, mode);
    } finally {
      _busy.remove(key);
      _pendingTargets.remove(key);
      _notify();
    }
  }

  Future<CommandResult> _send(
    String id,
    int channel,
    bool on,
    bool mode,
  ) async {
    final device = _find(id, mode);
    if (device == null) {
      return const CommandResult(
        success: false,
        message: 'The device was removed.',
      );
    }
    if (!mode && _network?.isWifi != true) {
      return const CommandResult(
        success: false,
        message: 'Connect this phone to the board’s Wi-Fi network first.',
      );
    }
    final generation = _networkGeneration;
    CommandResult result;
    if (mode) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      result = const CommandResult(
        success: true,
        message: 'Demo state updated. No hardware command sent.',
      );
    } else {
      result = await _transport.send(device.ip, channel, on, port: device.port);
    }
    final current = _find(id, mode);
    if (current == null) return result;
    if (!mode &&
        (generation != _networkGeneration ||
            current.ip != device.ip ||
            current.port != device.port)) {
      result = const CommandResult(
        success: false,
        uncertain: true,
        message:
            'The network or address changed during sending. The result is uncertain; check the connection.',
      );
    }
    final updated = current.copyWith(
      reachability: result.success ? Reachability.online : Reachability.offline,
      lastSeen: result.success ? DateTime.now() : null,
      relays: current.relays
          .map(
            (r) => r.channel != channel
                ? r
                : result.success
                ? r.copyWith(
                    lastState: on,
                    lastSentAt: DateTime.now(),
                    uncertain: false,
                  )
                : result.uncertain
                ? r.copyWith(uncertain: true)
                : r,
          )
          .toList(),
    );
    _replace(updated, mode);
    try {
      await _persist(mode);
    } on Object {
      return CommandResult(
        success: result.success,
        uncertain: result.uncertain,
        message:
            '${result.message} The history could not be saved on this phone.',
      );
    }
    return result;
  }

  Future<CommandResult> applySavedStates(String id) async {
    final mode = _demoMode, key = '${_demoMode ? 'demo' : 'real'}:$id';
    if (_busy.containsKey(key)) {
      return const CommandResult(
        success: false,
        message: 'Wait for this board’s current command to finish.',
      );
    }
    final device = _find(id, mode);
    if (device == null) {
      return const CommandResult(success: false, message: 'Device not found.');
    }
    final known = device.relays.where((r) => r.lastState != null).toList();
    if (known.isEmpty) {
      return const CommandResult(
        success: false,
        message: 'There are no saved states to apply yet.',
      );
    }
    if (mode && device.reachability != Reachability.online) {
      return const CommandResult(
        success: false,
        message: 'This demo board is offline.',
      );
    }
    _busy[key] = -1;
    _notify();
    try {
      for (final relay in known) {
        _pendingTargets[key] = (relay.channel, relay.lastState!);
        _notify();
        final result = await _send(id, relay.channel, relay.lastState!, mode);
        if (!result.success) return result;
      }
      return CommandResult(
        success: true,
        message: mode
            ? 'Demo states applied.'
            : '${known.length} saved commands sent. Physical state is not confirmed.',
      );
    } finally {
      _busy.remove(key);
      _pendingTargets.remove(key);
      _notify();
    }
  }

  Future<void> saveDevice(RelayDevice device) async {
    if (device.relays.length != 4 ||
        device.relays.map((r) => r.channel).toSet().difference({
          1,
          2,
          3,
          4,
        }).isNotEmpty ||
        device.relays.map((r) => r.channel).toSet().length != 4) {
      throw ArgumentError(
        'A board must have exactly four channels numbered 1–4.',
      );
    }
    if (device.name.trim().isEmpty || device.room.trim().isEmpty) {
      throw ArgumentError('Enter a device name and room.');
    }
    if (!_demoMode &&
        (!isPrivateIpv4(device.ip) || device.port < 1 || device.port > 65535)) {
      throw ArgumentError('Enter a private IPv4 address and valid TCP port.');
    }
    final mode = _demoMode;
    final records = mode ? _demo : _real;
    final normalized = device.copyWith(demo: mode);
    _ensureUniqueDevice(normalized, mode);
    final index = records.indexWhere((d) => d.id == device.id);
    if (index < 0) {
      records.add(normalized);
    } else {
      records[index] = normalized;
    }
    await _persist(mode);
    _notify();
  }

  void _ensureUniqueDevice(RelayDevice device, bool mode) {
    final records = mode ? _demo : _real;
    final duplicate = records
        .where(
          (d) =>
              d.id != device.id &&
              ((device.mac != null &&
                      d.mac?.toLowerCase() == device.mac?.toLowerCase()) ||
                  (d.ip == device.ip && d.port == device.port)),
        )
        .firstOrNull;
    if (duplicate != null) {
      throw StateError(
        'This address or device is already saved as ${duplicate.name}. Edit that device instead.',
      );
    }
  }

  /// Rebinds an existing record after SmartConfig; never replays relay states.
  Future<RelayDevice> moveDeviceToNetwork(
    String id,
    DiscoveredDevice found, {
    required String ssid,
  }) async {
    final mode = _demoMode;
    if (!found.verified || (!mode && !isPrivateIpv4(found.ip))) {
      throw StateError('Pair the board before saving its new connection.');
    }
    if (!mode) {
      await refreshNetwork();
      if (_demoMode != mode ||
          _network?.isWifi != true ||
          (_network?.ssid != null && _network!.ssid != ssid)) {
        throw StateError(
          'Reconnect this phone to “$ssid” and try setup again.',
        );
      }
    }
    final device = _find(id, mode);
    if (device == null) throw StateError('This saved board was removed.');
    if (isDeviceBusy(id)) {
      throw StateError('Wait for this board’s current command to finish.');
    }
    if (device.mac != null &&
        device.mac!.toLowerCase() != found.mac?.toLowerCase()) {
      throw StateError(
        'A different board replied. Put “${device.name}” in pairing mode and try again.',
      );
    }
    final updated = device.copyWith(
      ip: found.ip,
      mac: found.mac,
      reachability: found.reachable
          ? Reachability.online
          : Reachability.offline,
      lastSeen: found.reachable ? DateTime.now() : null,
    );
    _ensureUniqueDevice(updated, mode);
    // Keep the old connection intact if local persistence fails. Read the
    // current record above so an earlier setup-screen snapshot cannot replace
    // newer relay names, artwork, or command history.
    final records = mode ? _demo : _real;
    await _write(
      mode ? 'demo_devices_v1' : 'real_devices_v1',
      encodeDevices([
        for (final record in records) record.id == id ? updated : record,
      ]),
    );
    _replace(updated, mode);
    return updated;
  }

  Future<void> removeDevice(String id) async {
    final mode = _demoMode;
    (mode ? _demo : _real).removeWhere((d) => d.id == id);
    await _persist(mode);
    _notify();
  }

  Future<void> updateDeviceAddress(String id, String ip) async {
    final device = deviceById(id);
    if (device == null) return;
    await saveDevice(
      device.copyWith(ip: ip.trim(), reachability: Reachability.offline),
    );
    await checkDevice(id);
  }

  Future<List<DiscoveredDevice>> discover({
    void Function(int checked, int total)? onProgress,
  }) async {
    final generation = ++_discoveryGeneration;
    if (_demoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (generation != _discoveryGeneration) return [];
      onProgress?.call(1, 1);
      return [
        const DiscoveredDevice(
          ip: '192.0.2.40',
          reachable: true,
          verified: false,
        ),
      ];
    }
    await refreshNetwork();
    final hosts = localHosts(_network ?? const NetworkSnapshot());
    final results = <DiscoveredDevice>[];
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    var cursor = 0, checked = 0;
    onProgress?.call(0, hosts.length);
    Future<void> worker() async {
      while (generation == _discoveryGeneration &&
          cursor < hosts.length &&
          DateTime.now().isBefore(deadline) &&
          !_disposed) {
        final ip = hosts[cursor++];
        final open = await _transport.check(
          ip,
          timeout: const Duration(milliseconds: 600),
        );
        if (generation != _discoveryGeneration) return;
        if (open) results.add(DiscoveredDevice(ip: ip, reachable: true));
        onProgress?.call(++checked, hosts.length);
      }
    }

    await Future.wait(List.generate(24, (_) => worker()));
    results.sort(
      (a, b) => (ipv4Number(a.ip) ?? 0).compareTo(ipv4Number(b.ip) ?? 0),
    );
    if (generation != _discoveryGeneration) return [];
    if (checked < hosts.length) {
      _networkError =
          'The scan time limit was reached. You can also add a board by IP.';
      _notify();
    }
    return results;
  }

  void cancelDiscovery() {
    _discoveryGeneration++;
  }

  Future<List<DiscoveredDevice>> provision({
    required String ssid,
    required String password,
    void Function(PairingStage)? onStage,
  }) async {
    if (_provisioningActive) throw StateError('Setup is already running.');
    _provisioningActive = true;
    final generation = _networkGeneration;
    void ensureActive() {
      if (generation != _networkGeneration || _disposed) {
        throw const ProvisioningCancelled();
      }
    }

    try {
      if (_demoMode) {
        for (final stage in PairingStage.values) {
          onStage?.call(stage);
          await Future<void>.delayed(const Duration(milliseconds: 650));
          ensureActive();
        }
        return [
          const DiscoveredDevice(
            ip: '192.0.2.40',
            mac: 'DE:00:00:00:00:40',
            reachable: true,
            verified: true,
          ),
        ];
      }
      if (utf8.encode(ssid).isEmpty || utf8.encode(ssid).length > 32) {
        throw ArgumentError('The Wi-Fi name must contain 1–32 bytes.');
      }
      if (password.isNotEmpty &&
          (utf8.encode(password).length < 8 ||
              utf8.encode(password).length > 64)) {
        throw ArgumentError(
          'The Wi-Fi password must contain 8–64 bytes, or be empty for an open network.',
        );
      }
      await refreshNetwork(requestPermission: true);
      ensureActive();
      if (_network?.isWifi != true) {
        throw StateError('Connect this phone to your 2.4 GHz Wi-Fi first.');
      }
      if (_network?.frequencyMhz != null && _network!.frequencyMhz! >= 4900) {
        throw StateError(
          'This phone is on a 5 or 6 GHz band. Connect it to 2.4 GHz for setup.',
        );
      }
      if (_network?.ssid != null && _network!.ssid != ssid) {
        throw StateError(
          'Connect your phone to “$ssid” before sending its details.',
        );
      }
      await _networkService.beginProvisioning();
      _nativeProvisioningHeld = true;
      ensureActive();
      final results = await _provisioning.provision(
        ssid: ssid,
        password: password,
        bssid: _network?.bssid,
        onStage: onStage,
      );
      ensureActive();
      onStage?.call(PairingStage.checking);
      final checked = <DiscoveredDevice>[];
      for (final result in results) {
        if (!isPrivateIpv4(result.ip)) continue;
        var reachable = await _transport.check(result.ip);
        ensureActive();
        if (!reachable) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          ensureActive();
          reachable = await _transport.check(result.ip);
        }
        ensureActive();
        checked.add(
          DiscoveredDevice(
            ip: result.ip,
            mac: result.mac,
            reachable: reachable,
            verified: true,
          ),
        );
      }
      onStage?.call(PairingStage.complete);
      return checked;
    } finally {
      await _releaseProvisioningNetwork();
      _provisioningActive = false;
    }
  }

  Future<void> _releaseProvisioningNetwork() async {
    if (_nativeProvisioningHeld) {
      _nativeProvisioningHeld = false;
      await _networkService.endProvisioning();
    }
  }

  Future<void> cancelProvisioning() async {
    _networkGeneration++;
    if (!_provisioningActive) return;
    try {
      await _provisioning.cancel();
    } finally {
      await _releaseProvisioningNetwork();
    }
  }

  Future<String?> importRelayImage() => _images.importImage();

  static List<RelayDevice> _exampleDevices() {
    final now = DateTime.now();
    return [
      RelayDevice(
        id: 'demo-living',
        name: 'Living room board',
        room: 'Living room',
        ip: '192.0.2.10',
        demo: true,
        reachability: Reachability.online,
        lastSeen: now,
        relays: [
          RelayChannel(
            channel: 1,
            name: 'Table lamp',
            preset: 'table_lamp',
            lastState: true,
            lastSentAt: now,
          ),
          RelayChannel(
            channel: 2,
            name: 'Ceiling fan',
            preset: 'ceiling_fan',
            lastState: true,
            lastSentAt: now,
          ),
          RelayChannel(
            channel: 3,
            name: 'Television',
            preset: 'tv',
            lastState: false,
            lastSentAt: now,
          ),
          RelayChannel(
            channel: 4,
            name: 'Socket',
            preset: 'socket',
            lastState: false,
            lastSentAt: now,
          ),
        ],
      ),
      RelayDevice(
        id: 'demo-bedroom',
        name: 'Bedroom board',
        room: 'Bedroom',
        ip: '192.0.2.11',
        demo: true,
        reachability: Reachability.online,
        relays: [
          const RelayChannel(
            channel: 1,
            name: 'Bed lamp',
            preset: 'table_lamp',
            lastState: true,
          ),
          const RelayChannel(
            channel: 2,
            name: 'Room fan',
            preset: 'ceiling_fan',
            lastState: false,
          ),
          const RelayChannel(
            channel: 3,
            name: 'Wall light',
            preset: 'wall_light',
          ),
          const RelayChannel(
            channel: 4,
            name: 'Air conditioner',
            preset: 'ac',
            lastState: false,
          ),
        ],
      ),
      RelayDevice(
        id: 'demo-office-offline',
        name: 'Office board',
        room: 'Office',
        ip: '192.0.2.12',
        demo: true,
        relays: [
          const RelayChannel(
            channel: 1,
            name: 'Desk lamp',
            preset: 'table_lamp',
            lastState: true,
          ),
          const RelayChannel(
            channel: 2,
            name: 'Office fan',
            preset: 'standing_fan',
            lastState: true,
          ),
          const RelayChannel(
            channel: 3,
            name: 'Computer',
            preset: 'pc',
            lastState: false,
          ),
          const RelayChannel(
            channel: 4,
            name: 'Socket',
            preset: 'socket',
            lastState: false,
          ),
        ],
      ),
    ];
  }
}
