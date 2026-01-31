import 'package:camera/camera.dart';

/// Shared camera: list cameras, init with low resolution, start/stop stream, dispose.
class CameraService {
  static Future<List<CameraDescription>> getCameras() async {
    return await availableCameras();
  }

  static Future<CameraController> initialize({
    CameraDescription? camera,
    ResolutionPreset resolution = ResolutionPreset.low,
    ImageFormatGroup? imageFormat,
  }) async {
    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No cameras found');
    }
    final CameraDescription desc = camera ?? cameras.first;
    final ImageFormatGroup format =
        imageFormat ?? ImageFormatGroup.yuv420;
    final CameraController controller = CameraController(
      desc,
      resolution,
      imageFormatGroup: format,
    );
    try {
      await controller.initialize();
      return controller;
    } catch (e) {
      controller.dispose();
      if (format == ImageFormatGroup.yuv420) {
        try {
          final CameraController fallback = CameraController(
            desc,
            resolution,
            imageFormatGroup: ImageFormatGroup.bgra8888,
          );
          await fallback.initialize();
          return fallback;
        } catch (_) {
          // Fallback failed; rethrow original
        }
      }
      rethrow;
    }
  }

  static Future<bool> supportsImageStreaming(CameraController controller) async {
    return controller.supportsImageStreaming();
  }

  static Future<void> startImageStream(
    CameraController controller,
    void Function(CameraImage image) onImage,
  ) async {
    if (!await supportsImageStreaming(controller)) return;
    await controller.startImageStream(onImage);
  }

  static Future<void> stopImageStream(CameraController controller) async {
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  static Future<void> dispose(CameraController controller) async {
    await stopImageStream(controller);
    await controller.dispose();
  }
}
