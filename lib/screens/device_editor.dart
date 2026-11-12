import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../widgets/appliance_art.dart';

const deviceIconPresets = <String, String>{
  'board': 'Relay board',
  'lighting_board': 'Lighting',
  'appliance_board': 'Appliances',
};

class DeviceEditor extends StatefulWidget {
  const DeviceEditor({
    super.key,
    required this.controller,
    required this.device,
    this.isNew = false,
    this.updateConnection = false,
  });
  final AppController controller;
  final RelayDevice device;
  final bool isNew;
  final bool updateConnection;

  @override
  State<DeviceEditor> createState() => _DeviceEditorState();
}

class _DeviceEditorState extends State<DeviceEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _room;
  late List<RelayChannel> _relays;
  late String _preset;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.device.name);
    _room = TextEditingController(text: widget.device.room);
    _relays = List.of(widget.device.relays);
    _preset = widget.device.preset;
  }

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Use current records so editing metadata cannot overwrite a newly sent
      // relay state or a connectivity refresh that completed during editing.
      final latest = widget.controller.deviceById(widget.device.id);
      final device = (latest ?? widget.device).copyWith(
        name: _name.text.trim(),
        room: _room.text.trim(),
        preset: _preset,
        ip: widget.updateConnection ? widget.device.ip : null,
        port: widget.updateConnection ? widget.device.port : null,
        mac: widget.updateConnection ? widget.device.mac : null,
        reachability: widget.updateConnection
            ? widget.device.reachability
            : null,
        lastSeen: widget.updateConnection ? widget.device.lastSeen : null,
        relays: [
          for (final edited in _relays)
            (latest?.relays.firstWhere(
                      (relay) => relay.channel == edited.channel,
                      orElse: () => edited,
                    ) ??
                    edited)
                .copyWith(
                  name: edited.name,
                  preset: edited.preset,
                  customImagePath: edited.customImagePath,
                  clearCustomImage: edited.customImagePath == null,
                ),
        ],
      );
      await widget.controller.saveDevice(device);
      if (mounted) Navigator.of(context).pop(device);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this device. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editRelay(int index) async {
    final relay = await showRelayEditor(
      context,
      controller: widget.controller,
      relay: _relays[index],
    );
    if (relay != null && mounted) {
      setState(() => _relays[index] = relay);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rooms = <String>{
      'Living room',
      'Bedroom',
      'Kitchen',
      'Office',
      ...widget.controller.devices.map((device) => device.room),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Device added' : 'Edit device'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Text(
              widget.isNew
                  ? 'Make it yours'
                  : 'Familiar names.\nYour own style.',
              style: text.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Give your board and relays familiar names.',
              style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (widget.device.demo) ...[
              const SizedBox(height: 12),
              const Text('Demo device · Stored separately from real devices'),
            ],
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Device name'),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Give this device a name.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _room,
              decoration: const InputDecoration(
                labelText: 'Room',
                helperText: 'Choose a room below or type your own.',
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 40,
              onChanged: (_) => setState(() {}),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Choose or name a room.'
                  : null,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 7,
              runSpacing: 4,
              children: [
                for (final room in rooms)
                  ChoiceChip(
                    label: Text(room),
                    selected: _room.text == room,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _room.text = room),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Device icon', style: text.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in deviceIconPresets.entries)
                  _ArtworkOption(
                    preset: entry.key,
                    label: entry.value,
                    selected: _preset == entry.key,
                    onTap: () => setState(() => _preset = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'Your four relays',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < _relays.length; index++) ...[
              Material(
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  leading: ApplianceArt(
                    preset: _relays[index].preset,
                    customImagePath: _relays[index].customImagePath,
                    on: _relays[index].lastState == true,
                    size: 45,
                  ),
                  title: Text(
                    _relays[index].name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Relay ${_relays[index].channel}'),
                  trailing: const Icon(Icons.edit_outlined, size: 21),
                  onTap: _saving ? null : () => _editRelay(index),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 5),
            Text(
              'Names and artwork can be changed anytime.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(_saving ? 'Saving…' : 'Save device'),
          ),
        ),
      ),
    );
  }
}

Future<RelayChannel?> showRelayEditor(
  BuildContext context, {
  required AppController controller,
  required RelayChannel relay,
}) => showModalBottomSheet<RelayChannel>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _RelayEditor(controller: controller, relay: relay),
);

class _RelayEditor extends StatefulWidget {
  const _RelayEditor({required this.controller, required this.relay});
  final AppController controller;
  final RelayChannel relay;

  @override
  State<_RelayEditor> createState() => _RelayEditorState();
}

class _RelayEditorState extends State<_RelayEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _preset;
  String? _customImage;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.relay.name);
    _preset = widget.relay.preset;
    _customImage = widget.relay.customImagePath;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _picking = true);
    try {
      final path = await widget.controller.importRelayImage();
      if (path != null && mounted) setState(() => _customImage = path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not import that image. Try another.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      widget.relay.copyWith(
        name: _name.text.trim(),
        preset: _preset,
        customImagePath: _customImage,
        clearCustomImage: _customImage == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    Text(
                      'Make relay ${widget.relay.channel} yours',
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _preview('Off', false, colors),
                        const SizedBox(width: 24),
                        _preview('On', true, colors),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Relay name',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Give this relay a name.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Text('Choose an appliance', style: text.titleMedium),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in appliancePresets.entries)
                            _ArtworkOption(
                              preset: entry.key,
                              label: entry.value,
                              width: (constraints.maxWidth - 16) / 3,
                              selected:
                                  _preset == entry.key && _customImage == null,
                              onTap: () => setState(() {
                                _preset = entry.key;
                                _customImage = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _picking ? null : _pickImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _picking ? 'Opening photos…' : 'Use your own image',
                      ),
                    ),
                    if (_customImage != null)
                      TextButton(
                        onPressed: () => setState(() => _customImage = null),
                        child: const Text('Remove custom image'),
                      ),
                    Text(
                      'Artwork is saved on this phone. Your own image is used for both states.',
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _picking ? null : _save,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Save relay'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(String label, bool on, ColorScheme colors) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on
              ? colors.primaryContainer.withValues(alpha: .5)
              : colors.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: ApplianceArt(
          preset: _preset,
          customImagePath: _customImage,
          on: on,
          size: 72,
        ),
      ),
      const SizedBox(height: 6),
      Text(label),
    ],
  );
}

class _ArtworkOption extends StatelessWidget {
  const _ArtworkOption({
    required this.preset,
    required this.label,
    required this.selected,
    required this.onTap,
    this.width = 96,
  });
  final String preset;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: SizedBox(
        width: width,
        child: Material(
          color: selected
              ? colors.primaryContainer.withValues(alpha: .55)
              : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Column(
                children: [
                  ExcludeSemantics(
                    child: ApplianceArt(preset: preset, on: true, size: 48),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
