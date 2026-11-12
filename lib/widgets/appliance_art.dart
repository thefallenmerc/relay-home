import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// User-facing names for the bundled appliance presets. The stored keys stay
/// stable so changing a name never invalidates a saved device configuration.
const appliancePresets = <String, String>{
  'switch': 'Switch',
  'pc': 'Computer',
  'laptop': 'Laptop',
  'tv': 'Television',
  'bulb': 'Light bulb',
  'table_lamp': 'Table lamp',
  'wall_light': 'Wall light',
  'ceiling_light': 'Ceiling light',
  'pendant_light': 'Pendant light',
  'ceiling_fan': 'Ceiling fan',
  'standing_fan': 'Standing fan',
  'ac': 'Air conditioner',
  'socket': 'Socket',
  'pump': 'Water pump',
};

/// Local, transparent illustrations. Each asset has two equal square frames:
/// ON at the left and OFF at the right. Cropping happens only during painting;
/// the generated artwork and its alpha channel remain intact on disk.
class ApplianceArt extends StatelessWidget {
  const ApplianceArt({
    super.key,
    required this.preset,
    this.on = false,
    this.customImagePath,
    this.size = 72,
  });

  final String preset;
  final bool on;
  final String? customImagePath;
  final double size;

  // The fixed 16-item library is bounded. The decoded sprites are shared by
  // every tile rather than decoded again when a relay changes state.
  static final Map<String, Future<ui.Image>> _images = {};

  /// Each widget test owns a different fake-async zone. Do not carry completed
  /// futures between those zones or dispose images still used by old painters.
  @visibleForTesting
  static void clearCacheForTesting() => _images.clear();

  static Future<ui.Image> _imageFor(String key) {
    final cached = _images[key];
    if (cached != null) return cached;
    late final Future<ui.Image> pending;
    pending = _decode(key).then(
      (image) => image,
      onError: (Object error, StackTrace stackTrace) {
        // A transient load failure should be retried on a later build. Do not
        // evict a newer load started after a test reset while this one waited.
        if (identical(_images[key], pending)) _images.remove(key);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _images[key] = pending;
    return pending;
  }

  String get _assetPreset => switch (preset) {
    'lighting_board' || 'appliance_board' => 'board',
    'board' || 'router' => preset,
    _ => appliancePresets.containsKey(preset) ? preset : 'switch',
  };

  static Future<ui.Image> _decode(String key) async {
    final bytes = await rootBundle.load('assets/art/$key.png');
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      targetWidth: 768,
      allowUpscaling: false,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Widget _fallback(BuildContext context) => Center(
    child: Icon(
      switch (_assetPreset) {
        'pc' => Icons.desktop_windows_rounded,
        'laptop' => Icons.laptop_mac_rounded,
        'tv' => Icons.tv_rounded,
        'bulb' || 'ceiling_light' || 'pendant_light' => Icons.lightbulb_outline,
        'table_lamp' || 'wall_light' => Icons.light_outlined,
        'ceiling_fan' || 'standing_fan' => Icons.air_rounded,
        'ac' => Icons.ac_unit_rounded,
        'socket' => Icons.power_rounded,
        'pump' => Icons.water_drop_outlined,
        'router' => Icons.router_rounded,
        'board' => Icons.developer_board_rounded,
        _ => Icons.power_settings_new_rounded,
      },
      size: size * 0.55,
      color: on
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _bundled(BuildContext context) => FutureBuilder<ui.Image>(
    future: _imageFor(_assetPreset),
    builder: (context, snapshot) {
      final image = snapshot.data;
      if (image == null) return _fallback(context);
      return AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        child: CustomPaint(
          key: ValueKey('$_assetPreset:$on'),
          size: Size.square(size),
          painter: _ApplianceSpritePainter(image: image, on: on),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final path = customImagePath;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: path == null || path.isEmpty
            ? _bundled(context)
            : ClipRRect(
                borderRadius: BorderRadius.circular(size * 0.14),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  width: size,
                  height: size,
                  cacheWidth: (size * 3).ceil(),
                  errorBuilder: (context, error, stackTrace) =>
                      _bundled(context),
                ),
              ),
      ),
    );
  }
}

class _ApplianceSpritePainter extends CustomPainter {
  const _ApplianceSpritePainter({required this.image, required this.on});

  final ui.Image image;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final halfWidth = image.width / 2;
    final source = Rect.fromLTWH(
      on ? 0 : halfWidth,
      0,
      halfWidth,
      image.height.toDouble(),
    );
    final sourceSize = Size(halfWidth, image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ApplianceSpritePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.on != on;
}
