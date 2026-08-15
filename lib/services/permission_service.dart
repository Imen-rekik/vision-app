import 'package:permission_handler/permission_handler.dart';

enum PermissionState { granted, denied, permanentlyDenied }

class PermissionService {
  Future<PermissionState> checkRequired() async {
    final camera = await Permission.camera.status;
    final microphone = await Permission.microphone.status;
    final location = await Permission.locationWhenInUse.status;

    if (camera.isGranted && microphone.isGranted && location.isGranted) {
      return PermissionState.granted;
    }

    if (camera.isPermanentlyDenied ||
        microphone.isPermanentlyDenied ||
        location.isPermanentlyDenied) {
      return PermissionState.permanentlyDenied;
    }

    return PermissionState.denied;
  }

  Future<PermissionState> requestMissing() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
    ].request();

    final camera = statuses[Permission.camera];
    final microphone = statuses[Permission.microphone];
    final location = statuses[Permission.locationWhenInUse];

    if (camera == PermissionStatus.granted &&
        microphone == PermissionStatus.granted &&
        location == PermissionStatus.granted) {
      return PermissionState.granted;
    }

    if (camera == PermissionStatus.permanentlyDenied ||
        microphone == PermissionStatus.permanentlyDenied ||
        location == PermissionStatus.permanentlyDenied) {
      return PermissionState.permanentlyDenied;
    }

    return PermissionState.denied;
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}
