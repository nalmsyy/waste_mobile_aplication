import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import '../models/detection.dart';
import 'image_utils.dart';
import 'nms.dart';

/// DetectorService using TFLite (LiteRT).
class DetectorService {
  static const String _modelAsset  = 'assets/models/yolo26m_waste.tflite';
  static const String _labelsAsset = 'assets/labels/labels.txt';
  static const int    _imgSize     = 640;
  static const double _nmsIou      = 0.45;

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<void> initialize() async {
    await _loadLabels();
    await _loadModel();
    _isLoaded = true;
  }

  Future<void> _loadLabels() async {
    final raw = await rootBundle.loadString(_labelsAsset);
    _labels = raw.trim().split('\n').map((l) => l.trim()).toList();
  }

  Future<void> _loadModel() async {
    final options = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
    _interpreter!.allocateTensors();
    debugPrint('[Detector TFLite] Model loaded.');
  }

  Future<List<Detection>> detect(
    CameraImage cameraImage, {
    required double confidenceThreshold,
    required int previewWidth,
    required int previewHeight,
    required int sensorOrientation,
    bool isFrontCamera = false,
  }) async {
    if (!_isLoaded || _interpreter == null) return [];

    img.Image? rawImage = cameraImageToImage(cameraImage);
    if (rawImage == null) return [];

    rawImage = _rotateImage(rawImage, sensorOrientation, isFrontCamera);
    final lb = letterbox(rawImage, _imgSize);
    final input = imageToFloat32(lb.image);

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final outputSize  = outputShape.reduce((a, b) => a * b);
    final outputBuffer = Float32List(outputSize);

    _interpreter!.run(
      input.reshape([1, _imgSize, _imgSize, 3]),
      outputBuffer.reshape(outputShape),
    );

    final rawDets = _parseOutput(outputBuffer, outputShape, confidenceThreshold);
    final mappedDets = rawDets
        .map((d) => _mapCoords(d, lb, rawImage!.width, rawImage.height))
        .toList();

    return nms(mappedDets, _nmsIou);
  }

  List<Detection> _parseOutput(Float32List data, List<int> shape, double threshold) {
    if (shape.length == 3) {
      final int dim1 = shape[1];
      final int dim2 = shape[2];
      final int numClasses = _labels.length;

      if (dim2 == 6) return _parseLayoutA(data, dim1, threshold);
      if (dim2 == 5 + numClasses) return _parseLayoutB(data, dim1, numClasses, threshold);
      if (dim1 == 5 + numClasses) return _parseLayoutC(data, dim1, dim2, numClasses, threshold);
      if (dim1 == 4 + numClasses) return _parseLayoutD(data, dim1, dim2, numClasses, threshold);
    }
    if (shape.length == 3 && shape[1] == 6) {
      return _parseLayoutE(data, shape[2], threshold);
    }
    return [];
  }

  List<Detection> _parseLayoutA(Float32List data, int m, double threshold) {
    final List<Detection> dets = [];
    for (int i = 0; i < m; i++) {
      final off = i * 6;
      final conf = data[off + 4];
      if (conf < threshold) continue;
      final classId = data[off + 5].round().clamp(0, _labels.length - 1);
      dets.add(Detection(
        x1: data[off],     y1: data[off + 1],
        x2: data[off + 2], y2: data[off + 3],
        confidence: conf, classId: classId, label: _labels[classId],
      ));
    }
    return dets;
  }

  List<Detection> _parseLayoutB(Float32List data, int n, int numClasses, double threshold) {
    final List<Detection> dets = [];
    final stride = 5 + numClasses;
    for (int i = 0; i < n; i++) {
      final off  = i * stride;
      final obj  = data[off + 4];
      if (obj < threshold) continue;
      int bestCls = 0; double bestScore = 0;
      for (int c = 0; c < numClasses; c++) {
        final s = obj * data[off + 5 + c];
        if (s > bestScore) { bestScore = s; bestCls = c; }
      }
      if (bestScore < threshold) continue;
      final cx = data[off]; final cy = data[off + 1];
      final w  = data[off + 2]; final h = data[off + 3];
      dets.add(Detection(
        x1: (cx - w / 2) / _imgSize, y1: (cy - h / 2) / _imgSize,
        x2: (cx + w / 2) / _imgSize, y2: (cy + h / 2) / _imgSize,
        confidence: bestScore, classId: bestCls, label: _labels[bestCls],
      ));
    }
    return dets;
  }

  List<Detection> _parseLayoutC(Float32List data, int rows, int n, int numClasses, double threshold) {
    final List<Detection> dets = [];
    for (int i = 0; i < n; i++) {
      final obj = data[4 * n + i];
      if (obj < threshold) continue;
      int bestCls = 0; double bestScore = 0;
      for (int c = 0; c < numClasses; c++) {
        final s = obj * data[(5 + c) * n + i];
        if (s > bestScore) { bestScore = s; bestCls = c; }
      }
      if (bestScore < threshold) continue;
      final cx = data[i]; final cy = data[n + i];
      final w  = data[2 * n + i]; final h = data[3 * n + i];
      dets.add(Detection(
        x1: (cx - w / 2) / _imgSize, y1: (cy - h / 2) / _imgSize,
        x2: (cx + w / 2) / _imgSize, y2: (cy + h / 2) / _imgSize,
        confidence: bestScore, classId: bestCls, label: _labels[bestCls],
      ));
    }
    return dets;
  }

  List<Detection> _parseLayoutD(Float32List data, int rows, int n, int numClasses, double threshold) {
    final List<Detection> dets = [];
    for (int i = 0; i < n; i++) {
      int bestCls = 0; double bestScore = 0;
      for (int c = 0; c < numClasses; c++) {
        final s = data[(4 + c) * n + i];
        if (s > bestScore) { bestScore = s; bestCls = c; }
      }
      if (bestScore < threshold) continue;
      dets.add(Detection(
        x1: data[i]           / _imgSize,
        y1: data[n + i]       / _imgSize,
        x2: data[2 * n + i]   / _imgSize,
        y2: data[3 * n + i]   / _imgSize,
        confidence: bestScore, classId: bestCls, label: _labels[bestCls],
      ));
    }
    return dets;
  }

  List<Detection> _parseLayoutE(Float32List data, int m, double threshold) {
    final List<Detection> dets = [];
    for (int i = 0; i < m; i++) {
      final conf = data[4 * m + i];
      if (conf < threshold) continue;
      final classId = data[5 * m + i].round().clamp(0, _labels.length - 1);
      dets.add(Detection(
        x1: data[i]         / _imgSize,
        y1: data[m + i]     / _imgSize,
        x2: data[2 * m + i] / _imgSize,
        y2: data[3 * m + i] / _imgSize,
        confidence: conf, classId: classId, label: _labels[classId],
      ));
    }
    return dets;
  }

  Detection _mapCoords(
    Detection d,
    ({img.Image image, double scaleX, double scaleY, int padLeft, int padTop}) lb,
    int origW,
    int origH,
  ) {
    double x1 = (d.x1 * _imgSize - lb.padLeft) / lb.scaleX / origW;
    double y1 = (d.y1 * _imgSize - lb.padTop)  / lb.scaleY / origH;
    double x2 = (d.x2 * _imgSize - lb.padLeft) / lb.scaleX / origW;
    double y2 = (d.y2 * _imgSize - lb.padTop)  / lb.scaleY / origH;
    return Detection(
      x1: x1.clamp(0, 1), y1: y1.clamp(0, 1),
      x2: x2.clamp(0, 1), y2: y2.clamp(0, 1),
      confidence: d.confidence, classId: d.classId, label: d.label,
    );
  }

  img.Image _rotateImage(img.Image src, int sensorOrientation, bool isFront) {
    switch (sensorOrientation) {
      case 90:  return img.copyRotate(src, angle: isFront ? -90 : 90);
      case 180: return img.copyRotate(src, angle: 180);
      case 270: return img.copyRotate(src, angle: isFront ? 90 : -90);
      default:  return src;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}
