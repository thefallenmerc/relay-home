import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_home/app_controller.dart';
import 'package:relay_home/main.dart';
import 'package:relay_home/screens/device_screen.dart';
import 'package:relay_home/screens/device_editor.dart';
import 'package:relay_home/screens/setup_screen.dart';
import 'package:relay_home/theme.dart';
import 'package:relay_home/widgets/appliance_art.dart';
import 'package:relay_home/models.dart';
import 'controller_test.dart'
    show MemoryStorage, FakeNetwork, FakeTransport, FakeProvisioning;

const capture = bool.fromEnvironment('CAPTURE_SCREENS');

Future<void> screen(WidgetTester tester, String name) async {
  if (!capture) return;
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
  });
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../docs/screenshots/$name.png'),
  );
}

void main() {
  setUpAll(() async {
    final archivo = FontLoader('Archivo')
      ..addFont(rootBundle.load('assets/fonts/Archivo.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await archivo.load();
    await icons.load();
  });
  late AppController controller;
  late MemoryStorage storage;
  late FakeTransport transport;
  setUp(() async {
    ApplianceArt.clearCacheForTesting();
    storage = MemoryStorage();
    transport = FakeTransport();
    controller = AppController(
      storage: storage,
      networkService: FakeNetwork(),
      transport: transport,
      provisioning: FakeProvisioning(),
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());

  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'fresh install, pairing, personalization and save have a complete working path',
    (tester) async {
      await size(tester);
      await tester.pumpWidget(RelayHomeApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(controller.devices, isEmpty);
      await screen(tester, 'empty-home');
      await tester.tap(find.text('Add device').last);
      await tester.pumpAndSettle();
      expect(find.byType(SetupScreen), findsOneWidget);
      await screen(tester, 'prepare');
      await tester.ensureVisible(find.text('Board is ready'));
      await tester.tap(find.text('Board is ready'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to Wi-Fi'), findsOneWidget);
      expect(find.text('Test Wi-Fi'), findsOneWidget);
      await screen(tester, 'wifi-setup');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'test-password-only',
      );
      await tester.ensureVisible(find.text('Connect device'));
      await tester.tap(find.text('Connect device'));
      await tester.pumpAndSettle();
      expect(find.text('Your board is on Wi-Fi'), findsOneWidget);
      expect(find.text('192.168.1.40'), findsOneWidget);
      await tester.tap(find.text('ESP relay board'));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceEditor), findsOneWidget);
      await screen(tester, 'personalize');
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Dining room lights',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Dining room');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.dragUntilVisible(
        find.text('Save device'),
        find.byType(ListView).last,
        const Offset(0, -400),
      );
      await tester.tap(find.text('Save device'));
      await tester.pumpAndSettle();
      expect(controller.devices.single.name, 'Dining room lights');
      expect(controller.devices.single.room, 'Dining room');
      expect(controller.devices.single.ip, '192.168.1.40');
      expect(
        controller.devices.single.relays.every((r) => r.lastState == null),
        isTrue,
      );
      expect(
        storage.values.values.any((s) => s.contains('test-password-only')),
        isFalse,
      );
      expect(transport.sends, isEmpty);
      expect(find.byType(SetupScreen), findsNothing);
    },
  );

  testWidgets(
    'demo home and details render in both themes with saved state intact',
    (tester) async {
      await size(tester);
      await tester.runAsync(() => controller.setDemoMode(true));
      await tester.runAsync(() => controller.setThemeMode(ThemeMode.light));
      await tester.pumpWidget(RelayHomeApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('DEMO'), findsOneWidget);
      await screen(tester, 'home-light');
      await tester.runAsync(() => controller.setThemeMode(ThemeMode.dark));
      await tester.pumpAndSettle();
      await screen(tester, 'home-dark');
      await tester.runAsync(() => controller.setThemeMode(ThemeMode.light));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Living room board'));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceScreen), findsOneWidget);
      expect(find.text('Table lamp'), findsOneWidget);
      await screen(tester, 'relay-controls');
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch).first);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(
        controller.deviceById('demo-living')!.relays.first.lastState,
        false,
      );
      expect(transport.sends, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reconfiguration updates address and preserves custom relay history',
    (tester) async {
      await size(tester);
      final original = RelayDevice(
        id: 'rejoining-board',
        name: 'Kitchen board',
        room: 'Kitchen',
        ip: '192.168.1.10',
        relays: List.generate(
          4,
          (i) => RelayChannel(
            channel: i + 1,
            name: i == 0 ? 'Counter light' : 'Relay ${i + 1}',
            lastState: i < 2,
          ),
        ),
      );
      await tester.runAsync(() => controller.saveDevice(original));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          home: DeviceEditor(
            controller: controller,
            device: original.copyWith(ip: '192.168.1.77'),
            updateConnection: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Save device'),
        find.byType(ListView).last,
        const Offset(0, -400),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save device'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      final saved = controller.devices.single;
      expect(saved.ip, '192.168.1.77');
      expect(saved.id, original.id);
      expect(saved.relays.first.name, 'Counter light');
      expect(saved.relays.first.lastState, isTrue);
      expect(transport.sends, isEmpty);
    },
  );

  testWidgets('offline recovery retains last ON state without transmitting', (
    tester,
  ) async {
    await size(tester);
    await tester.runAsync(() => controller.setDemoMode(true));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: DeviceScreen(
          controller: controller,
          deviceId: 'demo-office-offline',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    await screen(tester, 'offline-recovery');
    expect(transport.sends, isEmpty);
  });
}
