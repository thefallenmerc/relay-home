import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';
import '../widgets/relay_tile.dart';
import 'device_editor.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.controller,
    required this.deviceId,
  });
  final AppController controller;
  final String deviceId;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  bool _applying = false;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send(RelayChannel relay, bool on) async {
    HapticFeedback.selectionClick();
    final result = await widget.controller.toggleRelay(
      widget.deviceId,
      relay.channel,
      on,
    );
    if (!result.success) _message(result.message);
  }

  Future<void> _applySaved() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply saved states?'),
        content: const Text(
          'This sends your saved On and Off commands to this board now. Relays with no saved state are left alone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply states'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _applying = true);
    try {
      final result = await widget.controller.applySavedStates(widget.deviceId);
      _message(result.message);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _editRelay(RelayChannel relay) async {
    final edited = await showRelayEditor(
      context,
      controller: widget.controller,
      relay: relay,
    );
    final current = widget.controller.deviceById(widget.deviceId);
    if (edited == null || current == null || !mounted) return;
    final updated = current.copyWith(
      relays: [
        for (final item in current.relays)
          if (item.channel == edited.channel)
            item.copyWith(
              name: edited.name,
              preset: edited.preset,
              customImagePath: edited.customImagePath,
              clearCustomImage: edited.customImagePath == null,
            )
          else
            item,
      ],
    );
    try {
      await widget.controller.saveDevice(updated);
    } catch (_) {
      _message('Could not save that relay. Try again.');
    }
  }

  Future<void> _editAddress(RelayDevice device) async {
    final address = await showDialog<String>(
      context: context,
      builder: (_) => _AddressDialog(initialAddress: device.ip),
    );
    if (address == null || !mounted) return;
    await _saveAddress(address);
  }

  Future<void> _saveAddress(String address) async {
    try {
      await widget.controller.updateDeviceAddress(widget.deviceId, address);
      final online =
          widget.controller.deviceById(widget.deviceId)?.reachability ==
          Reachability.online;
      _message(
        online
            ? 'Address saved. The control port is reachable.'
            : 'Address saved. The board is not reachable yet.',
      );
    } catch (_) {
      _message('Could not update this address. Check the IP and try again.');
    }
  }

  Future<void> _findAddress() async {
    final address = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FindAddressSheet(controller: widget.controller),
    );
    if (address != null && mounted) await _saveAddress(address);
  }

  Future<void> _remove(RelayDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${device.name}?'),
        content: const Text(
          'This removes its names, artwork references, and saved states from this app. The board itself is not reset.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep device'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Remove',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.removeDevice(widget.deviceId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _message('Could not remove the device. Try again.');
    }
  }

  void _details(RelayDevice device) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device details',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _detailRow('Address', '${device.ip}:${device.port}'),
            if (device.mac != null) _detailRow('MAC address', device.mac!),
            _detailRow('Room', device.room),
            _detailRow(
              'Last reachable',
              device.lastSeen == null
                  ? 'Not yet checked'
                  : _date(device.lastSeen!),
            ),
            if (device.demo) _detailRow('Mode', 'Demo · simulated device'),
            const Divider(height: 28),
            Text(
              'About saved states',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'This board accepts On and Off commands but does not report its physical relay state. “Last set” records the commands this app sent. Another controller or a board restart can change the outputs without updating this app.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Saved states return when you reopen the app. Commands are only sent when you choose a control or Apply saved states.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        SelectableText(value),
      ],
    ),
  );

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _menu(String action, RelayDevice device) {
    switch (action) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute<RelayDevice>(
            builder: (_) =>
                DeviceEditor(controller: widget.controller, device: device),
          ),
        );
      case 'details':
        _details(device);
      case 'find':
        _findAddress();
      case 'address':
        _editAddress(device);
      case 'wifi':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SetupScreen(
              controller: widget.controller,
              reconfigureDevice: device,
            ),
          ),
        );
      case 'remove':
        _remove(device);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final device = widget.controller.deviceById(widget.deviceId);
      if (device == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(
            child: Text('This device is no longer in your home.'),
          ),
        );
      }
      final colors = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      final online = device.reachability == Reachability.online;
      final busy = _applying || widget.controller.isDeviceBusy(device.id);
      return Scaffold(
        appBar: AppBar(
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Device options',
              onSelected: (action) => _menu(action, device),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit device')),
                PopupMenuItem(value: 'details', child: Text('Device details')),
                PopupMenuItem(value: 'find', child: Text('Find device again')),
                PopupMenuItem(
                  value: 'address',
                  child: Text('Update IP address'),
                ),
                PopupMenuItem(value: 'wifi', child: Text('Reconfigure Wi-Fi')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'remove', child: Text('Remove from app')),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            Text(
              device.name,
              style: text.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -.9,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  device.room,
                  style: text.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                DeviceReachability(reachability: device.reachability),
                if (device.demo)
                  Text(
                    'DEMO',
                    style: text.labelSmall?.copyWith(color: colors.primary),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            if (!online)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 31),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.reachability == Reachability.checking
                                ? 'Checking your board'
                                : 'Can’t reach this board',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text('Your last commands are still saved.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Material(
              color: colors.surfaceContainerHighest.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                onTap: () => _details(device),
                borderRadius: BorderRadius.circular(17),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 21),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Last set states · No physical feedback'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            RelayGrid(
              gap: 12,
              children: [
                for (final relay in device.relays)
                  RelayTile(
                    relay: relay,
                    online: online,
                    sending: widget.controller.isSending(
                      device.id,
                      relay.channel,
                    ),
                    onChanged: busy ? null : (value) => _send(relay, value),
                    onEdit: busy ? null : () => _editRelay(relay),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (online) ...[
              OutlinedButton(
                onPressed:
                    busy ||
                        !device.relays.any((relay) => relay.lastState != null)
                    ? null
                    : _applySaved,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _applying ? 'Applying states…' : 'Apply saved states',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Only sends when you choose.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ] else ...[
              Text(
                'Connect to the same Wi-Fi network and check the board’s power.',
                style: text.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: device.reachability == Reachability.checking
                    ? null
                    : () => widget.controller.checkDevice(device.id),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Check connection'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => _editAddress(device),
                child: const Text('Update IP address'),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog({required this.initialAddress});
  final String initialAddress;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: widget.initialAddress);
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Update IP address'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Use the address assigned to this board by your router.'),
          const SizedBox(height: 18),
          TextFormField(
            controller: _address,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'IPv4 address'),
            validator: (value) {
              final ip = InternetAddress.tryParse(value?.trim() ?? '');
              return ip?.type == InternetAddressType.IPv4
                  ? null
                  : 'Enter a valid IPv4 address.';
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _address.text.trim());
          }
        },
        child: const Text('Save address'),
      ),
    ],
  );
}

class _FindAddressSheet extends StatefulWidget {
  const _FindAddressSheet({required this.controller});
  final AppController controller;

  @override
  State<_FindAddressSheet> createState() => _FindAddressSheetState();
}

class _FindAddressSheetState extends State<_FindAddressSheet> {
  bool _searching = true;
  String? _error;
  int _checked = 0;
  int _total = 0;
  List<DiscoveredDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
      _devices = [];
      _checked = 0;
      _total = 0;
    });
    try {
      final results = await widget.controller.discover(
        onProgress: (checked, total) {
          if (mounted) {
            setState(() {
              _checked = checked;
              _total = total;
            });
          }
        },
      );
      if (mounted) setState(() => _devices = results);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not search this network. Check your Wi-Fi connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    widget.controller.cancelDiscovery();
    super.dispose();
  }

  Future<void> _choose(DiscoveredDevice candidate) async {
    final choose = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Use ${candidate.ip}?'),
        content: const Text(
          'A matching control port is open here, but it does not identify the board. Confirm this address belongs to your device using your router’s device list before saving it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use address'),
          ),
        ],
      ),
    );
    if (choose == true && mounted) Navigator.pop(context, candidate.ip);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .7,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      children: [
        Text(
          'Find device again',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        const Text(
          'Searching your current Wi-Fi for possible relay boards. Choose an address only when you recognize it.',
        ),
        const SizedBox(height: 24),
        if (_searching) ...[
          LinearProgressIndicator(
            value: _total == 0 ? null : _checked / _total,
          ),
          const SizedBox(height: 12),
          Text(
            _total == 0
                ? 'Finding this network…'
                : 'Checked $_checked of $_total addresses',
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel search'),
          ),
        ] else ...[
          if (_error != null)
            Text(_error!)
          else if (_devices.isEmpty)
            const Text(
              'No possible devices found. Check the board’s power and that it is on the same Wi-Fi network.',
            ),
          for (final candidate in _devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.router_outlined),
              title: Text(candidate.ip),
              subtitle: const Text('Possible device · identity unconfirmed'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _choose(candidate),
            ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _search,
            icon: const Icon(Icons.refresh),
            label: const Text('Search again'),
          ),
        ],
      ],
    ),
  );
}
