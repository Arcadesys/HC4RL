import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;

import 'camera_image_converter.dart';

/// Writes [CameraImage] to a temp JPEG file and returns the path, or null.
Future<String?> saveCameraImageToTempJpeg(CameraImage image) async {
  final Uint8List? rgb = CameraImageConverter.toRgb(image);
  if (rgb == null) return null;
  final int w = image.width;
  final int h = image.height;
  final img.Image im = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  final Uint8List jpeg = img.encodeJpg(im, quality: 85);
  final dir = await getTemporaryDirectory();
  final file = File(path.join(dir.path, 'frame_${DateTime.now().millisecondsSinceEpoch}.jpg'));
  await file.writeAsBytes(jpeg);
  return file.path;
}
