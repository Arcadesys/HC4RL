import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Rotates edge points from camera image space to display space so the overlay
/// matches the rotated preview. [sensorOrientation] is the clockwise angle
/// (0, 90, 180, 270) the image must be rotated to be upright.
/// Returns (rotated points, display width, display height).
(List<cv.Point> points, int displayWidth, int displayHeight) rotateEdgePointsForDisplay(
  List<cv.Point> points,
  int imageWidth,
  int imageHeight,
  int sensorOrientation,
) {
  if (points.isEmpty) {
    switch (sensorOrientation) {
      case 90:
      case 270:
        return (points, imageHeight, imageWidth);
      default:
        return (points, imageWidth, imageHeight);
    }
  }
  final int w = imageWidth;
  final int h = imageHeight;
  final List<cv.Point> out = [];
  switch (sensorOrientation) {
    case 90:
      // Rotate 90° CW: (x,y) -> (h-1-y, x); display size H×W
      for (final p in points) {
        out.add(cv.Point(h - 1 - p.y, p.x));
      }
      return (out, h, w);
    case 180:
      for (final p in points) {
        out.add(cv.Point(w - 1 - p.x, h - 1 - p.y));
      }
      return (out, w, h);
    case 270:
      // Rotate 270° CW: (x,y) -> (y, w-1-x); display size H×W
      for (final p in points) {
        out.add(cv.Point(p.y, w - 1 - p.x));
      }
      return (out, h, w);
    default:
      return (List.from(points), w, h);
  }
}

/// Draws one point per edge pixel in image space; scales to preview layout.
/// If [contentRect] is set, draws inside that rect (e.g. camera's letterboxed texture rect); otherwise uses [previewSize] and [previewFit].
class EdgeOverlayPainter extends CustomPainter {
  EdgeOverlayPainter({
    required this.edgePoints,
    required this.imageWidth,
    required this.imageHeight,
    required this.previewSize,
    this.contentRect,
    this.previewFit = BoxFit.contain,
    this.color = const Color(0xFF00FF00),
    this.pointMode = PointMode.points,
    this.strokeWidth = 1.5,
  });

  final List<cv.Point> edgePoints;
  final int imageWidth;
  final int imageHeight;
  final Size previewSize;
  /// When set, overlay is drawn inside this rect (e.g. camera texture letterbox rect); avoids vertical/horizontal offset.
  final Rect? contentRect;
  final BoxFit previewFit;
  final Color color;
  final PointMode pointMode;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (edgePoints.isEmpty || imageWidth <= 0 || imageHeight <= 0) return;

    final double scale;
    final double offsetX;
    final double offsetY;
    if (contentRect != null) {
      final Rect r = contentRect!;
      scale = r.width / imageWidth;
      offsetX = r.left;
      offsetY = r.top;
    } else {
      final double w = size.width;
      final double h = size.height;
      final double scaleX = w / imageWidth;
      final double scaleY = h / imageHeight;
      scale = previewFit == BoxFit.cover
          ? (scaleX > scaleY ? scaleX : scaleY)
          : (scaleX < scaleY ? scaleX : scaleY);
      offsetX = (w - imageWidth * scale) / 2;
      offsetY = (h - imageHeight * scale) / 2;
    }

    final List<Offset> offsets = edgePoints
        .map((p) => Offset(offsetX + p.x * scale, offsetY + p.y * scale))
        .toList();

    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawPoints(pointMode, offsets, paint);
  }

  @override
  bool shouldRepaint(EdgeOverlayPainter oldDelegate) {
    return oldDelegate.edgePoints != edgePoints ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight ||
        oldDelegate.previewSize != previewSize ||
        oldDelegate.contentRect != contentRect ||
        oldDelegate.previewFit != previewFit ||
        oldDelegate.color != color ||
        oldDelegate.pointMode != pointMode ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
