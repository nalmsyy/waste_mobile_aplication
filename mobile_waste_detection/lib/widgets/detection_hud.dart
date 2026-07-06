import 'package:flutter/material.dart';
import '../models/detection.dart';
import 'bounding_box_painter.dart';

/// Overlay bar showing per-class detection counts.
class DetectionCountBar extends StatelessWidget {
  final List<Detection> detections;
  static const _labels = ['kertas', 'logam', 'pakaian', 'plastik', 'tumbuhan'];

  const DetectionCountBar({super.key, required this.detections});

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{};
    for (final d in detections) {
      counts[d.classId] = (counts[d.classId] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (int i = 0; i < _labels.length; i++)
            if ((counts[i] ?? 0) > 0)
              _Chip(label: _labels[i], count: counts[i]!, color: classColor(i)),
          if (counts.isEmpty)
            const Text('Tidak ada objek',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _Chip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.20),
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Compact FPS + total count indicator.
class StatsBar extends StatelessWidget {
  final double fps;
  final int totalCount;

  const StatsBar({super.key, required this.fps, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed, size: 14, color: Colors.greenAccent),
          const SizedBox(width: 4),
          Text(
            '${fps.toStringAsFixed(1)} FPS',
            style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.category, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            '$totalCount objek',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Confidence threshold slider widget.
class ConfidenceSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const ConfidenceSlider({
      super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Confidence threshold',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              Text(
                '${(value * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.cyanAccent,
              thumbColor: Colors.cyanAccent,
              inactiveTrackColor: Colors.white24,
              overlayColor: Colors.cyanAccent.withOpacity(0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: 0.05,
              max: 0.95,
              divisions: 18,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
