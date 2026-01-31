import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../services/camera_service.dart';
import '../../utils/camera_image_converter.dart';
import 'edge_detector_service.dart'
    show
        EdgeDetectorInput,
        EdgeDetectorOutput,
        EdgeMode,
        EdgePreset,
        kSobelApertureSizes,
        runEdgeDetection;
import 'edge_overlay_painter.dart'
    show EdgeOverlayPainter, rotateEdgePointsForDisplay;

/// Overlay colors for edge drawing.
const List<Color> kEdgeOverlayColors = [
  Color(0xFF00FF00), // green (default)
  Color(0xFFFFFFFF), // white
  Color(0xFF00FFFF), // cyan
  Color(0xFFFFA500), // orange
];

/// Stroke width presets (thin / medium / thick).
const List<double> kStrokeWidths = [1.0, 1.5, 2.5];

class EdgeScreen extends StatefulWidget {
  const EdgeScreen({super.key});

  @override
  State<EdgeScreen> createState() => _EdgeScreenState();
}

class _EdgeScreenState extends State<EdgeScreen> {
  CameraController? _controller;
  List<cv.Point> _edgePoints = [];
  int _imageWidth = 0;
  int _imageHeight = 0;
  Size _previewSize = Size.zero;
  bool _processing = false;
  String? _error;

  /// False when this device doesn't support image streaming (no edge frames).
  bool _imageStreamSupported = true;

  /// Skip every other frame to reduce main-thread load (e.g. ~10–15 fps effective).
  int _frameSkipCounter = 0;

  // Settings (drawer)
  EdgeMode _edgeMode = EdgeMode.inspect;
  EdgePreset _edgePreset = EdgePreset.normal;
  int _overlayColorIndex = 0;
  int _strokeWidthIndex = 1; // medium
  int _sobelApertureIndex = 0; // 3 (sharper) by default
  bool _dimmedView = false;
  bool _enhanceBeforeEdges = false;
  /// Min contour area (pixels²); contours below this are dropped. 0 = show all.
  int _minContourArea = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final CameraController controller = await CameraService.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _error = null;
      });
      final bool streamSupported =
          await CameraService.supportsImageStreaming(controller);
      if (!mounted) return;
      if (!streamSupported) {
        setState(() => _imageStreamSupported = false);
        return;
      }
      await CameraService.startImageStream(controller, _onImage);
    } catch (e, st) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
      debugPrintStack(stackTrace: st, label: e.toString());
    }
  }

  void _onImage(CameraImage image) {
    if (_processing) return;
    _frameSkipCounter++;
    if (_frameSkipCounter % 2 != 0)
      return; // Process every 2nd frame to reduce load
    final Uint8List? gray = CameraImageConverter.toGrayscale(image);
    if (gray == null || !mounted) return;
    _processing = true;
    final int w = image.width;
    final int h = image.height;
    final EdgePreset preset = _edgePreset;
    final bool enhance = _enhanceBeforeEdges;
    final int minArea = _edgeMode == EdgeMode.find
        ? (_minContourArea < 200 ? 200 : _minContourArea)
        : _minContourArea;
    final EdgeDetectorInput input = EdgeDetectorInput(
      width: w,
      height: h,
      bytes: gray,
      cannyLow: preset.cannyLow,
      cannyHigh: preset.cannyHigh,
      blurKernelSize: preset.blurKernelSize,
      blurSigma: preset.blurSigma,
      sobelApertureSize: kSobelApertureSizes[
          _sobelApertureIndex.clamp(0, kSobelApertureSizes.length - 1)],
      enhanceBeforeEdges: enhance,
      minContourArea: minArea,
    );
    // Run on main isolate: opencv_dart/FFI often fails inside compute() on mobile.
    Future<EdgeDetectorOutput>(() => runEdgeDetection(input))
        .then((EdgeDetectorOutput out) {
      if (!mounted) return;
      setState(() {
        _edgePoints = out.points;
        _imageWidth = w;
        _imageHeight = h;
        _processing = false;
      });
    }).catchError((Object err, StackTrace st) {
      debugPrintStack(stackTrace: st, label: err.toString());
      if (mounted) {
        setState(() {
          _error = 'Edge detection failed. Try reopening.';
          _processing = false;
        });
      }
    });
  }

  @override
  void dispose() {
    if (_controller != null) {
      CameraService.dispose(_controller!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edge Highlight')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edge Highlight')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // SizedBox in _buildPreview is (contentW × contentH); camera texture (textureW × textureH) is letterboxed inside it.
    final double contentW =
        (_controller!.value.previewSize?.height ?? 1).toDouble();
    final double contentH =
        (_controller!.value.previewSize?.width ?? 1).toDouble();
    final double textureW =
        (_controller!.value.previewSize?.width ?? 1).toDouble();
    final double textureH =
        (_controller!.value.previewSize?.height ?? 1).toDouble();

    return Scaffold(
      drawer: _buildDrawer(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final Size size = constraints.biggest;
          _previewSize = size;
          final int sensorOrientation =
              _controller!.value.description.sensorOrientation;
          final (overlayPoints, overlayWidth, overlayHeight) =
              rotateEdgePointsForDisplay(
            _edgePoints,
            _imageWidth,
            _imageHeight,
            sensorOrientation,
          );
          // Scale edge points to texture space (same as camera's letterboxed texture).
          final List<cv.Point> scaledPoints =
              overlayWidth > 0 && overlayHeight > 0
                  ? overlayPoints
                      .map((p) => cv.Point(
                            (p.x * textureW / overlayWidth).round(),
                            (p.y * textureH / overlayHeight).round(),
                          ))
                      .toList()
                  : overlayPoints;
          // Where the camera texture actually appears: letterboxed inside SizedBox, then cover to screen.
          final double letterboxScale = (contentW / textureW) < (contentH / textureH)
              ? contentW / textureW
              : contentH / textureH;
          final double textureInContentW = textureW * letterboxScale;
          final double textureInContentH = textureH * letterboxScale;
          final double marginX = (contentW - textureInContentW) / 2;
          final double marginY = (contentH - textureInContentH) / 2;
          final double coverScale = (size.width / contentW) > (size.height / contentH)
              ? size.width / contentW
              : size.height / contentH;
          final double offsetX = (size.width - contentW * coverScale) / 2;
          final double offsetY = (size.height - contentH * coverScale) / 2;
          final Rect textureRect = Rect.fromLTWH(
            offsetX + marginX * coverScale,
            offsetY + marginY * coverScale,
            textureInContentW * coverScale,
            textureInContentH * coverScale,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: _buildPreview(size)),
              if (!_imageStreamSupported)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Material(
                    color: Colors.black87,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          'Image streaming not supported on this device. Edges cannot be shown.',
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_dimmedView)
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.4)),
                ),
              Positioned.fill(
                child: CustomPaint(
                  painter: EdgeOverlayPainter(
                    edgePoints: scaledPoints,
                    imageWidth: textureW.round(),
                    imageHeight: textureH.round(),
                    previewSize: _previewSize,
                    contentRect: textureRect,
                    color: kEdgeOverlayColors[_overlayColorIndex],
                    strokeWidth: kStrokeWidths[_strokeWidthIndex],
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_edgePreset == EdgePreset.highContrast)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Material(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                child: Text(
                                  'High contrast',
                                  style: TextStyle(
                                    color:
                                        kEdgeOverlayColors[_overlayColorIndex],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(24),
                          child: IconButton(
                            icon:
                                const Icon(Icons.settings, color: Colors.white),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.teal),
            child: Text(
              'Edge Highlight',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          _sectionTitle('Mode'),
          ...EdgeMode.values.map((mode) {
            final isSelected = _edgeMode == mode;
            return ListTile(
              title: Text(mode == EdgeMode.find ? 'Find (object boundaries)' : 'Inspect (fine detail)'),
              subtitle: Text(
                mode == EdgeMode.find
                    ? 'Fewer lines, thicker, higher confidence'
                    : 'More lines, finer detail',
              ),
              trailing: isSelected ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() {
                  _edgeMode = mode;
                  if (mode == EdgeMode.find) {
                    _edgePreset = EdgePreset.highContrast;
                    _minContourArea = _minContourArea < 200 ? 200 : _minContourArea;
                    _strokeWidthIndex = 2; // thick
                  } else {
                    _edgePreset = EdgePreset.normal;
                    _minContourArea = 0;
                    _strokeWidthIndex = 0; // thin
                  }
                });
                Navigator.of(context).pop();
              },
            );
          }),
          const Divider(),
          _sectionTitle('Edge detection'),
          ListTile(
            title: const Text('Sobel aperture'),
            subtitle: Text(_sobelApertureLabel(_sobelApertureIndex)),
            onTap: () => _showSobelPicker(context),
          ),
          ...EdgePreset.values.map((p) {
            final isSelected = _edgePreset == p;
            return ListTile(
              title: Text(_presetLabel(p)),
              trailing: isSelected ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _edgePreset = p);
                Navigator.of(context).pop();
              },
            );
          }),
          _sectionTitle('Noise (min contour size)'),
          ListTile(
            title: const Text('Min contour area'),
            subtitle: Text(_noiseLabel(_minContourArea)),
            onTap: () => _showNoiseSlider(context),
          ),
          const Divider(),
          _sectionTitle('High-contrast / view'),
          ListTile(
            title: const Text('Overlay color'),
            subtitle: Text(_colorLabel(_overlayColorIndex)),
            onTap: () => _showColorPicker(context),
          ),
          ListTile(
            title: const Text('Stroke width'),
            subtitle: Text(_strokeLabel(_strokeWidthIndex)),
            onTap: () => _showStrokePicker(context),
          ),
          SwitchListTile(
            title: const Text('Edges on dimmed video'),
            value: _dimmedView,
            onChanged: (v) {
              setState(() => _dimmedView = v);
            },
          ),
          const Divider(),
          _sectionTitle('Enhancement'),
          SwitchListTile(
            title: const Text('Enhance for low light'),
            subtitle: const Text('CLAHE before edge detection'),
            value: _enhanceBeforeEdges,
            onChanged: (v) {
              setState(() => _enhanceBeforeEdges = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  String _presetLabel(EdgePreset p) {
    switch (p) {
      case EdgePreset.lowLight:
        return 'Low light';
      case EdgePreset.normal:
        return 'Normal';
      case EdgePreset.highContrast:
        return 'High contrast';
    }
  }

  String _colorLabel(int i) {
    const labels = ['Green', 'White', 'Cyan', 'Orange'];
    return labels[i.clamp(0, labels.length - 1)];
  }

  String _strokeLabel(int i) {
    const labels = ['Thin', 'Medium', 'Thick'];
    return labels[i.clamp(0, labels.length - 1)];
  }

  String _sobelApertureLabel(int i) {
    final k = kSobelApertureSizes[i.clamp(0, kSobelApertureSizes.length - 1)];
    if (k == 3) return '3 — sharper gradients';
    if (k == 5) return '5 — balanced';
    return '7 — smoother gradients';
  }

  static const int _noiseSliderMax = 1000;
  String _noiseLabel(int minArea) {
    if (minArea <= 0) return 'Off (show all)';
    if (minArea < 200) return 'Low ($minArea px²)';
    if (minArea < 500) return 'Medium ($minArea px²)';
    return 'High ($minArea px²)';
  }

  void _showNoiseSlider(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Min contour area (noise filter)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _noiseLabel(_minContourArea),
                style: const TextStyle(color: Colors.grey),
              ),
              Slider(
                value: _minContourArea
                    .toDouble()
                    .clamp(0.0, _noiseSliderMax.toDouble()),
                min: 0,
                max: _noiseSliderMax.toDouble(),
                divisions: 20,
                label: _noiseLabel(_minContourArea),
                onChanged: (v) {
                  setState(() => _minContourArea = v.round());
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showSobelPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sobel aperture',
                style: TextStyle(fontSize: 18),
              ),
            ),
            ...List.generate(kSobelApertureSizes.length, (i) {
              return ListTile(
                title: Text(_sobelApertureLabel(i)),
                onTap: () {
                  setState(() => _sobelApertureIndex = i);
                  Navigator.of(context).pop();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Overlay color', style: TextStyle(fontSize: 18)),
            ),
            ...List.generate(kEdgeOverlayColors.length, (i) {
              return ListTile(
                title: Text(_colorLabel(i)),
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: kEdgeOverlayColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                onTap: () {
                  setState(() => _overlayColorIndex = i);
                  Navigator.of(context).pop();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showStrokePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Stroke width', style: TextStyle(fontSize: 18)),
            ),
            ...List.generate(kStrokeWidths.length, (i) {
              return ListTile(
                title: Text(_strokeLabel(i)),
                onTap: () {
                  setState(() => _strokeWidthIndex = i);
                  Navigator.of(context).pop();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(Size size) {
    final CameraController c = _controller!;
    // Use non-zero fallback so layout never collapses; FittedBox.cover = full screen.
    final double w = (c.value.previewSize?.height ?? 1).toDouble();
    final double h = (c.value.previewSize?.width ?? 1).toDouble();
    return FittedBox(
      fit: BoxFit.cover,
      alignment: Alignment.center,
      child: SizedBox(
        width: w,
        height: h,
        child: CameraPreview(c),
      ),
    );
  }
}
