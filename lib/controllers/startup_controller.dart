import '../services/onboarding_service.dart';
import '../services/permission_service.dart';

enum StartupDestination {
  permissions,
  voiceOnboarding,
  permissionRecovery,
  home,
}

class StartupController {
  static const bool debugSkipOnboarding = false;

  final OnboardingService _onboardingService;
  final PermissionService _permissionService;

  StartupController({
    required OnboardingService onboardingService,
    required PermissionService permissionService,
  }) : _onboardingService = onboardingService,
       _permissionService = permissionService;

  Future<StartupDestination> determineDestination() async {
    final permissionState = await _permissionService.checkRequired();

    if (permissionState == PermissionState.permanentlyDenied) {
      return StartupDestination.permissionRecovery;
    }

    if (permissionState != PermissionState.granted) {
      return StartupDestination.permissions;
    }

    if (debugSkipOnboarding) {
      return StartupDestination.home;
    }

    final hasOnboarded = await _onboardingService
        .isInteractiveOnboardingCompleted();
    if (!hasOnboarded) {
      return StartupDestination.voiceOnboarding;
    }

    return StartupDestination.home;
  }
}
