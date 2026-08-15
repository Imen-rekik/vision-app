import '../services/onboarding_service.dart';
import '../services/permission_service.dart';

enum StartupDestination {
  permissions,
  voiceOnboarding,
  permissionRecovery,
  home,
}

class StartupController {
  final OnboardingService _onboardingService;
  final PermissionService _permissionService;

  StartupController({
    required OnboardingService onboardingService,
    required PermissionService permissionService,
  }) : _onboardingService = onboardingService,
       _permissionService = permissionService;

  Future<StartupDestination> determineDestination() async {
    final permissionState = await _permissionService.checkRequired();

    // Permanently denied means the OS will no longer show the system
    // permission dialog — sending the user back through PermissionsScreen
    // (which just calls requestMissing()) would silently do nothing. They
    // need the "open Settings" flow instead, regardless of onboarding state.
    if (permissionState == PermissionState.permanentlyDenied) {
      return StartupDestination.permissionRecovery;
    }

    if (permissionState != PermissionState.granted) {
      return StartupDestination.permissions;
    }

    // Permission is granted from here on. `isInteractiveOnboardingCompleted`
    // is the flag actually written by VoiceOnboardingScreen/HowToUseScreen;
    // `isCompleted` is legacy and unused elsewhere in the app.
    final hasOnboarded = await _onboardingService
        .isInteractiveOnboardingCompleted();
    if (!hasOnboarded) {
      return StartupDestination.voiceOnboarding;
    }

    return StartupDestination.home;
  }
}
