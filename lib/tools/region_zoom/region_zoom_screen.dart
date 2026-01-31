import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/camera_service.dart';

class RegionZoomScreen extends StatefulWidget {
  const RegionZoomScreen({super.key});

  @override
  State<RegionZoomScreen> createState() => _RegionZoomScreenState();
}

class _RegionZoomScreenState extends State<RegionZoomScreen> {
  CameraController? _controller;
  String? _error;
  double _zoomLevel = 2.0; // 1 = full, 2 = 2x center crop

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final controller = await CameraService.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    if (_controller != null) CameraService.dispose(_controller!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Region Zoom')),
        body: Center(child: Text(_error!)),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Region Zoom')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Region Zoom')),
      body: Column(
        children: [
          Expanded(
            child: _ZoomedPreview(
              controller: _controller!,
              zoomLevel: _zoomLevel,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('Zoom'),
                  Expanded(
                    child: Slider(
                      value: _zoomLevel,
                      min: 1.0,
                      max: 4.0,
                      onChanged: (v) => setState(() => _zoomLevel = v),
                    ),
                  ),
                  Text('${_zoomLevel.toStringAsFixed(1)}×'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Virtual crop: center region scaled by zoomLevel (1 = full, 2 = 2x center).
class _ZoomedPreview extends StatelessWidget {
  const _ZoomedPreview({
    required this.controller,
    required this.zoomLevel,
  });
  final CameraController controller;
  final double zoomLevel;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 0,
            height: controller.value.previewSize?.width ?? 0,
            child: Transform.scale(
              scale: zoomLevel,
              alignment: Alignment.center,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }
}
