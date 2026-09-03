import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../controllers/startup_controller.dart';
import '../../core/constants/app_strings.dart';
import '../../services/onboarding_service.dart';
import '../../services/permission_service.dart';
import '../../services/speech_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/celestial_background.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';
import '../permission_recovery/permission_recovery_screen.dart';
import 'voice_onboarding_screen.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final SpeechService _speechService = SpeechService();
  final PermissionService _permissionService = PermissionService();
  final TranslationService _translationService = TranslationService();

  bool _isRequesting = false;
  String _titleText = AppStrings.permissionsTitle;
  String _descriptionText = AppStrings.permissionsDescription;

  @override
  void initState() {
    super.initState();
    _explainAndRequest();
  }

  Future<void> _explainAndRequest() async {
    final preferredLang = await OnboardingService().getPreferredLanguage();
    final deviceLang =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final resolvedLang =
        preferredLang ?? (deviceLang.isEmpty ? 'en' : deviceLang);
    await _speechService.setLanguage(resolvedLang);
    await _translationService.init(resolvedLang);

    _titleText = await _translationService.translate(
      AppStrings.permissionsTitle,
    );
    _descriptionText = await _translationService.translate(
      AppStrings.permissionsDescription,
    );

    if (mounted) setState(() {});

    final explanation = await _translationService.translate(
      AppStrings.permissionsExplanation,
    );
    await _speechService.speakAndAwait(explanation);

    if (!mounted) return;
    setState(() => _isRequesting = true);

    final status = await _permissionService.requestMissing();

    if (!mounted) return;

    if (status == PermissionState.granted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => StartupController.debugSkipOnboarding
              ? const HomeScreen()
              : const VoiceOnboardingScreen(),
        ),
      );
    } else {
      final notGranted = await _translationService.translate(
        AppStrings.permissionsNotGranted,
      );
      await _speechService.speakAndAwait(notGranted);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionRecoveryScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CelestialBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 36,
                ),
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
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        size: 64,
                        color: AppColors.electricCyan,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ExcludeSemantics(
                      child: Text(
                        _titleText,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(fontSize: 30),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ExcludeSemantics(
                      child: Text(
                        _descriptionText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.crispWhite.withValues(alpha: 0.9),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isRequesting)
                      const ExcludeSemantics(
                        child: CircularProgressIndicator(
                          color: AppColors.electricCyan,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
