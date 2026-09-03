import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../controllers/startup_controller.dart';
import '../../core/constants/app_strings.dart';
import '../../services/network_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/permission_service.dart';
import '../../services/speech_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/celestial_background.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';
import '../onboarding/permissions_screen.dart';
import '../onboarding/voice_onboarding_screen.dart';
import '../permission_recovery/permission_recovery_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final SpeechService _speechService = SpeechService();
  final NetworkService _networkService = NetworkService();
  final TranslationService _translationService = TranslationService();
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _networkService.init();

    final startupController = StartupController(
      onboardingService: OnboardingService(),
      permissionService: PermissionService(),
    );

    await Future.delayed(const Duration(seconds: 1));

    await _speechService.init();
    await Future.delayed(const Duration(milliseconds: 300));

    final preferredLang = await OnboardingService().getPreferredLanguage();
    final String deviceLocale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final String resolvedLocale =
        (preferredLang != null && preferredLang.trim().isNotEmpty)
        ? preferredLang.trim().toLowerCase()
        : (deviceLocale.isEmpty ? 'en' : deviceLocale.toLowerCase());

    await _speechService.setLanguage(resolvedLocale);

    final isEnglish = _translationService.isEnglish(resolvedLocale);
    if (!isEnglish) {
      if (mounted) setState(() => _statusText = 'Downloading language pack...');
    }

    await _translationService.init(resolvedLocale);

    if (mounted) setState(() => _statusText = '');

    final welcomeMsg = await _translationService.translate(
      AppStrings.welcomeToVision,
    );
    await _speechService.speakAndAwait(welcomeMsg);
    await Future.delayed(const Duration(milliseconds: 1800));

    final destination = await startupController.determineDestination();

    if (!mounted) return;

    switch (destination) {
      case StartupDestination.permissions:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PermissionsScreen()),
        );
        break;
      case StartupDestination.voiceOnboarding:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const VoiceOnboardingScreen()),
        );
        break;
      case StartupDestination.permissionRecovery:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PermissionRecoveryScreen()),
        );
        break;
      case StartupDestination.home:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CelestialBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.electricCyan.withValues(alpha: 0.15),
                      border: Border.all(
                        color: AppColors.electricCyan.withValues(alpha: 0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.electricCyan.withValues(alpha: 0.3),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.visibility_rounded,
                      size: 72,
                      color: AppColors.electricCyan,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Vision',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: 44,
                      letterSpacing: 1.5,
                      shadows: [
                        Shadow(
                          color: AppColors.electricCyan.withValues(alpha: 0.5),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'AI Visual Assistant',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.topLightBlue,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const ExcludeSemantics(
                    child: CircularProgressIndicator(
                      color: AppColors.electricCyan,
                      strokeWidth: 3,
                    ),
                  ),
                  if (_statusText.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.topLightBlue.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
