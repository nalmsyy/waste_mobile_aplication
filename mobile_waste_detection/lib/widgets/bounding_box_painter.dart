import 'package:flutter/material.dart';
import '../models/detection.dart';

/// Class-specific colour palette
const _palette = [
  Color(0xFF4FC3F7), // kertas   – light blue
  Color(0xFFFFB74D), // logam    – amber
  Color(0xFFBA68C8), // pakaian  – purple
  Color(0xFF81C784), // plastik  – green
  Color(0xFFA5D6A7), // tumbuhan – light green
];

Color classColor(int classId) => _palette[classId % _palette.length];

/// Custom painter that draws bounding boxes and labels over the camera preview.
class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final Size previewSize;   // logical size of the preview widget
  final Size imageSize;     // size of the camera frame (after rotation)

  const BoundingBoxPainter({
    required this.detections,
    required this.previewSize,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    // Scale factors to map normalised [0..1] → widget pixel coords
    final double scaleX = size.width;
    final double scaleY = size.height;

    for (final d in detections) {
      final color = classColor(d.classId);
      final rect = Rect.fromLTRB(
        d.x1 * scaleX,
        d.y1 * scaleY,
        d.x2 * scaleX,
        d.y2 * scaleY,
      );

      // ── Box ──────────────────────────────────────────────────────────────
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withOpacity(0.20)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // ── Label ─────────────────────────────────────────────────────────────
      final label = '${d.label}  ${(d.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: ' $label ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            backgroundColor: color.withOpacity(0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelY = (rect.top - tp.height).clamp(0.0, size.height - tp.height);
      tp.paint(canvas, Offset(rect.left, labelY));
    }
  }

  @override
  bool shouldRepaint(BoundingBoxPainter old) =>
      old.detections != detections || old.previewSize != previewSize;
}
