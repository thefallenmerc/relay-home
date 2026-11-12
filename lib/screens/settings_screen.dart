import 'package:flutter/material.dart';

import '../app_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            Text(
              'Make yourself\nat home.',
              style: text.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 28),
            Text('APPEARANCE', style: text.labelSmall),
            const SizedBox(height: 10),
            _SettingsSurface(
              children: [
                for (final entry in const <ThemeMode, (String, IconData)>{
                  ThemeMode.system: (
                    'Use device setting',
                    Icons.brightness_auto_outlined,
                  ),
                  ThemeMode.light: ('Light', Icons.light_mode_outlined),
                  ThemeMode.dark: ('Dark', Icons.dark_mode_outlined),
                }.entries)
                  ListTile(
                    leading: Icon(entry.value.$2),
                    title: Text(entry.value.$1),
                    trailing: Icon(
                      controller.themeMode == entry.key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: controller.themeMode == entry.key
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    selected: controller.themeMode == entry.key,
                    onTap: () => controller.setThemeMode(entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text('EXPLORE', style: text.labelSmall),
            const SizedBox(height: 10),
            _SettingsSurface(
              children: [
                SwitchListTile(
                  value: controller.demoMode,
                  onChanged: controller.setDemoMode,
                  title: const Text('Demo home'),
                  subtitle: const Text(
                    'Try sample boards with simulated controls. Real devices stay saved separately.',
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('NETWORK', style: text.labelSmall),
            const SizedBox(height: 10),
            _SettingsSurface(
              children: [
                ListTile(
                  leading: const Icon(Icons.wifi_rounded),
                  title: Text(
                    controller.demoMode
                        ? 'Demo network'
                        : controller.network?.ssid ?? 'Current Wi-Fi',
                  ),
                  subtitle: Text(
                    controller.demoMode
                        ? 'No commands are sent to real devices.'
                        : controller.network?.isWifi == true
                        ? controller.network?.ipv4 ?? 'Wi-Fi connected'
                        : 'Connect to the same Wi-Fi as your boards.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: controller.refreshing
                          ? null
                          : () async {
                              await controller.refreshNetwork(
                                requestPermission: true,
                              );
                              await controller.refreshDevices();
                            },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh network information'),
                    ),
                  ),
                ),
                if (controller.networkError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      controller.networkError!,
                      style: text.bodySmall?.copyWith(color: colors.error),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text('LOCAL BY DESIGN', style: text.labelSmall),
            const SizedBox(height: 12),
            Text(
              'Your home stays on your phone.',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Device names, rooms, artwork, and last commands are saved locally. No account or cloud service is needed. Wi-Fi passwords are used during setup and are not saved.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              'A relay’s physical position cannot be read from this board. Saved states show your last commands; reopening the app never sends them automatically.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            TextButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Relay Home',
                applicationVersion: '1.0.0',
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Open-source licenses'),
            ),
            Text(
              'Relay Home · Built for four little switches',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    },
  );
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}
