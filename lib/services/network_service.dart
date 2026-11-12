import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models.dart';

abstract class NetworkService {
  Future<NetworkSnapshot> snapshot({bool requestPermission = false});
  Stream<void> get changes;
  Future<void> beginProvisioning();
  Future<void> endProvisioning();
  void dispose();
}

class AndroidNetworkService implements NetworkService {
  static const _channel = MethodChannel('dev.relayhome/network');
  static const _events = EventChannel('dev.relayhome/network_events');
  @override
  Stream<void> get changes => Platform.isAndroid
      ? _events.receiveBroadcastStream().map((_) {})
      : const Stream.empty();
  @override
  Future<NetworkSnapshot> snapshot({bool requestPermission = false}) async {
    if (!Platform.isAndroid) return const NetworkSnapshot();
    final map = await _channel.invokeMapMethod<dynamic, dynamic>('snapshot', {
      'requestPermission': requestPermission,
    });
    return NetworkSnapshot.fromMap(map ?? {});
  }

  @override
  Future<void> beginProvisioning() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Provisioning is available in the Android app.');
    }
    await _channel.invokeMethod<void>('beginProvisioning');
  }

  @override
  Future<void> endProvisioning() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('endProvisioning');
    }
  }

  @override
  void dispose() {
    unawaited(endProvisioning().catchError((Object _) {}));
  }
}

int? ipv4Number(String text) {
  final parts = text.split('.');
  if (parts.length != 4) return null;
  var number = 0;
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    number = (number << 8) | value;
  }
  return number;
}

String ipv4Text(int value) =>
    [24, 16, 8, 0].map((s) => (value >> s) & 255).join('.');
bool isPrivateIpv4(String address) {
  final n = ipv4Number(address);
  return n != null &&
      ((n >> 24) == 10 || (n >> 20) == 0xac1 || (n >> 16) == 0xc0a8);
}

/// Refuses public or excessively broad scans rather than guessing a /24.
List<String> localHosts(NetworkSnapshot network, {int maximumHosts = 4094}) {
  final ip = ipv4Number(network.ipv4 ?? '');
  final mask = ipv4Number(network.subnetMask ?? '');
  if (!network.isWifi ||
      ip == null ||
      mask == null ||
      !isPrivateIpv4(network.ipv4!)) {
    throw StateError(
      'Connect to a private Wi-Fi network to find nearby boards.',
    );
  }
  final inverse = (~mask) & 0xffffffff;
  if ((inverse & (inverse + 1)) != 0 || inverse < 3) {
    throw StateError(
      'This Wi-Fi subnet cannot be scanned. Enter the board’s IP manually.',
    );
  }
  if (inverse - 1 > maximumHosts) {
    throw StateError(
      'This network is too large to scan safely. Enter the board’s IP manually.',
    );
  }
  final base = ip & mask;
  return [
    for (var host = base + 1; host < (base | inverse); host++)
      if (host != ip) ipv4Text(host),
  ];
}
