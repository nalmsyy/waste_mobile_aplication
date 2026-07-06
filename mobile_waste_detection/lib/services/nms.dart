import 'dart:math' as math;
import 'package:collection/collection.dart';
import '../models/detection.dart';

/// Non-Maximum Suppression (greedy, class-agnostic).
/// [dets] must already be filtered by confidence threshold.
/// Returns a deduplicated list.
List<Detection> nms(List<Detection> dets, double iouThreshold) {
  if (dets.isEmpty) return [];

  // Sort by confidence descending
  final sorted = dets.sorted((a, b) => b.confidence.compareTo(a.confidence));
  final List<bool> keep = List.filled(sorted.length, true);

  for (int i = 0; i < sorted.length; i++) {
    if (!keep[i]) continue;
    for (int j = i + 1; j < sorted.length; j++) {
      if (!keep[j]) continue;
      if (sorted[i].classId != sorted[j].classId) continue;
      if (_iou(sorted[i], sorted[j]) > iouThreshold) {
        keep[j] = false;
      }
    }
  }

  return [for (int i = 0; i < sorted.length; i++) if (keep[i]) sorted[i]];
}

double _iou(Detection a, Detection b) {
  final double interX1 = math.max(a.x1, b.x1);
  final double interY1 = math.max(a.y1, b.y1);
  final double interX2 = math.min(a.x2, b.x2);
  final double interY2 = math.min(a.y2, b.y2);

  final double interW = (interX2 - interX1).clamp(0.0, double.infinity);
  final double interH = (interY2 - interY1).clamp(0.0, double.infinity);
  final double interArea = interW * interH;

  if (interArea == 0) return 0.0;

  final double areaA = a.width * a.height;
  final double areaB = b.width * b.height;
  return interArea / (areaA + areaB - interArea);
}
