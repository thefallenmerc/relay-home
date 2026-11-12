import 'dart:async';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models.dart';
import '../widgets/appliance_art.dart';
import '../widgets/common.dart';
import 'device_editor.dart';

enum _SetupPage { prepare, wifi, connecting, discovery, results }

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.controller,
    this.reconfigureDevice,
  });
  final AppController controller;
  final RelayDevice? reconfigureDevice;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _manualIp = TextEditingController();
  _SetupPage _page = _SetupPage.prepare;
  PairingStage _stage = PairingStage.sending;
  bool _showPassword = false,
      _openNetwork = false,
      _busy = false,
      _networkLoading = false;
  String? _error;
  List<DiscoveredDevice> _results = [];
  int _elapsed = 0, _checked = 0, _total = 0, _generation = 0;
  Timer? _timer;

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    if (_busy) {
      widget.controller.cancelDiscovery();
      unawaited(widget.controller.cancelProvisioning());
    }
    _ssid.dispose();
    _password.dispose();
    _manualIp.dispose();
    super.dispose();
  }

  Future<void> _loadNetwork() async {
    setState(() {
      _page = _SetupPage.wifi;
      _networkLoading = true;
      _error = null;
    });
    try {
      await widget.controller.refreshNetwork(requestPermission: true);
      if (!mounted) return;
      final detected = widget.controller.network?.ssid;
      if (detected != null && detected.isNotEmpty && _ssid.text.isEmpty) {
        _ssid.text = detected;
      }
    } finally {
      if (mounted) setState(() => _networkLoading = false);
    }
  }

  void _startClock() {
    _elapsed = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  Future<void> _connect() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    final ssid = _ssid.text.trim();
    final password = _openNetwork ? '' : _password.text;
    setState(() {
      _page = _SetupPage.connecting;
      _busy = true;
      _error = null;
      _stage = PairingStage.sending;
    });
    _startClock();
    try {
      final devices = await widget.controller.provision(
        ssid: ssid,
        password: password,
        onStage: (stage) {
          if (mounted && generation == _generation) {
            setState(() => _stage = stage);
          }
        },
      );
      if (!mounted || generation != _generation) return;
      _timer?.cancel();
      setState(() {
        _busy = false;
        _results = devices;
        _page = _SetupPage.results;
      });
      if (devices.isEmpty) {
        setState(
          () => _error =
              'No board responded. Check pairing mode and the Wi-Fi details, then try again.',
        );
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _timer?.cancel();
      setState(() {
        _busy = false;
        _error = _message(error);
      });
    } finally {
      if (mounted && generation == _generation) _password.clear();
    }
  }

  String _message(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|Bad state):\s*'),
    '',
  );

  Future<void> _scan() async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _page = _SetupPage.discovery;
      _busy = true;
      _error = null;
      _results = [];
      _checked = 0;
      _total = 0;
    });
    try {
      await widget.controller.refreshNetwork(requestPermission: true);
      if (!mounted || generation != _generation) return;
      final devices = await widget.controller.discover(
        onProgress: (checked, total) {
          if (mounted && generation == _generation) {
            setState(() {
              _checked = checked;
              _total = total;
            });
          }
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _results = devices;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _cancel() async {
    _generation++;
    _timer?.cancel();
    widget.controller.cancelDiscovery();
    await widget.controller.cancelProvisioning();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = null;
        _page = _SetupPage.prepare;
      });
    }
  }

  Future<void> _select(DiscoveredDevice found) async {
    final existingByMac = widget.controller.devices
        .where(
          (d) =>
              found.mac != null &&
              d.mac?.toLowerCase() == found.mac!.toLowerCase(),
        )
        .firstOrNull;
    var device = widget.reconfigureDevice ?? existingByMac;
    if (device == null &&
        widget.controller.devices.any((d) => d.ip == found.ip)) {
      final savedAtAddress = widget.controller.devices.firstWhere(
        (d) => d.ip == found.ip,
      );
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Address already saved'),
          content: const Text(
            'A saved board uses this IP address. If this is the same physical board, continue to review its saved details. If it is a different board, update the old record’s address first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Review saved board'),
            ),
          ],
        ),
      );
      if (shouldContinue != true || !mounted) return;
      device = savedAtAddress;
    }
    if (!mounted) return;
    final next =
        device?.copyWith(
          ip: found.ip,
          mac: found.mac ?? device.mac,
          reachability: found.reachable
              ? Reachability.online
              : Reachability.offline,
        ) ??
        RelayDevice(
          id: '${widget.controller.demoMode ? 'demo' : 'board'}-${DateTime.now().microsecondsSinceEpoch}',
          name: 'New board',
          room: 'Living room',
          ip: found.ip,
          mac: found.mac,
          reachability: found.reachable
              ? Reachability.online
              : Reachability.offline,
          demo: widget.controller.demoMode,
          relays: List.generate(
            4,
            (i) => RelayChannel(channel: i + 1, name: 'Relay ${i + 1}'),
          ),
        );
    final saved = await Navigator.of(context).push<RelayDevice>(
      MaterialPageRoute(
        builder: (_) => DeviceEditor(
          controller: widget.controller,
          device: next,
          isNew: device == null,
          updateConnection: true,
        ),
      ),
    );
    if (saved != null && mounted) Navigator.of(context).pop();
  }

  Future<void> _addManual() async {
    final key = GlobalKey<FormState>();
    final address = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add by IP address'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use the address shown in your router’s connected-device list. You can save it now and check the connection later.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _manualIp,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'IP address',
                  hintText: '192.168.1.10',
                ),
                validator: (value) {
                  final parts = (value ?? '').trim().split('.');
                  if (parts.length != 4 ||
                      parts.any(
                        (p) =>
                            int.tryParse(p) == null ||
                            int.parse(p) < 0 ||
                            int.parse(p) > 255,
                      )) {
                    return 'Enter a valid IPv4 address';
                  }
                  final first = int.parse(parts[0]),
                      second = int.parse(parts[1]);
                  if (!(first == 10 ||
                      first == 192 && second == 168 ||
                      first == 172 && second >= 16 && second <= 31)) {
                    return 'Use a local network address';
                  }
                  return null;
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
              if (key.currentState!.validate()) {
                Navigator.pop(context, _manualIp.text.trim());
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (address != null && mounted) {
      await _select(DiscoveredDevice(ip: address));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _busy) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (_busy) {
                _cancel();
              } else if (_page != _SetupPage.prepare) {
                setState(() {
                  _page = _SetupPage.prepare;
                  _error = null;
                });
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            if (widget.controller.demoMode)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Chip(
                  label: Text(
                    'DEMO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: c.onPrimaryContainer,
                    ),
                  ),
                  backgroundColor: c.primaryContainer,
                  side: BorderSide.none,
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            children: switch (_page) {
              _SetupPage.prepare => _prepare(context),
              _SetupPage.wifi => _wifi(context),
              _SetupPage.connecting => _connecting(context),
              _SetupPage.discovery => _discovery(context),
              _SetupPage.results => _resultsPage(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _heading(
    BuildContext context,
    String eyebrow,
    String title,
    String subtitle,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 10),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  List<Widget> _prepare(BuildContext context) => [
    _heading(
      context,
      'Set up device · 1 of 3',
      widget.reconfigureDevice == null
          ? 'Let’s get your\nboard ready'
          : 'Reconnect your board',
      'A few things before you connect.',
    ),
    const SizedBox(height: 26),
    Container(
      height: 182,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: const ApplianceArt(preset: 'board', on: true, size: 170),
    ),
    const SizedBox(height: 22),
    _preparationRow(
      context,
      Icons.power_settings_new_rounded,
      'Power on your board',
    ),
    const SizedBox(height: 10),
    _preparationRow(context, Icons.wifi_rounded, 'Use a 2.4 GHz Wi-Fi network'),
    const SizedBox(height: 10),
    _preparationRow(
      context,
      Icons.smartphone_rounded,
      'Keep your phone nearby',
    ),
    const SizedBox(height: 22),
    Text(
      'Put the board in its pairing mode using its own instructions. Configure one board at a time.',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    ),
    if (widget.controller.demoMode) ...[
      const SizedBox(height: 16),
      const InfoPanel(
        text: 'Demo setup is simulated. No Wi-Fi credentials are transmitted.',
      ),
    ],
    const SizedBox(height: 26),
    FilledButton(onPressed: _loadNetwork, child: const Text('Board is ready')),
    const SizedBox(height: 8),
    TextButton(onPressed: _scan, child: const Text('Find an existing device')),
  ];

  Widget _preparationRow(BuildContext context, IconData icon, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, size: 25),
            const SizedBox(width: 17),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      );

  List<Widget> _wifi(BuildContext context) {
    final network = widget.controller.network;
    final wrongBand =
        network?.frequencyMhz != null && network!.frequencyMhz! >= 4900;
    return [
      _heading(
        context,
        'Set up device · 2 of 3',
        'Connect to Wi-Fi',
        'Choose the 2.4 GHz network your board will use.',
      ),
      const SizedBox(height: 16),
      const Center(child: ApplianceArt(preset: 'router', on: true, size: 156)),
      const SizedBox(height: 16),
      if (_networkLoading) ...[
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 16),
      ],
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _ssid,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Wi-Fi network',
                prefixIcon: Icon(Icons.wifi_rounded),
                hintText: 'Your network name',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter the current Wi-Fi name'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_openNetwork,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) => !_openNetwork && (v == null || v.isEmpty)
                  ? 'Enter the Wi-Fi password'
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'This network has no password',
                style: TextStyle(fontSize: 14),
              ),
              value: _openNetwork,
              onChanged: (v) => setState(() => _openNetwork = v ?? false),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      InfoPanel(
        text: wrongBand
            ? 'Your phone is using 5 GHz. Join the 2.4 GHz Wi-Fi network before continuing.'
            : 'Connect this phone to the same 2.4 GHz Wi-Fi network. A shared network name is okay when 2.4 GHz is available.',
        warning: wrongBand,
      ),
      if (!_networkLoading &&
          network?.ssid == null &&
          !widget.controller.demoMode) ...[
        const SizedBox(height: 12),
        const Text(
          'Network name unavailable. Enter it manually, or allow Wi-Fi access and try detecting it again.',
        ),
        TextButton.icon(
          onPressed: _loadNetwork,
          icon: const Icon(Icons.wifi_find_rounded),
          label: const Text('Detect current network'),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _networkLoading ? null : _connect,
        child: const Text('Connect device'),
      ),
      const SizedBox(height: 18),
      const Text(
        'Your Wi-Fi password is used for setup and is not saved.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13),
      ),
    ];
  }

  List<Widget> _connecting(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final minutes = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsed % 60).toString().padLeft(2, '0');
    return [
      _heading(
        context,
        'Set up device · 3 of 3',
        _error == null ? 'Connecting your board' : 'Let’s try that again',
        _error == null
            ? 'Keep this screen open for a moment.'
            : 'Your board has not been added yet.',
      ),
      const SizedBox(height: 34),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 136,
            decoration: BoxDecoration(
              border: Border.all(color: c.onSurfaceVariant, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: RelayMark(size: 40)),
          ),
          const SizedBox(width: 14),
          Text(
            '•••',
            style: TextStyle(color: c.primary, fontSize: 26, letterSpacing: 4),
          ),
          const SizedBox(width: 6),
          const Flexible(
            child: ApplianceArt(preset: 'board', on: true, size: 142),
          ),
        ],
      ),
      const SizedBox(height: 34),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          border: Border.all(color: c.outlineVariant),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            _progressRow(
              context,
              'Sending network details',
              _stage.index > 0,
              _stage == PairingStage.sending,
            ),
            const SizedBox(height: 25),
            _progressRow(
              context,
              'Waiting for your board',
              _stage.index > 1,
              _stage == PairingStage.waiting,
            ),
            const SizedBox(height: 25),
            _progressRow(
              context,
              'Checking connection',
              _stage == PairingStage.complete,
              _stage == PairingStage.checking,
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      Text(
        '$minutes:$seconds elapsed',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Setup can take up to 90 seconds.',
        textAlign: TextAlign.center,
      ),
      if (_error != null) ...[
        const SizedBox(height: 20),
        InfoPanel(text: _error!, warning: true),
      ],
      const SizedBox(height: 30),
      if (_busy)
        OutlinedButton(onPressed: _cancel, child: const Text('Cancel setup'))
      else
        FilledButton(
          onPressed: () => setState(() {
            _page = _SetupPage.wifi;
            _error = null;
          }),
          child: const Text('Check details and retry'),
        ),
      const SizedBox(height: 16),
      const Text(
        'Wi-Fi password is not saved.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13),
      ),
    ];
  }

  Widget _progressRow(
    BuildContext context,
    String label,
    bool done,
    bool active,
  ) => Row(
    children: [
      SizedBox(
        width: 28,
        height: 28,
        child: done
            ? Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              )
            : active && _busy
            ? const CircularProgressIndicator(strokeWidth: 3)
            : Icon(
                _error != null && active
                    ? Icons.error_outline_rounded
                    : Icons.circle,
                size: active ? 26 : 17,
                color: Theme.of(context).colorScheme.outline,
              ),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: active || done
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  List<Widget> _discovery(BuildContext context) => [
    _heading(
      context,
      'Find existing device',
      'Already on your Wi-Fi?',
      'Look for boards connected to this phone’s current network.',
    ),
    const SizedBox(height: 24),
    if (_busy) ...[
      const Center(child: ApplianceArt(preset: 'router', on: true, size: 150)),
      const SizedBox(height: 20),
      LinearProgressIndicator(
        value: _total > 0 ? _checked / _total : null,
        minHeight: 4,
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 12),
      Text(
        _total == 0
            ? 'Preparing the local network scan…'
            : 'Checked $_checked of $_total addresses',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      OutlinedButton(onPressed: _cancel, child: const Text('Cancel search')),
    ] else ...[
      if (_error != null)
        InfoPanel(text: _error!, warning: true)
      else if (_results.isEmpty)
        const InfoPanel(
          text:
              'No board responded. Make sure it has joined this Wi-Fi network and is powered on.',
          icon: Icons.wifi_find_rounded,
        ),
      ..._results.map((d) => _resultTile(context, d)),
      const SizedBox(height: 20),
      const InfoPanel(
        text:
            'Results are possible matches on the relay control port. Check the address against your board or router before adding one.',
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _scan,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Search again'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _addManual,
        child: const Text('Enter IP address manually'),
      ),
    ],
  ];

  List<Widget> _resultsPage(BuildContext context) => [
    _heading(
      context,
      _results.isEmpty ? 'No response' : 'Board found',
      _results.isEmpty ? 'No board found yet' : 'Your board is on Wi-Fi',
      _results.isEmpty
          ? 'Check your network details and pairing mode.'
          : 'Choose your board and make it yours.',
    ),
    const SizedBox(height: 22),
    const Center(child: ApplianceArt(preset: 'board', on: true, size: 180)),
    const SizedBox(height: 20),
    if (_error != null) ...[
      InfoPanel(text: _error!, warning: true),
      const SizedBox(height: 16),
    ],
    ..._results.map((d) => _resultTile(context, d)),
    if (_results.any((d) => !d.reachable)) ...[
      const SizedBox(height: 18),
      const InfoPanel(
        text:
            'Wi-Fi setup responded, but the control port is not reachable yet. You can save the board and check again after it finishes starting.',
        warning: true,
      ),
    ],
    const SizedBox(height: 20),
    TextButton(
      onPressed: () => setState(() {
        _page = _SetupPage.wifi;
        _error = null;
      }),
      child: const Text('Try setup again'),
    ),
  ];

  Widget _resultTile(BuildContext context, DiscoveredDevice result) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _select(result),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const ApplianceArt(preset: 'board', on: true, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.verified
                          ? 'ESP relay board'
                          : 'Possible relay board',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(result.ip),
                    if (result.mac != null)
                      Text(
                        result.mac!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 5),
                    Text(
                      result.reachable
                          ? 'Control port reachable'
                          : 'Connection not confirmed',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    ),
  );
}
