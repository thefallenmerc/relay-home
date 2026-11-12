import 'package:flutter/material.dart';

class RelayMark extends StatelessWidget {
  const RelayMark({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Relay Home',
    image: true,
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .18),
      decoration: BoxDecoration(
        color: const Color(0xFF00634E),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: CustomPaint(painter: _MarkPainter()),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFF3F6E8)
      ..strokeWidth = size.width * .085
      ..strokeCap = StrokeCap.round;
    final points = [
      Offset(size.width * .18, size.height * .18),
      Offset(size.width * .82, size.height * .18),
      Offset(size.width * .18, size.height * .82),
      Offset(size.width * .82, size.height * .82),
    ];
    canvas.drawLine(points[0], points[3], p);
    canvas.drawLine(points[1], points[2], p);
    for (final point in points) {
      canvas.drawCircle(point, size.width * .17, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class InfoPanel extends StatelessWidget {
  const InfoPanel({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.warning = false,
  });
  final String text;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warning
            ? c.errorContainer.withValues(alpha: .45)
            : c.primaryContainer.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 23,
            color: warning ? c.onErrorContainer : c.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: warning ? c.onErrorContainer : c.onPrimaryContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
