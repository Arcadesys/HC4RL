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

/// Find: fewer lines, thicker, higher confidence (object boundaries).
/// Inspect: more lines, finer detail (connector/label shape).
enum EdgeMode {
  find,
  inspect,
}

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
    this.minContourArea = 0,
    this.downscaleFactor = 1.0,
    this.primaryEdgesOnly = false,
    this.primaryEdgesPercentile = 0.9,
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

  /// Minimum contour area in pixels²; contours below this are dropped. 0 = show all.
  final int minContourArea;

  /// Scale factor for optional downscale before processing (e.g. 0.5 = half size). 1.0 = no downscale.
  final double downscaleFactor;

  /// When true, keep only edge pixels with gradient magnitude in the top (primaryEdgesPercentile*100)%.
  final bool primaryEdgesOnly;

  /// Percentile for primary edges (e.g. 0.9 = top 10%). Used when primaryEdgesOnly is true.
  final double primaryEdgesPercentile;
}

/// Output: list of (x, y) edge pixel coordinates in image space.
/// [contours] is the list of contours (each a list of points) that passed minArea, for tap-to-focus.
/// [strengths] optional per-point gradient magnitude (same length as points) for confidence styling.
class EdgeDetectorOutput {
  const EdgeDetectorOutput({
    required this.points,
    this.contours,
    this.strengths,
  });
  final List<cv.Point> points;
  final List<List<cv.Point>>? contours;
  final List<double>? strengths;
}

/// Runs in isolate: grayscale → [optional CLAHE] → [optional downscale] → blur → Canny →
/// morphological close → findContours → filter by minContourArea → list of points.
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

  final double scaleFactor = input.downscaleFactor.clamp(0.25, 1.0);
  final bool downscale = scaleFactor < 1.0;
  cv.Mat work = src;
  int workWidth = width;
  int workHeight = height;
  if (downscale) {
    workWidth = (width * scaleFactor).round().clamp(1, width);
    workHeight = (height * scaleFactor).round().clamp(1, height);
    final cv.Mat resized = cv.resize(src, (workWidth, workHeight));
    src.dispose();
    src = resized;
    work = resized;
  }

  final int k = input.blurKernelSize;
  final double sigma = input.blurSigma;
  final cv.Mat blurred = cv.gaussianBlur(work, (k, k), sigma);
  if (downscale) work.dispose();
  work = blurred;
  if (blurred.isEmpty) {
    src.dispose();
    return const EdgeDetectorOutput(points: []);
  }

  final int aperture = kSobelApertureSizes.contains(input.sobelApertureSize)
      ? input.sobelApertureSize
      : 3;
  cv.Mat? magMat;
  if (input.primaryEdgesOnly) {
    final cv.Mat gradX = cv.sobel(
      work,
      cv.MatType.CV_32F,
      1,
      0,
      ksize: aperture,
    );
    final cv.Mat gradY = cv.sobel(
      work,
      cv.MatType.CV_32F,
      0,
      1,
      ksize: aperture,
    );
    magMat = cv.magnitude(gradX, gradY);
    gradX.dispose();
    gradY.dispose();
  }
  final cv.Mat edges = cv.canny(
    work,
    input.cannyLow,
    input.cannyHigh,
    apertureSize: aperture,
  );
  work.dispose();
  if (edges.isEmpty) {
    magMat?.dispose();
    src.dispose();
    return const EdgeDetectorOutput(points: []);
  }

  final cv.Mat kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
  final cv.Mat closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);
  kernel.dispose();
  edges.dispose();

  final (cv.Contours contours, cv.VecVec4i hierarchy) = cv.findContours(
    closed,
    cv.RETR_EXTERNAL,
    cv.CHAIN_APPROX_SIMPLE,
  );
  closed.dispose();

  final double scaleBack = downscale ? (1.0 / scaleFactor) : 1.0;
  final int minArea = input.minContourArea;
  final List<cv.Point> rawPoints = [];
  final List<double> magnitudes = [];
  final List<List<cv.Point>> contourList = [];

  try {
    for (int i = 0; i < contours.length; i++) {
      final cv.VecPoint contour = contours[i];
      final double area = cv.contourArea(contour);
      if (minArea > 0 && area < minArea) continue;
      final List<cv.Point> contourPoints = [];
      for (int j = 0; j < contour.length; j++) {
        final p = contour[j];
        rawPoints.add(cv.Point(p.x, p.y));
        contourPoints.add(
          downscale
              ? cv.Point((p.x * scaleBack).round(), (p.y * scaleBack).round())
              : cv.Point(p.x, p.y),
        );
        if (magMat != null) {
          final int row = p.y.clamp(0, magMat.rows - 1);
          final int col = p.x.clamp(0, magMat.cols - 1);
          magnitudes.add(magMat.atF32(row, i1: col));
        }
      }
      contourList.add(contourPoints);
    }
  } finally {
    contours.dispose();
    hierarchy.dispose();
    magMat?.dispose();
  }

  List<cv.Point> points;
  List<double>? outStrengths;
  if (input.primaryEdgesOnly && magnitudes.length == rawPoints.length && magnitudes.isNotEmpty) {
    final double pct = input.primaryEdgesPercentile.clamp(0.0, 1.0);
    final List<double> sorted = List<double>.from(magnitudes)..sort();
    final int idx = ((sorted.length - 1) * pct).round().clamp(0, sorted.length - 1);
    final double threshold = sorted[idx];
    points = <cv.Point>[];
    final List<double> kept = <double>[];
    for (int i = 0; i < rawPoints.length; i++) {
      if (magnitudes[i] >= threshold) {
        final p = rawPoints[i];
        if (downscale) {
          points.add(cv.Point(
            (p.x * scaleBack).round(),
            (p.y * scaleBack).round(),
          ));
        } else {
          points.add(cv.Point(p.x, p.y));
        }
        kept.add(magnitudes[i]);
      }
    }
    outStrengths = kept;
  } else {
    points = downscale
        ? rawPoints
            .map((p) => cv.Point(
                  (p.x * scaleBack).round(),
                  (p.y * scaleBack).round(),
                ))
            .toList()
        : rawPoints;
  }

  src.dispose();

  return EdgeDetectorOutput(
    points: points,
    contours: contourList.isEmpty ? null : contourList,
    strengths: outStrengths,
  );
}
