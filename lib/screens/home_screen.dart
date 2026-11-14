import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';
import '../widgets/appliance_art.dart';
import '../widgets/common.dart';
import '../widgets/relay_tile.dart';
import 'device_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _room;

  void _addDevice() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SetupScreen(controller: widget.controller),
    ),
  );

  Future<void> _refresh() async {
    await widget.controller.refreshNetwork();
    await widget.controller.refreshDevices();
  }

  Future<void> _send(RelayDevice device, RelayChannel relay, bool on) async {
    HapticFeedback.selectionClick();
    final result = await widget.controller.toggleRelay(
      device.id,
      relay.channel,
      on,
    );
    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final colors = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      final rooms = controller.devices.map((device) => device.room).toSet()
        ..removeWhere((room) => room.trim().isEmpty);
      final selectedRoom = rooms.contains(_room) ? _room : null;
      final devices = controller.devices
          .where(
            (device) => selectedRoom == null || device.room == selectedRoom,
          )
          .toList();

      return Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RelayMark(size: 29),
              const SizedBox(width: 9),
              const Flexible(
                child: Text(
                  'RELAY HOME',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (controller.demoMode) ...[
                const SizedBox(width: 8),
                const _DemoBadge(),
              ],
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(controller: controller),
                ),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Home',
                style: text.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.9,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Simple control. All local.',
                style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              _NetworkLine(controller: controller),
              if (controller.devices.isNotEmpty) ...[
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('All rooms'),
                          selected: selectedRoom == null,
                          onSelected: (_) => setState(() => _room = null),
                          showCheckmark: false,
                        ),
                      ),
                      for (final room in rooms)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(room),
                            selected: selectedRoom == room,
                            onSelected: (_) => setState(() => _room = room),
                            showCheckmark: false,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final device in devices) ...[
                  _boardCard(context, device),
                  const SizedBox(height: 12),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Text(
                    'States shown are your last commands.',
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ] else
                _emptyHome(context),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: FilledButton.icon(
            onPressed: _addDevice,
            icon: const Icon(Icons.add),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Add device'),
            ),
          ),
        ),
      );
    },
  );

  Widget _emptyHome(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Center(
              child: ApplianceArt(preset: 'board', size: 170),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'A little board.\nA more connected home.',
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'Add your first four-relay device. Give each switch a name, and make it yours.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (!widget.controller.demoMode) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => widget.controller.setDemoMode(true),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Explore a demo home'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _boardCard(BuildContext context, RelayDevice device) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final online = device.reachability == Reachability.online;
    final busy = widget.controller.isDeviceBusy(device.id);
    final onCount = device.relays
        .where((relay) => relay.lastState == true)
        .length;
    final uncertain = device.relays.any((relay) => relay.uncertain);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(23),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeviceScreen(
                    controller: widget.controller,
                    deviceId: device.id,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(3, 3, 3, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: ApplianceArt(preset: device.preset, size: 30),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            device.name,
                            style: text.titleLarge?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.4,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 21),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${device.room} · 4 relays',
                          style: text.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        DeviceReachability(reachability: device.reachability),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            RelayGrid(
              children: [
                for (final relay in device.relays)
                  RelayTile(
                    relay: relay,
                    online: online,
                    sending: widget.controller.isSending(
                      device.id,
                      relay.channel,
                    ),
                    pendingState: widget.controller.pendingRelayState(
                      device.id,
                      relay.channel,
                    ),
                    compact: true,
                    onChanged: busy ? null : (on) => _send(device, relay, on),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 10, 3, 0),
              child: Text(
                '$onCount of 4 last set on${uncertain ? ' · Some results uncertain' : ''}',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            if (!online) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: device.reachability == Reachability.checking
                      ? null
                      : () => widget.controller.checkDevice(device.id),
                  child: Text(
                    device.reachability == Reachability.checking
                        ? 'Checking connection…'
                        : 'Check connection',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DeviceReachability extends StatelessWidget {
  const DeviceReachability({super.key, required this.reachability});
  final Reachability reachability;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = switch (reachability) {
      Reachability.online => 'Reachable',
      Reachability.checking => 'Checking',
      Reachability.offline => 'Offline',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: reachability == Reachability.online
                ? colors.primary
                : colors.onSurfaceVariant.withValues(alpha: .55),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _NetworkLine extends StatelessWidget {
  const _NetworkLine({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final network = controller.network;
    final label = controller.demoMode
        ? 'Demo network · Simulated controls'
        : network?.isWifi == true
        ? network?.ssid ?? 'Wi-Fi connected'
        : 'Connect to your home Wi-Fi';
    return Row(
      children: [
        Icon(
          network?.isWifi == true || controller.demoMode
              ? Icons.wifi_rounded
              : Icons.wifi_off_rounded,
          size: 17,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        if (controller.refreshing)
          const Padding(
            padding: EdgeInsets.all(15),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            tooltip: 'Refresh network and devices',
            icon: const Icon(Icons.refresh_rounded, size: 21),
            onPressed: () async {
              await controller.refreshNetwork();
              await controller.refreshDevices();
            },
          ),
      ],
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'DEMO',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
  );
}
