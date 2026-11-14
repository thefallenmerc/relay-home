import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_home/app_controller.dart';
import 'package:relay_home/models.dart';
import 'package:relay_home/screens/device_screen.dart';
import 'package:relay_home/screens/home_screen.dart';
import 'package:relay_home/theme.dart';
import 'package:relay_home/widgets/relay_tile.dart';
import 'package:relay_home/widgets/appliance_art.dart';
import 'dart:async';
import 'controller_test.dart' as fixtures;

class UiController extends AppController {
  UiController({bool online = true}) : _online = online;
  bool _online;
  final List<(int, bool)> commands = [];
  final _relays = [
    const RelayChannel(
      channel: 1,
      name: 'Table lamp',
      preset: 'table_lamp',
      lastState: true,
    ),
    const RelayChannel(
      channel: 2,
      name: 'Ceiling fan',
      preset: 'ceiling_fan',
      lastState: false,
    ),
    const RelayChannel(channel: 3, name: 'Television', preset: 'tv'),
    const RelayChannel(
      channel: 4,
      name: 'Socket',
      preset: 'socket',
      lastState: true,
      uncertain: true,
    ),
  ];
  @override
  List<RelayDevice> get devices => [
    RelayDevice(
      id: 'board',
      name: 'Living room board',
      room: 'Living room',
      ip: '192.168.1.10',
      relays: _relays,
      reachability: _online ? Reachability.online : Reachability.offline,
    ),
  ];
  @override
  NetworkSnapshot get network =>
      const NetworkSnapshot(isWifi: true, ssid: 'Home Wi-Fi');
  @override
  RelayDevice? deviceById(String id) => id == 'board' ? devices.first : null;
  @override
  Future<CommandResult> toggleRelay(String id, int channel, bool on) async {
    commands.add((channel, on));
    final index = _relays.indexWhere((relay) => relay.channel == channel);
    _relays[index] = _relays[index].copyWith(lastState: on, uncertain: false);
    notifyListeners();
    return const CommandResult(success: true, message: 'Command sent');
  }

  @override
  Future<bool> checkDevice(String id) async {
    _online = true;
    notifyListeners();
    return true;
  }
}

Widget testApp(Widget child, {double scale = 1}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  for (final detail in [false, true]) {
    testWidgets(
      '${detail ? 'device' : 'home'} switch responds before send and reverts on failure',
      (tester) async {
        final transport = fixtures.FakeTransport();
        final controller = AppController(
          storage: fixtures.MemoryStorage(),
          transport: transport,
          networkService: fixtures.FakeNetwork(),
          provisioning: fixtures.FakeProvisioning(),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.saveDevice(fixtures.fixture());
        await controller.toggleRelay('real-board', 1, false);
        await tester.pumpWidget(
          testApp(
            detail
                ? DeviceScreen(controller: controller, deviceId: 'real-board')
                : HomeScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        transport.gate = Completer<void>();
        transport.next = const CommandResult(
          success: false,
          message: 'Could not connect',
        );
        await tester.tap(find.byType(Switch).first);
        await tester.pump();
        expect(tester.widget<Switch>(find.byType(Switch).first).value, true);
        final tile = find.byType(RelayTile).first;
        final art = find.descendant(
          of: tile,
          matching: find.byType(ApplianceArt),
        );
        expect(tester.widget<ApplianceArt>(art).on, true);
        expect(find.text('Setting On…'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(controller.devices.single.relays.first.lastState, false);
        transport.gate!.complete();
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(find.byType(Switch).first).value, false);
        expect(find.text('Last set Off'), findsOneWidget);
        expect(find.text('Could not connect'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('offline saved ON remains ON and cannot send', (tester) async {
    bool changed = false;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: RelayTile(
            relay: const RelayChannel(
              channel: 1,
              name: 'Lamp',
              lastState: true,
            ),
            online: false,
            sending: false,
            onChanged: (_) => changed = true,
          ),
        ),
      ),
    );
    final control = tester.widget<Switch>(find.byType(Switch));
    expect(control.value, isTrue);
    expect(control.onChanged, isNull);
    expect(find.text('Last set On'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(changed, isFalse);
  });

  testWidgets('unknown and uncertain states are explicit', (tester) async {
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Column(
            children: [
              RelayTile(
                relay: const RelayChannel(channel: 1, name: 'Unknown relay'),
                online: true,
                sending: false,
                onChanged: (_) {},
                compact: true,
              ),
              RelayTile(
                relay: const RelayChannel(
                  channel: 2,
                  name: 'Uncertain relay',
                  lastState: true,
                  uncertain: true,
                ),
                online: true,
                sending: false,
                onChanged: (_) {},
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Last set Unknown'), findsOneWidget);
    expect(find.text('Last set Uncertain'), findsOneWidget);
  });

  testWidgets('narrow home controls send exactly the selected channel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = UiController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(testApp(HomeScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Switch), findsNWidgets(4));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(controller.commands, [(1, false)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text device controls scroll without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = UiController(online: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      testApp(
        DeviceScreen(controller: controller, deviceId: 'board'),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.commands, isEmpty);
  });
}
