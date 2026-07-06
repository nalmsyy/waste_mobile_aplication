import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';

/// Converts a [CameraImage] (YUV420 / NV21 / BGRA8888) to an [img.Image].
img.Image? cameraImageToImage(CameraImage cameraImage) {
  try {
    switch (cameraImage.format.group) {
      // ── YUV420 (Android) ────────────────────────────────────────────────
      case ImageFormatGroup.yuv420:
        return _convertYuv420ToImage(cameraImage);

      // ── BGRA8888 (iOS) ───────────────────────────────────────────────────
      case ImageFormatGroup.bgra8888:
        return _convertBgra8888ToImage(cameraImage);

      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

img.Image _convertYuv420ToImage(CameraImage image) {
  final int width  = image.width;
  final int height = image.height;

  final yPlane  = image.planes[0];
  final uPlane  = image.planes[1];
  final vPlane  = image.planes[2];

  final Uint8List yBytes  = yPlane.bytes;
  final Uint8List uBytes  = uPlane.bytes;
  final Uint8List vBytes  = vPlane.bytes;

  final int uvRowStride    = uPlane.bytesPerRow;
  final int uvPixelStride  = uPlane.bytesPerPixel ?? 1;

  final out = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int yIdx = y * yPlane.bytesPerRow + x;
      final int uvIdx = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;

      final int yVal = yBytes[yIdx];
      final int uVal = uBytes[uvIdx] - 128;
      final int vVal = vBytes[uvIdx] - 128;

      int r = (yVal + (1.402 * vVal)).round().clamp(0, 255);
      int g = (yVal - (0.344 * uVal) - (0.714 * vVal)).round().clamp(0, 255);
      int b = (yVal + (1.772 * uVal)).round().clamp(0, 255);

      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

img.Image _convertBgra8888ToImage(CameraImage image) {
  final bytes = image.planes[0].bytes;
  final width  = image.width;
  final height = image.height;
  final out = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int idx = (y * width + x) * 4;
      final int b = bytes[idx];
      final int g = bytes[idx + 1];
      final int r = bytes[idx + 2];
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

/// Letterbox-resize [src] to [targetSize]×[targetSize] with grey padding.
/// Returns (resizedImage, scaleX, scaleY, padLeft, padTop).
({img.Image image, double scaleX, double scaleY, int padLeft, int padTop})
    letterbox(img.Image src, int targetSize) {
  final double scaleX = targetSize / src.width;
  final double scaleY = targetSize / src.height;
  final double scale  = scaleX < scaleY ? scaleX : scaleY;

  final int newW = (src.width  * scale).round();
  final int newH = (src.height * scale).round();

  final resized = img.copyResize(src, width: newW, height: newH,
      interpolation: img.Interpolation.linear);

  final padded = img.Image(width: targetSize, height: targetSize);
  img.fill(padded, color: img.ColorRgb8(114, 114, 114)); // grey fill
  img.compositeImage(padded, resized,
      dstX: (targetSize - newW) ~/ 2,
      dstY: (targetSize - newH) ~/ 2);

  return (
    image  : padded,
    scaleX : scale,
    scaleY : scale,
    padLeft: (targetSize - newW) ~/ 2,
    padTop : (targetSize - newH) ~/ 2,
  );
}

/// Convert [img.Image] to a normalised Float32List [1, H, W, 3] for TFLite.
Float32List imageToFloat32(img.Image image) {
  final int h = image.height;
  final int w = image.width;
  final out = Float32List(1 * h * w * 3);
  int idx = 0;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final pixel = image.getPixel(x, y);
      out[idx++] = pixel.r / 255.0;
      out[idx++] = pixel.g / 255.0;
      out[idx++] = pixel.b / 255.0;
    }
  }
  return out;
}

/// Convert [img.Image] to a normalised Float32List [1, 3, H, W] for ONNX (BCHW).
Float32List imageToFloat32NCHW(img.Image image) {
  final int h = image.height;
  final int w = image.width;
  final out = Float32List(1 * 3 * h * w);
  final int channelSize = h * w;
  int rIdx = 0;
  int gIdx = channelSize;
  int bIdx = 2 * channelSize;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final pixel = image.getPixel(x, y);
      out[rIdx++] = pixel.r / 255.0;
      out[gIdx++] = pixel.g / 255.0;
      out[bIdx++] = pixel.b / 255.0;
    }
  }
  return out;
}
