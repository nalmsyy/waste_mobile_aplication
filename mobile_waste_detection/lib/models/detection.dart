/// Detection represents a single bounding-box result from the model.
class Detection {
  /// Bounding box in normalised coordinates [0..1]  (x1, y1, x2, y2)
  final double x1, y1, x2, y2;
  final double confidence;
  final int classId;
  final String label;

  const Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
    required this.label,
  });

  /// Width in normalised units
  double get width  => x2 - x1;

  /// Height in normalised units
  double get height => y2 - y1;

  /// Center x/y in normalised units
  double get cx => (x1 + x2) / 2;
  double get cy => (y1 + y2) / 2;

  @override
  String toString() =>
      'Detection(label=$label, conf=${confidence.toStringAsFixed(2)}, '
      'box=[${x1.toStringAsFixed(3)},${y1.toStringAsFixed(3)},'
      '${x2.toStringAsFixed(3)},${y2.toStringAsFixed(3)}])';
}
