import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Converts [CameraImage] to grayscale buffer for OpenCV (1 channel, row-major).
/// Android: YUV420, planes[0] = Y. iOS: BGRA.
/// Respects bytesPerRow / strides so image is not skewed.
class CameraImageConverter {
  /// Returns grayscale [Uint8List] (width * height), or null if format unsupported.
  static Uint8List? toGrayscale(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final int width = image.width;
    final int height = image.height;

    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
        return _yuvToGrayscale(image, width, height);
      case ImageFormatGroup.bgra8888:
        return _bgraToGrayscale(image, width, height);
      default:
        return null;
    }
  }

  static Uint8List _yuvToGrayscale(CameraImage image, int width, int height) {
    final Plane yPlane = image.planes[0];
    final int bytesPerRow = yPlane.bytesPerRow;
    final Uint8List out = Uint8List(width * height);
    final ByteData yData = yPlane.bytes.buffer.asByteData();
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        out[y * width + x] = yData.getUint8(y * bytesPerRow + x);
      }
    }
    return out;
  }

  static Uint8List _bgraToGrayscale(CameraImage image, int width, int height) {
    final Plane plane = image.planes[0];
    final int bytesPerRow = plane.bytesPerRow;
    final ByteData data = plane.bytes.buffer.asByteData();
    final Uint8List out = Uint8List(width * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int idx = y * bytesPerRow + x * 4;
        final int b = data.getUint8(idx);
        final int g = data.getUint8(idx + 1);
        final int r = data.getUint8(idx + 2);
        out[y * width + x] = ((0.299 * r) + (0.587 * g) + (0.114 * b)).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// Returns RGB bytes (width * height * 3, row-major R,G,B) for saving as image.
  static Uint8List? toRgb(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final int width = image.width;
    final int height = image.height;

    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
        return _yuvToRgb(image, width, height);
      case ImageFormatGroup.bgra8888:
        return _bgraToRgb(image, width, height);
      default:
        return null;
    }
  }

  static Uint8List _yuvToRgb(CameraImage image, int width, int height) {
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes.length > 1 ? image.planes[1] : image.planes[0];
    final Plane vPlane = image.planes.length > 2 ? image.planes[2] : image.planes[0];
    final int yRow = yPlane.bytesPerRow;
    final int uvRow = uPlane.bytesPerRow;
    final Uint8List out = Uint8List(width * height * 3);
    final ByteData yData = yPlane.bytes.buffer.asByteData();
    final ByteData uData = uPlane.bytes.buffer.asByteData();
    final ByteData vData = vPlane.bytes.buffer.asByteData();
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yVal = yData.getUint8(y * yRow + x).toInt();
        final int uvX = x ~/ 2;
        final int uvY = y ~/ 2;
        final int uVal = uData.getUint8(uvY * uvRow + uvX).toInt() - 128;
        final int vVal = vData.getUint8(uvY * uvRow + uvX).toInt() - 128;
        final int r = (yVal + (1.402 * vVal)).round().clamp(0, 255);
        final int g = (yVal - (0.344 * uVal) - (0.714 * vVal)).round().clamp(0, 255);
        final int b = (yVal + (1.772 * uVal)).round().clamp(0, 255);
        final int i = (y * width + x) * 3;
        out[i] = r;
        out[i + 1] = g;
        out[i + 2] = b;
      }
    }
    return out;
  }

  static Uint8List _bgraToRgb(CameraImage image, int width, int height) {
    final Plane plane = image.planes[0];
    final int bytesPerRow = plane.bytesPerRow;
    final ByteData data = plane.bytes.buffer.asByteData();
    final Uint8List out = Uint8List(width * height * 3);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int idx = y * bytesPerRow + x * 4;
        final int i = (y * width + x) * 3;
        out[i] = data.getUint8(idx + 2);
        out[i + 1] = data.getUint8(idx + 1);
        out[i + 2] = data.getUint8(idx);
      }
    }
    return out;
  }
}
