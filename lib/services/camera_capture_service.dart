import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class CameraCaptureService {
  static const int _maxDimension = 768;

  static const int _jpegQuality = 80;

  Future<Uint8List?> captureFrame(CameraController? controller) async {
    if (controller == null || !controller.value.isInitialized) {
      debugPrint('CameraCaptureService: controller not ready.');
      return null;
    }
    if (controller.value.isTakingPicture) {
      debugPrint('CameraCaptureService: capture already in progress.');
      return null;
    }

    try {
      final XFile file = await controller.takePicture();
      final Uint8List rawBytes = await file.readAsBytes();

      final Uint8List? compressed = await compute(_resizeAndEncode, rawBytes);
      return compressed;
    } catch (e) {
      debugPrint('CameraCaptureService: capture/compress failed: $e');
      return null;
    }
  }

  static Uint8List? _resizeAndEncode(Uint8List rawBytes) {
    final image = img.decodeImage(rawBytes);
    if (image == null) return null;

    final resized =
        (image.width > _maxDimension || image.height > _maxDimension)
        ? img.copyResize(
            image,
            width: image.width >= image.height ? _maxDimension : null,
            height: image.height > image.width ? _maxDimension : null,
          )
        : image;

    return Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
  }
}
