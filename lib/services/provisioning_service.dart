import 'dart:async';
import 'dart:isolate';
import 'package:esp_smartconfig/esp_smartconfig.dart';
import '../models.dart';

abstract class ProvisioningService {
  Future<List<DiscoveredDevice>> provision({
    required String ssid,
    required String password,
    String? bssid,
    void Function(PairingStage)? onStage,
  });
  Future<void> cancel();
  void dispose();
}

/// A fresh enclosing isolate owns each package instance. esp_smartconfig 3.0.0
/// closes its worker on stop(), but retains a ReceivePort in its caller. Exiting
/// our enclosing isolate after stop() releases that port without patching package.
class EspTouchProvisioningService implements ProvisioningService {
  Isolate? _isolate;
  SendPort? _control;
  Completer<List<DiscoveredDevice>>? _pending;
  Completer<void>? _stopped;
  bool _cancelRequested = false;
  final Duration timeout;
  EspTouchProvisioningService({this.timeout = const Duration(seconds: 90)});

  @override
  Future<List<DiscoveredDevice>> provision({
    required String ssid,
    required String password,
    String? bssid,
    void Function(PairingStage)? onStage,
  }) async {
    if (_pending != null) {
      throw StateError('A setup attempt is already running.');
    }
    final messages = ReceivePort();
    final pending = Completer<List<DiscoveredDevice>>();
    // Cancellation can arrive while Isolate.spawn is still being awaited.
    pending.future.ignore();
    final stopped = Completer<void>();
    _pending = pending;
    _stopped = stopped;
    _cancelRequested = false;
    final found = <String, DiscoveredDevice>{};
    Timer? responseWindow;
    final limit = Timer(timeout, () {
      if (!pending.isCompleted) {
        pending.completeError(
          TimeoutException(
            'No board replied. Check pairing mode and 2.4 GHz Wi-Fi.',
          ),
        );
      }
    });
    final subscription = messages.listen((dynamic message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'control':
          _control = message['port'] as SendPort;
          if (_cancelRequested) _control?.send('stop');
        case 'started':
          onStage?.call(PairingStage.waiting);
        case 'device':
          final ip = message['ip'] as String?;
          if (ip != null) {
            found[ip] = DiscoveredDevice(
              ip: ip,
              mac: message['mac'] as String?,
              verified: true,
            );
            // Brief window includes other boards that answered the same attempt.
            responseWindow ??= Timer(const Duration(seconds: 3), () {
              if (!pending.isCompleted) pending.complete(found.values.toList());
            });
          }
        case 'error':
          if (!pending.isCompleted) {
            pending.completeError(
              StateError(
                'Could not start or continue Wi-Fi setup. Check Wi-Fi and retry.',
              ),
            );
          }
        case 'stopped':
          if (!stopped.isCompleted) stopped.complete();
      }
    });
    try {
      onStage?.call(PairingStage.sending);
      _isolate = await Isolate.spawn(_runEspTouch, <String, Object?>{
        'port': messages.sendPort,
        'ssid': ssid,
        'password': password,
        'bssid': bssid,
      });
      if (_cancelRequested && !pending.isCompleted) {
        pending.completeError(const ProvisioningCancelled());
      }
      return await pending.future;
    } finally {
      limit.cancel();
      responseWindow?.cancel();
      _cancelRequested = true;
      _control?.send('stop');
      // The worker handshake may still be in flight immediately after spawn.
      try {
        await stopped.future.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        /* Defensive final cleanup. */
      }
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _control = null;
      messages.close();
      await subscription.cancel();
      _pending = null;
      _stopped = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _control?.send('stop');
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const ProvisioningCancelled());
    }
    final stopped = _stopped;
    if (stopped != null) {
      try {
        await stopped.future.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        /* Owner finally closes isolate. */
      }
    }
  }

  @override
  void dispose() {
    unawaited(cancel());
  }
}

class ProvisioningCancelled implements Exception {
  const ProvisioningCancelled();
  @override
  String toString() => 'Setup cancelled.';
}

void _runEspTouch(Map<String, Object?> input) async {
  final parent = input['port'] as SendPort;
  final commands = ReceivePort();
  final provisioner = Provisioner.espTouch();
  bool started = false, requestedStop = false, stopped = false;
  Future<void> stop() async {
    if (stopped) return;
    stopped = true;
    provisioner.stop(); // Kills package's UDP/timer worker before caller exits.
    commands.close();
    Isolate.exit(parent, {'type': 'stopped'});
  }

  commands.listen((dynamic _) {
    requestedStop = true;
    if (started) unawaited(stop());
  });
  parent.send({'type': 'control', 'port': commands.sendPort});
  provisioner.listen(
    (response) {
      parent.send({
        'type': 'device',
        'ip': response.ipAddressText,
        'mac': response.bssidText,
      });
    },
    onError: (Object _, StackTrace _) {
      parent.send({'type': 'error'});
      requestedStop = true;
      if (started) unawaited(stop());
    },
  );
  try {
    final password = input['password'] as String;
    await provisioner
        .start(
          ProvisioningRequest.fromStrings(
            ssid: input['ssid'] as String,
            password: password.isEmpty ? null : password,
            bssid: input['bssid'] as String? ?? '00:00:00:00:00:00',
          ),
        )
        .timeout(const Duration(seconds: 10));
    started = true;
    if (requestedStop) {
      await stop();
    } else {
      parent.send({'type': 'started'});
    }
  } on Object {
    parent.send({'type': 'error'});
    await stop();
  }
}
