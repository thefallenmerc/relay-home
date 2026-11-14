import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_home/app_controller.dart';
import 'package:relay_home/models.dart';
import 'package:relay_home/services/network_service.dart';
import 'package:relay_home/services/provisioning_service.dart';
import 'package:relay_home/services/relay_transport.dart';
import 'package:relay_home/services/storage_service.dart';

class MemoryStorage implements AppStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class FakeNetwork implements NetworkService {
  Completer<void>? snapshotGate, beginGate;
  final beginEntered = Completer<void>();
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<NetworkSnapshot> snapshot({bool requestPermission = false}) async {
    if (requestPermission) await snapshotGate?.future;
    return const NetworkSnapshot(
      ssid: 'Test Wi-Fi',
      ipv4: '192.168.1.2',
      subnetMask: '255.255.255.0',
      isWifi: true,
      permissionGranted: true,
      frequencyMhz: 2412,
    );
  }

  int begins = 0, ends = 0;
  @override
  Future<void> beginProvisioning() async {
    begins++;
    if (!beginEntered.isCompleted) beginEntered.complete();
    await beginGate?.future;
  }

  @override
  Future<void> endProvisioning() async {
    ends++;
  }

  @override
  void dispose() {}
}

class FakeTransport implements RelayTransport {
  final List<(String, int, bool)> sends = [];
  int checks = 0;
  bool online = true;
  CommandResult next = const CommandResult(success: true, message: 'Sent');
  Completer<void>? gate;
  @override
  Future<bool> check(
    String ip, {
    int port = 8080,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    checks++;
    return online;
  }

  @override
  Future<CommandResult> send(
    String ip,
    int channel,
    bool on, {
    int port = 8080,
  }) async {
    sends.add((ip, channel, on));
    await gate?.future;
    return next;
  }

  @override
  void dispose() {}
}

class FakeProvisioning implements ProvisioningService {
  bool fail = false;
  int calls = 0;
  @override
  Future<List<DiscoveredDevice>> provision({
    required String ssid,
    required String password,
    String? bssid,
    void Function(PairingStage)? onStage,
  }) async {
    calls++;
    if (fail) throw TimeoutException('Timed out');
    return [
      const DiscoveredDevice(
        ip: '192.168.1.40',
        mac: 'aa:bb:cc:dd:ee:ff',
        verified: true,
      ),
    ];
  }

  @override
  Future<void> cancel() async {}
  @override
  void dispose() {}
}

RelayDevice fixture() => RelayDevice(
  id: 'real-board',
  name: 'My board',
  room: 'Living room',
  ip: '192.168.1.10',
  relays: List.generate(
    4,
    (i) => RelayChannel(channel: i + 1, name: 'Relay ${i + 1}'),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryStorage storage;
  late FakeTransport transport;
  late FakeNetwork network;
  late FakeProvisioning provisioning;
  late AppController controller;
  setUp(() async {
    storage = MemoryStorage();
    transport = FakeTransport();
    network = FakeNetwork();
    provisioning = FakeProvisioning();
    controller = AppController(
      storage: storage,
      transport: transport,
      networkService: network,
      provisioning: provisioning,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());
  test('fresh install starts empty in real mode', () {
    expect(controller.demoMode, false);
    expect(controller.devices, isEmpty);
    expect(transport.sends, isEmpty);
  });
  test('saved states restore without automatic command replay', () async {
    await controller.saveDevice(fixture());
    await controller.toggleRelay('real-board', 2, true);
    final second = FakeTransport();
    final reopened = AppController(
      storage: storage,
      transport: second,
      networkService: FakeNetwork(),
      provisioning: FakeProvisioning(),
    );
    await reopened.initialize();
    expect(reopened.devices.single.relays[1].lastState, true);
    expect(reopened.devices.single.relays[0].lastState, isNull);
    expect(reopened.devices.single.relays[1].lastSentAt, isNotNull);
    expect(second.sends, isEmpty);
    reopened.dispose();
  });
  test(
    'send failure preserves state; ambiguous outcome marks uncertainty',
    () async {
      await controller.saveDevice(fixture());
      await controller.toggleRelay('real-board', 1, true);
      transport.next = const CommandResult(
        success: false,
        message: 'Could not connect',
      );
      await controller.toggleRelay('real-board', 1, false);
      expect(controller.devices.single.relays.first.lastState, true);
      expect(controller.devices.single.relays.first.uncertain, false);
      transport.next = const CommandResult(
        success: false,
        uncertain: true,
        message: 'Interrupted',
      );
      await controller.toggleRelay('real-board', 1, false);
      expect(controller.devices.single.relays.first.lastState, true);
      expect(controller.devices.single.relays.first.uncertain, true);
    },
  );
  test('board commands cannot overlap across channels', () async {
    await controller.saveDevice(fixture());
    transport.gate = Completer<void>();
    final first = controller.toggleRelay('real-board', 1, true);
    expect(controller.isDeviceBusy('real-board'), true);
    expect(controller.isSending('real-board', 1), true);
    expect(controller.isSending('real-board', 4), false);
    expect(controller.pendingRelayState('real-board', 1), true);
    expect(controller.pendingRelayState('real-board', 2), isNull);
    final conflict = await controller.toggleRelay('real-board', 2, true);
    expect(conflict.success, false);
    expect(transport.sends.length, 1);
    transport.gate!.complete();
    await first;
    expect(controller.isSending('real-board', 1), false);
    expect(controller.pendingRelayState('real-board', 1), isNull);
  });
  for (final result in [
    const CommandResult(success: true, message: 'Sent'),
    const CommandResult(success: false, message: 'Not connected'),
    const CommandResult(
      success: false,
      uncertain: true,
      message: 'Interrupted',
    ),
  ]) {
    test(
      'optimistic state is transient until send resolves: ${result.message}',
      () async {
        await controller.saveDevice(fixture());
        await controller.toggleRelay('real-board', 1, false);
        final savedBefore = storage.values['real_devices_v1'];
        transport.gate = Completer<void>();
        transport.next = result;
        final operation = controller.toggleRelay('real-board', 1, true);
        expect(controller.pendingRelayState('real-board', 1), true);
        expect(controller.devices.single.relays.first.lastState, false);
        expect(storage.values['real_devices_v1'], savedBefore);
        transport.gate!.complete();
        await operation;
        expect(controller.pendingRelayState('real-board', 1), isNull);
        expect(controller.isDeviceBusy('real-board'), false);
        final relay = controller.devices.single.relays.first;
        expect(relay.lastState, result.success);
        expect(relay.uncertain, result.uncertain);
        final persisted = decodeDevices(storage.values['real_devices_v1']);
        expect(persisted.single.relays.first.lastState, result.success);
      },
    );
  }
  test(
    'demo records are isolated and never invoke the real transport',
    () async {
      await controller.saveDevice(fixture());
      final checks = transport.checks;
      await controller.setDemoMode(true);
      final demo = controller.devices.first;
      await controller.toggleRelay(demo.id, 1, false);
      await controller.refreshDevices();
      await controller.discover();
      expect(transport.sends, isEmpty);
      expect(transport.checks, checks);
      expect(controller.devices.every((d) => d.demo), true);
      await controller.setDemoMode(false);
      expect(controller.devices.single.id, 'real-board');
      expect(controller.devices.single.relays.first.lastState, isNull);
    },
  );
  test('apply saved states only sends known channels in order', () async {
    await controller.saveDevice(
      fixture().copyWith(
        relays: [
          const RelayChannel(channel: 1, name: 'One', lastState: true),
          const RelayChannel(channel: 2, name: 'Two'),
          const RelayChannel(channel: 3, name: 'Three', lastState: false),
          const RelayChannel(channel: 4, name: 'Four'),
        ],
      ),
    );
    expect((await controller.applySavedStates('real-board')).success, true);
    expect(transport.sends, [
      ('192.168.1.10', 1, true),
      ('192.168.1.10', 3, false),
    ]);
  });
  test(
    'duplicate address cannot silently replace existing saved board',
    () async {
      await controller.saveDevice(fixture());
      await expectLater(
        controller.saveDevice(fixture().copyWith(id: 'other')),
        throwsStateError,
      );
      expect(controller.devices.length, 1);
    },
  );
  test(
    'pairing releases resources on success and timeout without saving password',
    () async {
      final found = await controller.provision(
        ssid: 'Test Wi-Fi',
        password: 'testpass123',
      );
      expect(found.single.reachable, true);
      expect(found.single.verified, true);
      expect(network.begins, 1);
      expect(network.ends, 1);
      provisioning.fail = true;
      await expectLater(
        controller.provision(ssid: 'Test Wi-Fi', password: 'testpass123'),
        throwsA(isA<TimeoutException>()),
      );
      expect(network.begins, 2);
      expect(network.ends, 2);
      expect(storage.values.toString(), isNot(contains('testpass123')));
    },
  );
  test(
    'cancel while permission information is pending never starts setup',
    () async {
      network.snapshotGate = Completer<void>();
      final operation = controller.provision(
        ssid: 'Test Wi-Fi',
        password: 'testpass123',
      );
      final expectation = expectLater(
        operation,
        throwsA(isA<ProvisioningCancelled>()),
      );
      await controller.cancelProvisioning();
      network.snapshotGate!.complete();
      await expectation;
      expect(network.begins, 0);
      expect(provisioning.calls, 0);
      expect(network.ends, 0);
    },
  );
  test(
    'cancel during native binding releases binding and never broadcasts',
    () async {
      network.beginGate = Completer<void>();
      final operation = controller.provision(
        ssid: 'Test Wi-Fi',
        password: 'testpass123',
      );
      final expectation = expectLater(
        operation,
        throwsA(isA<ProvisioningCancelled>()),
      );
      await network.beginEntered.future;
      await controller.cancelProvisioning();
      network.beginGate!.complete();
      await expectation;
      expect(network.begins, 1);
      expect(network.ends, 1);
      expect(provisioning.calls, 0);
    },
  );
  test(
    'changed address during a send cannot mark the new target online',
    () async {
      await controller.saveDevice(fixture());
      transport.gate = Completer<void>();
      final operation = controller.toggleRelay('real-board', 1, true);
      await controller.updateDeviceAddress('real-board', '192.168.1.41');
      transport.gate!.complete();
      final result = await operation;
      expect(result.uncertain, true);
      expect(result.success, false);
      expect(controller.devices.single.ip, '192.168.1.41');
      expect(controller.devices.single.reachability, Reachability.offline);
      expect(controller.devices.single.relays.first.lastState, isNull);
      expect(controller.devices.single.relays.first.uncertain, true);
    },
  );
}
