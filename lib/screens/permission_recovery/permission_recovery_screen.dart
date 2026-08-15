import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';
import '../../services/onboarding_service.dart';
import '../../services/permission_service.dart';
import '../../services/speech_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/celestial_background.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';

class PermissionRecoveryScreen extends StatefulWidget {
  const PermissionRecoveryScreen({super.key});

  @override
  State<PermissionRecoveryScreen> createState() =>
      _PermissionRecoveryScreenState();
}

class _PermissionRecoveryScreenState extends State<PermissionRecoveryScreen> {
  final SpeechService _speechService = SpeechService();
  final PermissionService _permissionService = PermissionService();
  final TranslationService _translationService = TranslationService();

  String _titleText = AppStrings.permissionsRequiredTitle;
  String _descText = AppStrings.permissionsRequiredDesc;
  String _openSettingsText = AppStrings.openSettings;
  String _iHaveGrantedText = AppStrings.iHaveGrantedThem;

  @override
  void initState() {
    super.initState();
    _loadTranslationsAndAnnounce();
  }

  Future<void> _loadTranslationsAndAnnounce() async {
    final preferredLang = await OnboardingService().getPreferredLanguage();
    final deviceLang =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final activeLang =
        preferredLang ?? (deviceLang.isEmpty ? 'en' : deviceLang);

    await _speechService.setLanguage(activeLang);
    if (preferredLang != null && preferredLang.isNotEmpty) {
      await _translationService.init(preferredLang);
    }

    _titleText = await _translationService.translate(
      AppStrings.permissionsRequiredTitle,
    );
    _descText = await _translationService.translate(
      AppStrings.permissionsRequiredDesc,
    );
    _openSettingsText = await _translationService.translate(
      AppStrings.openSettings,
    );
    _iHaveGrantedText = await _translationService.translate(
      AppStrings.iHaveGrantedThem,
    );

    if (mounted) setState(() {});

    final prompt = await _translationService.translate(
      AppStrings.permissionsRecoveryPrompt,
    );
    await _speechService.speak(prompt);
  }

  Future<void> _openSettings() async {
    await _permissionService.openSettings();
  }

  Future<void> _checkAgain() async {
    final state = await _permissionService.checkRequired();
    if (state == PermissionState.granted && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      final missingMsg = await _translationService.translate(
        AppStrings.permissionsStillMissing,
      );
      await _speechService.speak(missingMsg);
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
                        color: AppColors.errorRed.withValues(alpha: 0.2),
                        border: Border.all(
                          color: AppColors.errorRed.withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        size: 64,
                        color: AppColors.errorRed,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _titleText,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(fontSize: 28),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _descText,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.crispWhite.withValues(alpha: 0.9),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    GlassCard(
                      onTap: _openSettings,
                      semanticsLabel: _openSettingsText,
                      fillColor: AppColors.electricCyan.withValues(alpha: 0.25),
                      borderColor: AppColors.electricCyan,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 18,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.settings_rounded,
                            color: AppColors.electricCyan,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _openSettingsText,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontSize: 20,
                                  color: AppColors.electricCyan,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      button: true,
                      label: _iHaveGrantedText,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        child: TextButton(
                          onPressed: _checkAgain,
                          child: Text(
                            _iHaveGrantedText,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: AppColors.topLightBlue,
                                  decoration: TextDecoration.underline,
                                ),
                          ),
                        ),
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
