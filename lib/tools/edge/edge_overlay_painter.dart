import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../utils/debug_log.dart';

/// Rotates edge points from camera image space to display space so the overlay
/// matches the rotated preview. [sensorOrientation] is the clockwise angle
/// (0, 90, 180, 270) the image must be rotated to be upright.
/// Returns (rotated points, display width, display height).
(List<cv.Point> points, int displayWidth, int displayHeight)
    rotateEdgePointsForDisplay(
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
    this.invertEdges = false,
    this.contours,
    this.selectedContourIndex = -1,
    this.strengths,
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

  /// When true, draw edges dark on bright (e.g. black) for light backgrounds.
  final bool invertEdges;

  /// Contours in same space as edgePoints (for tap-to-focus). When [selectedContourIndex] >= 0, draw selected bold and others faded.
  final List<List<cv.Point>>? contours;
  final int selectedContourIndex;

  /// Optional per-point strength (same length as edgePoints) for thickness-by-confidence.
  final List<double>? strengths;

  @override
  void paint(Canvas canvas, Size size) {
    // #region agent log
    debugLog(
        'edge_overlay_painter.dart:paint',
        'paint entry',
        {
          'edgePoints.length': edgePoints.length,
          'imageWidth': imageWidth,
          'imageHeight': imageHeight,
          'contentRect': contentRect?.toString(),
          'size': size.toString(),
          'firstPoint': edgePoints.isNotEmpty
              ? '${edgePoints.first.x},${edgePoints.first.y}'
              : null,
        },
        'H4');
    // #endregion
    if (edgePoints.isEmpty || imageWidth <= 0 || imageHeight <= 0) return;

    final double scale;
    final double offsetX;
    final double offsetY;
    if (contentRect != null) {
      final Rect r = contentRect!;
      scale = r.width / imageWidth;
      offsetX = r.left;
      offsetY = r.top;
      // #region agent log
      if (edgePoints.isNotEmpty) {
        final double sx = offsetX + edgePoints.first.x * scale;
        final double sy = offsetY + edgePoints.first.y * scale;
        debugLog(
            'edge_overlay_painter.dart:paint',
            'contentRect transform',
            {
              'scale': scale,
              'offsetX': offsetX,
              'offsetY': offsetY,
              'rectW': r.width,
              'rectH': r.height,
              'sampleScreenX': sx,
              'sampleScreenY': sy,
              'canvasSize': '${size.width}x${size.height}'
            },
            'H5');
      }
      // #endregion
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

    final Color drawColor = invertEdges ? const Color(0xFF000000) : color;

    final bool hasSelection = contours != null &&
        contours!.isNotEmpty &&
        selectedContourIndex >= 0 &&
        selectedContourIndex < contours!.length;
    final bool hasStrengths = !hasSelection &&
        strengths != null &&
        strengths!.length == edgePoints.length &&
        strengths!.isNotEmpty;

    if (hasSelection) {
      final Color dimColor = drawColor.withValues(alpha: 0.25);
      final Paint dimPaint = Paint()
        ..color = dimColor
        ..strokeWidth = strokeWidth * 0.8
        ..strokeCap = StrokeCap.round;
      final Paint boldPaint = Paint()
        ..color = drawColor
        ..strokeWidth = strokeWidth * 1.8
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < contours!.length; i++) {
        final List<Offset> contourOffsets = contours![i]
            .map((p) => Offset(offsetX + p.x * scale, offsetY + p.y * scale))
            .toList();
        if (contourOffsets.isEmpty) continue;
        if (i == selectedContourIndex) {
          canvas.drawPoints(pointMode, contourOffsets, boldPaint);
        } else {
          canvas.drawPoints(pointMode, contourOffsets, dimPaint);
        }
      }
    } else if (hasStrengths) {
      final List<int> indices = List.generate(edgePoints.length, (i) => i);
      indices.sort((a, b) => strengths![a].compareTo(strengths![b]));
      final int n = indices.length;
      final int weakEnd = (n * 0.33).round().clamp(0, n);
      final int strongStart = (n * 0.67).round().clamp(0, n);
      final double thin = strokeWidth * 0.6;
      final double thick = strokeWidth * 1.5;
      final Paint thinPaint = Paint()
        ..color = drawColor
        ..strokeWidth = thin
        ..strokeCap = StrokeCap.round;
      final Paint midPaint = Paint()
        ..color = drawColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final Paint thickPaint = Paint()
        ..color = drawColor
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round;
      final List<Offset> weakOffsets = indices
          .sublist(0, weakEnd)
          .map((i) => Offset(offsetX + edgePoints[i].x * scale,
              offsetY + edgePoints[i].y * scale))
          .toList();
      final List<Offset> midOffsets = indices
          .sublist(weakEnd, strongStart)
          .map((i) => Offset(offsetX + edgePoints[i].x * scale,
              offsetY + edgePoints[i].y * scale))
          .toList();
      final List<Offset> strongOffsets = indices
          .sublist(strongStart)
          .map((i) => Offset(offsetX + edgePoints[i].x * scale,
              offsetY + edgePoints[i].y * scale))
          .toList();
      if (weakOffsets.isNotEmpty)
        canvas.drawPoints(pointMode, weakOffsets, thinPaint);
      if (midOffsets.isNotEmpty)
        canvas.drawPoints(pointMode, midOffsets, midPaint);
      if (strongOffsets.isNotEmpty)
        canvas.drawPoints(pointMode, strongOffsets, thickPaint);
    } else {
      final List<Offset> offsets = edgePoints
          .map((p) => Offset(offsetX + p.x * scale, offsetY + p.y * scale))
          .toList();
      final Paint paint = Paint()
        ..color = drawColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawPoints(pointMode, offsets, paint);
    }
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
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.invertEdges != invertEdges ||
        oldDelegate.contours != contours ||
        oldDelegate.selectedContourIndex != selectedContourIndex ||
        oldDelegate.strengths != strengths;
  }
}
