import 'package:face_verification/face_verification.dart';

/// Wraps face_verification: init once, register by path, verify by path.
class FaceVerificationService {
  static bool _inited = false;

  static Future<void> ensureInit() async {
    if (_inited) return;
    await FaceVerification.instance.init();
    _inited = true;
  }

  static Future<void> registerFromPath({
    required String personId,
    required String imagePath,
    String imageId = 'main',
    bool replace = false,
  }) async {
    await ensureInit();
    await FaceVerification.instance.registerFromImagePath(
      id: personId,
      imagePath: imagePath,
      imageId: imageId,
      replace: replace,
    );
  }

  /// Returns matched person id, or null.
  static Future<String?> verifyFromPath({
    required String imagePath,
    double threshold = 0.70,
  }) async {
    await ensureInit();
    return FaceVerification.instance.verifyFromImagePath(
      imagePath: imagePath,
      threshold: threshold,
    );
  }
}
