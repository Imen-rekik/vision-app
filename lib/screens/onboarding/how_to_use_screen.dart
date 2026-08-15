import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';
import '../../services/onboarding_service.dart';
import '../../services/speech_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/celestial_background.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';

class HowToUseScreen extends StatefulWidget {
  const HowToUseScreen({super.key});

  @override
  State<HowToUseScreen> createState() => _HowToUseScreenState();
}

class _HowToUseScreenState extends State<HowToUseScreen> {
  final SpeechService _speechService = SpeechService();
  final OnboardingService _onboardingService = OnboardingService();
  final TranslationService _translationService = TranslationService();

  String _titleText = AppStrings.howToUseTitle;
  String _subtitleText =
      '${AppStrings.howToUseSubtitleSay} "${AppStrings.wakeWordPhrase}" ${AppStrings.howToUseSubtitleToStart}\n${AppStrings.howToUseSubtitleSay} "${AppStrings.stopWordPhrase}" ${AppStrings.howToUseSubtitleToEnd}';

  @override
  void initState() {
    super.initState();
    _playWalkthrough();
  }

  Future<void> _playWalkthrough() async {
    final preferredLang = await _onboardingService.getPreferredLanguage();
    final deviceLang =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final activeLang =
        preferredLang ?? (deviceLang.isEmpty ? 'en' : deviceLang);

    await _speechService.setLanguage(activeLang);
    if (preferredLang != null && preferredLang.isNotEmpty) {
      await _translationService.init(preferredLang);
    }

    _titleText = await _translationService.translate(AppStrings.howToUseTitle);

    final say = await _translationService.translate(
      AppStrings.howToUseSubtitleSay,
    );
    final toStart = await _translationService.translate(
      AppStrings.howToUseSubtitleToStart,
    );
    final toEnd = await _translationService.translate(
      AppStrings.howToUseSubtitleToEnd,
    );

    _subtitleText =
        '$say "${AppStrings.wakeWordPhrase}" $toStart\n$say "${AppStrings.stopWordPhrase}" $toEnd';

    if (mounted) setState(() {});

    final wtPart1 = await _translationService.translate(
      AppStrings.howToUseWalkthroughPart1,
    );
    final wtPart2 = await _translationService.translate(
      AppStrings.howToUseWalkthroughPart2,
    );
    final wtPart3 = await _translationService.translate(
      AppStrings.howToUseWalkthroughPart3,
    );

    final walkthroughMsg =
        '$wtPart1${AppStrings.wakeWordPhrase}$wtPart2${AppStrings.stopWordPhrase}$wtPart3';

    await _speechService.speakAndAwait(walkthroughMsg);

    await _onboardingService.markCompleted();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
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
                  vertical: 40,
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
                        Icons.waving_hand_rounded,
                        size: 64,
                        color: AppColors.electricCyan,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ExcludeSemantics: title/subtitle are a visual echo of
                    // what SpeechService already speaks aloud (the
                    // walkthrough message). Keeping them focusable would
                    // make TalkBack/VoiceOver announce the same thing
                    // twice.
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
                        _subtitleText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.crispWhite.withValues(alpha: 0.9),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
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
