import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';
import '../../models/language_option.dart';
import '../../services/network_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/speech_service.dart';
import '../../services/translation_service.dart';
import '../../utils/locale_utils.dart';
import '../../widgets/celestial_background.dart';
import '../../widgets/glass_card.dart';
import 'permissions_screen.dart';

const Duration _languageSetupTimeout = Duration(seconds: 30);

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  final SpeechService _speechService = SpeechService();
  final OnboardingService _onboardingService = OnboardingService();
  final TranslationService _translationService = TranslationService();

  List<LanguageOption> _languages = [];
  bool _isLoading = true;
  bool _isSelecting = false;
  int? _selectedIndex;
  Timer? _reassuranceTimer;

  @override
  void initState() {
    super.initState();
    _loadLanguagesAndAnnounce();
  }

  @override
  void dispose() {
    _reassuranceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLanguagesAndAnnounce() async {
    final rawLanguages = await _speechService.getLanguages();
    final parsedOptions = LocaleUtils.parseTtsLanguages(rawLanguages);

    if (mounted) {
      setState(() {
        _languages = parsedOptions;
        _isLoading = false;
      });

      await _speechService.speak(AppStrings.selectLanguagePrompt);
    }
  }

  Future<void> _selectLanguage(LanguageOption option, int index) async {
    if (_isSelecting) return;

    HapticFeedback.selectionClick();

    setState(() {
      _isSelecting = true;
      _selectedIndex = index;
    });

    final isEnglish = _translationService.isEnglish(option.locale);

    if (isEnglish) {
      try {
        _speechService
            .speak(AppStrings.settingUpLanguage)
            .catchError((e) => debugPrint('SpeechService error: $e'));

        _speechService
            .setLanguage(option.ttsLocale)
            .catchError((e) => debugPrint('SpeechService error: $e'));

        await _onboardingService.setSelectedLanguage(option.locale);

        _reassuranceTimer = Timer(const Duration(seconds: 15), () {
          if (_isSelecting && mounted) {
            _speechService
                .speak(AppStrings.stillSettingUpLanguage)
                .catchError((e) => debugPrint('SpeechService error: $e'));
          }
        });

        try {
          await _translationService
              .init(option.locale)
              .timeout(_languageSetupTimeout, onTimeout: () => false);
        } catch (e) {
          debugPrint('TranslationService init error: $e');
        }
      } finally {
        _reassuranceTimer?.cancel();
        _reassuranceTimer = null;

        if (mounted) {
          setState(() {
            _isSelecting = false;
            _selectedIndex = null;
          });
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionsScreen()),
      );
      return;
    }

    try {
      _speechService
          .speak(AppStrings.settingUpLanguage)
          .catchError((e) => debugPrint('SpeechService error: $e'));

      _speechService
          .setLanguage(option.ttsLocale)
          .catchError((e) => debugPrint('SpeechService error: $e'));

      final hasInternet = await NetworkService().hasRealInternetAccess();
      if (!hasInternet) {
        _reassuranceTimer?.cancel();
        _reassuranceTimer = null;

        if (mounted) {
          setState(() {
            _isSelecting = false;
            _selectedIndex = null;
          });
        }

        await _speechService
            .speak(AppStrings.languageRequiresInternet)
            .catchError((e) => debugPrint('SpeechService error: $e'));
        return;
      }

      _reassuranceTimer = Timer(const Duration(seconds: 15), () {
        if (_isSelecting && mounted) {
          _speechService
              .speak(AppStrings.stillSettingUpLanguage)
              .catchError((e) => debugPrint('SpeechService error: $e'));
        }
      });

      bool initSucceeded;
      try {
        initSucceeded = await _translationService
            .init(option.locale)
            .timeout(_languageSetupTimeout, onTimeout: () => false);
      } catch (e) {
        debugPrint('TranslationService init error: $e');
        initSucceeded = false;
      }

      if (!initSucceeded) {
        _reassuranceTimer?.cancel();
        _reassuranceTimer = null;

        if (mounted) {
          setState(() {
            _isSelecting = false;
            _selectedIndex = null;
          });
        }

        await _speechService
            .speak(AppStrings.languageRequiresInternet)
            .catchError((e) => debugPrint('SpeechService error: $e'));
        return;
      }

      await _onboardingService.setSelectedLanguage(option.locale);
      _reassuranceTimer?.cancel();
      _reassuranceTimer = null;

      if (mounted) {
        setState(() {
          _isSelecting = false;
          _selectedIndex = null;
        });
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionsScreen()),
      );
    } catch (e) {
      debugPrint('Language selection error: $e');
      _reassuranceTimer?.cancel();
      _reassuranceTimer = null;

      if (mounted) {
        setState(() {
          _isSelecting = false;
          _selectedIndex = null;
        });
      }

      await _speechService
          .speak(AppStrings.languageRequiresInternet)
          .catchError((e) => debugPrint('SpeechService error: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          AppStrings.selectLanguageTitle,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: CelestialBackground(
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: ExcludeSemantics(
                    child: CircularProgressIndicator(
                      color: AppColors.electricCyan,
                    ),
                  ),
                )
              : _languages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: GlassCard(
                      child: Text(
                        AppStrings.noLanguagesFound,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                )
              : Semantics(
                  liveRegion: _isSelecting,
                  label: _isSelecting ? AppStrings.settingUpLanguage : null,
                  child: IgnorePointer(
                    ignoring: _isSelecting,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      itemCount: _languages.length,
                      itemBuilder: (context, index) {
                        final option = _languages[index];
                        final isThisSelected =
                            _isSelecting && _selectedIndex == index;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: GlassCard(
                            onTap: () => _selectLanguage(option, index),
                            semanticsLabel: option.displayName,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.electricCyan.withValues(
                                      alpha: 0.15,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.language_rounded,
                                    color: AppColors.electricCyan,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.displayName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        option.locale,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: AppColors.topLightBlue,
                                              fontSize: 14,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isThisSelected)
                                  const ExcludeSemantics(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: AppColors.electricCyan,
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 20,
                                    color: AppColors.electricCyan,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
