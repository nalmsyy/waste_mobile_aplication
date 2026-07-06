import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;

import '../models/detection.dart';
import 'image_utils.dart';
import 'nms.dart';

/// DetectorService using ONNX Runtime.
/// Loads the exported yolo26m_waste.onnx model and runs inference.
class DetectorService {
  static const String _modelAsset  = 'assets/models/yolo26m_waste.onnx';
  static const String _labelsAsset = 'assets/labels/labels.txt';
  static const int    _imgSize     = 640;
  static const double _nmsIou      = 0.45;

  OrtSession? _session;
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
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    final rawModel = await rootBundle.load(_modelAsset);
    _session = OrtSession.fromBuffer(rawModel.buffer.asUint8List(), sessionOptions);
    debugPrint('[Detector ONNX] Model loaded. '
        'Input names: ${_session!.inputNames}, '
        'Output names: ${_session!.outputNames}');
  }

  Future<List<Detection>> detect(
    CameraImage cameraImage, {
    required double confidenceThreshold,
    required int previewWidth,
    required int previewHeight,
    required int sensorOrientation,
    bool isFrontCamera = false,
  }) async {
    if (!_isLoaded || _session == null) return [];

    // 1. Convert camera frame to RGB
    img.Image? rawImage = cameraImageToImage(cameraImage);
    if (rawImage == null) return [];

    // 2. Rotate image
    rawImage = _rotateImage(rawImage, sensorOrientation, isFrontCamera);

    // 3. Letterbox to 640x640
    final lb = letterbox(rawImage, _imgSize);

    // 4. Convert to NCHW flat float32 list
    final inputData = imageToFloat32NCHW(lb.image);

    // 5. Create input tensor
    final shape = [1, 3, _imgSize, _imgSize];
    final inputOrt = OrtValueTensor.createTensorWithDataList(inputData, shape);
    final inputs = {_session!.inputNames.first: inputOrt};
    final runOptions = OrtRunOptions();

    // 6. Run ONNX session
    List<OrtValue?>? outputs;
    try {
      outputs = await _session!.runAsync(runOptions, inputs);
    } catch (e) {
      debugPrint('[Detector ONNX] Run error: $e');
      inputOrt.release();
      runOptions.release();
      return [];
    }

    if (outputs == null || outputs.isEmpty || outputs.first == null) {
      inputOrt.release();
      runOptions.release();
      return [];
    }

    // 7. Parse outputs [1, 300, 6] or [1, 5+C, 8400]
    final outputTensor = outputs.first as OrtValueTensor;
    final outputData = outputTensor.value as List;

    final List<Detection> rawDets = [];

    if (outputData.isNotEmpty) {
      final batch = outputData[0] as List;

      // Handle raw output [1, 5+C, 8400] or transposed [1, 8400, 5+C] if not end-to-end
      // Usually end-to-end YOLOv8/9/10/11 export with NMS has shape [1, 300, 6]
      // Let's check layout type:
      final sample = batch.first;
      if (sample is List) {
        // Layout A: list of rows (e.g. 300 rows, each row has length 6: [x1, y1, x2, y2, conf, class_id])
        if (sample.length == 6) {
          for (final item in batch) {
            final row = item as List;
            final double conf = (row[4] as num).toDouble();
            if (conf < confidenceThreshold) continue;

            final int classId = (row[5] as num).round().clamp(0, _labels.length - 1);
            
            // Convert to normalized coordinates [0..1]
            double x1 = (row[0] as num).toDouble();
            double y1 = (row[1] as num).toDouble();
            double x2 = (row[2] as num).toDouble();
            double y2 = (row[3] as num).toDouble();

            // If coordinates are in pixels (usually > 1.0), normalize them
            if (x1 > 1.01 || x2 > 1.01 || y1 > 1.01 || y2 > 1.01) {
              x1 /= _imgSize;
              y1 /= _imgSize;
              x2 /= _imgSize;
              y2 /= _imgSize;
            }

            rawDets.add(Detection(
              x1: x1, y1: y1, x2: x2, y2: y2,
              confidence: conf, classId: classId, label: _labels[classId],
            ));
          }
        } else {
          // Alternative layout: [1, 8400, 5+C]
          final numClasses = _labels.length;
          if (sample.length == 4 + numClasses || sample.length == 5 + numClasses) {
            final hasObjConf = sample.length == 5 + numClasses;
            for (final item in batch) {
              final row = item as List;
              double conf = 0.0;
              int bestCls = 0;
              double bestScore = 0.0;

              if (hasObjConf) {
                final objConf = (row[4] as num).toDouble();
                for (int c = 0; c < numClasses; c++) {
                  final score = (row[5] + c as num).toDouble() * objConf;
                  if (score > bestScore) {
                    bestScore = score;
                    bestCls = c;
                  }
                }
                conf = bestScore;
              } else {
                for (int c = 0; c < numClasses; c++) {
                  final score = (row[4 + c] as num).toDouble();
                  if (score > bestScore) {
                    bestScore = score;
                    bestCls = c;
                  }
                }
                conf = bestScore;
              }

              if (conf < confidenceThreshold) continue;

              final cx = (row[0] as num).toDouble() / _imgSize;
              final cy = (row[1] as num).toDouble() / _imgSize;
              final w  = (row[2] as num).toDouble() / _imgSize;
              final h  = (row[3] as num).toDouble() / _imgSize;

              rawDets.add(Detection(
                x1: cx - w / 2, y1: cy - h / 2,
                x2: cx + w / 2, y2: cy + h / 2,
                confidence: conf, classId: bestCls, label: _labels[bestCls],
              ));
            }
          }
        }
      } else {
        // Layout C: transposed [1, 5+C, 8400] where batch is a flat list or list of channels
        // In Dart ONNX output, if it's [1, 9, 8400], batch will have 9 channels, each channel is a List of 8400 elements.
        final numClasses = _labels.length;
        if (batch.length == 4 + numClasses || batch.length == 5 + numClasses) {
          final channels = batch;
          final int numAnchors = (channels[0] as List).length;
          final hasObjConf = channels.length == 5 + numClasses;

          for (int i = 0; i < numAnchors; i++) {
            double conf = 0.0;
            int bestCls = 0;
            double bestScore = 0.0;

            if (hasObjConf) {
              final objConf = (channels[4] as List)[i] as double;
              for (int c = 0; c < numClasses; c++) {
                final score = ((channels[5 + c] as List)[i] as double) * objConf;
                if (score > bestScore) {
                  bestScore = score;
                  bestCls = c;
                }
              }
              conf = bestScore;
            } else {
              for (int c = 0; c < numClasses; c++) {
                final score = (channels[4 + c] as List)[i] as double;
                if (score > bestScore) {
                  bestScore = score;
                  bestCls = c;
                }
              }
              conf = bestScore;
            }

            if (conf < confidenceThreshold) continue;

            final cx = ((channels[0] as List)[i] as double) / _imgSize;
            final cy = ((channels[1] as List)[i] as double) / _imgSize;
            final w  = ((channels[2] as List)[i] as double) / _imgSize;
            final h  = ((channels[3] as List)[i] as double) / _imgSize;

            rawDets.add(Detection(
              x1: cx - w / 2, y1: cy - h / 2,
              x2: cx + w / 2, y2: cy + h / 2,
              confidence: conf, classId: bestCls, label: _labels[bestCls],
            ));
          }
        }
      }
    }

    // 8. Cleanup
    inputOrt.release();
    runOptions.release();
    for (final element in outputs) {
      element?.release();
    }

    // 9. Coordinate mapping
    final mappedDets = rawDets
        .map((d) => _mapCoords(d, lb, rawImage!.width, rawImage.height))
        .toList();

    // 10. Non-Maximum Suppression
    return nms(mappedDets, _nmsIou);
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
      confidence: d.confidence,
      classId: d.classId,
      label: d.label,
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
    _session?.release();
    _session = null;
    OrtEnv.instance.release();
    _isLoaded = false;
  }
}
