import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_controller.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Archivo',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final controller = AppController();
  await controller.initialize();
  runApp(RelayHomeApp(controller: controller));
}

class RelayHomeApp extends StatefulWidget {
  const RelayHomeApp({super.key, required this.controller});
  final AppController controller;
  @override
  State<RelayHomeApp> createState() => _RelayHomeAppState();
}

class _RelayHomeAppState extends State<RelayHomeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshNetwork();
      widget.controller.refreshDevices();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.controller.cancelDiscovery();
      widget.controller.cancelProvisioning();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => MaterialApp(
      title: 'Relay Home',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: widget.controller.themeMode,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Theme.of(
                  context,
                ).scaffoldBackgroundColor,
              ),
          child: child!,
        );
      },
      home: HomeScreen(controller: widget.controller),
    ),
  );
}
