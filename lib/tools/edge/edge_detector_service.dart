import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Edge detection preset: name and Canny/blur parameters.
enum EdgePreset {
  lowLight(50.0, 150.0, 5, 1.0),
  normal(50.0, 150.0, 5, 1.0),

  /// Crisp edges: higher Canny thresholds, lighter blur so edges pop.
  highContrast(80.0, 220.0, 5, 0.6);

  const EdgePreset(
      this.cannyLow, this.cannyHigh, this.blurKernelSize, this.blurSigma);
  final double cannyLow;
  final double cannyHigh;
  final int blurKernelSize;
  final double blurSigma;
}

/// Sobel aperture sizes supported by OpenCV Canny (gradient kernel). 3 = sharper, 7 = smoother.
const List<int> kSobelApertureSizes = [3, 5, 7];

/// Input for isolate: grayscale buffer dimensions, bytes, and optional params.
class EdgeDetectorInput {
  const EdgeDetectorInput({
    required this.width,
    required this.height,
    required this.bytes,
    this.cannyLow = 50.0,
    this.cannyHigh = 150.0,
    this.blurKernelSize = 5,
    this.blurSigma = 1.0,
    this.sobelApertureSize = 3,
    this.enhanceBeforeEdges = false,
  });

  final int width;
  final int height;
  final Uint8List bytes;
  final double cannyLow;
  final double cannyHigh;
  final int blurKernelSize;
  final double blurSigma;

  /// Sobel kernel size for Canny gradient (3, 5, or 7).
  final int sobelApertureSize;
  final bool enhanceBeforeEdges;
}

/// Output: list of (x, y) edge pixel coordinates in image space.
class EdgeDetectorOutput {
  const EdgeDetectorOutput({required this.points});
  final List<cv.Point> points;
}

/// Runs in isolate: grayscale → [optional CLAHE] → blur → Canny → findNonZero → list of points.
EdgeDetectorOutput runEdgeDetection(EdgeDetectorInput input) {
  final int width = input.width;
  final int height = input.height;
  final Uint8List bytes = input.bytes;

  cv.Mat src = cv.Mat.fromList(
    height,
    width,
    cv.MatType.CV_8UC1,
    bytes,
  );

  if (input.enhanceBeforeEdges) {
    final clahe = cv.CLAHE.create(2.0, (8, 8));
    try {
      final cv.Mat enhanced = clahe.apply(src);
      clahe.dispose();
      src.dispose();
      src = enhanced;
    } catch (_) {
      clahe.dispose();
      src.dispose();
      return const EdgeDetectorOutput(points: []);
    }
  }

  final int k = input.blurKernelSize;
  final double sigma = input.blurSigma;
  final cv.Mat blurred = cv.gaussianBlur(src, (k, k), sigma);
  src.dispose();
  if (blurred.isEmpty) return const EdgeDetectorOutput(points: []);

  final int aperture = kSobelApertureSizes.contains(input.sobelApertureSize)
      ? input.sobelApertureSize
      : 3;
  final cv.Mat edges = cv.canny(
    blurred,
    input.cannyLow,
    input.cannyHigh,
    apertureSize: aperture,
  );
  blurred.dispose();
  if (edges.isEmpty) return const EdgeDetectorOutput(points: []);

  final cv.Mat nonzero = cv.findNonZero(edges);
  edges.dispose();
  if (nonzero.isEmpty) return const EdgeDetectorOutput(points: []);

  // findNonZero returns Nx1 CV_32SC2 (row r = point x,y). Read from raw buffer to avoid
  // native cv_Mat_get_i32_3 crash on some devices (SIGSEGV in libdartcv.so).
  final List<cv.Point> points = [];
  final int rows = nonzero.rows;
  final int numInt32 = rows * 2; // x,y per row
  final int byteLen = numInt32 * 4;
  try {
    final Uint8List raw = nonzero.data;
    if (raw.lengthInBytes < byteLen) {
      nonzero.dispose();
      return EdgeDetectorOutput(points: points);
    }
    final Int32List list = Int32List.view(
      raw.buffer,
      raw.offsetInBytes,
      numInt32,
    );
    for (int r = 0; r < rows; r++) {
      points.add(cv.Point(list[2 * r], list[2 * r + 1]));
    }
  } catch (_) {
    // Fallback: avoid crash; return empty or skip this frame
  } finally {
    nonzero.dispose();
  }

  return EdgeDetectorOutput(points: points);
}
