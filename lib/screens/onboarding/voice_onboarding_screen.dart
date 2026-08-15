import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';
import '../../models/language_option.dart';
import '../../services/onboarding_service.dart';
import '../../services/speech_recognition_service.dart';
import '../../services/speech_service.dart';
import '../../services/translation_service.dart';
import '../../utils/locale_utils.dart';
import '../../widgets/celestial_background.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';

class VoiceOnboardingScreen extends StatefulWidget {
  const VoiceOnboardingScreen({super.key});

  @override
  State<VoiceOnboardingScreen> createState() => _VoiceOnboardingScreenState();
}

class _VoiceOnboardingScreenState extends State<VoiceOnboardingScreen> {
  static const Duration _sttResponseTimeout = Duration(seconds: 6);
  static const int _maxSttRetries = 3;
  static const String _defaultGuestName = 'Guest';

  final SpeechService _speechService = SpeechService();
  final SpeechRecognitionService _speechRecognitionService =
      SpeechRecognitionService();
  final OnboardingService _onboardingService = OnboardingService();

  bool _isListening = false;
  bool _isWorking = false;
  String _titleText = AppStrings.voiceOnboardingScreenTitle;
  String _statusText = AppStrings.voiceOnboardingStatusInitial;
  List<LanguageOption> _supportedLanguages = const [];
  String _deviceLocale = 'en';

  final TranslationService _translationService = TranslationService();

  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  /// Speaks [englishText] translated into whatever locale TranslationService
  /// is currently configured for. Falls back to English automatically if
  /// translation isn't set up yet or fails (TranslationService.translate
  /// already handles that internally).
  Future<void> _speak(String englishText) async {
    final translated = await _translationService.translate(englishText);
    await _speechService.speakAndAwait(translated);
  }

  /// Re-translates the on-screen title and current status text into
  /// whatever language TranslationService is currently configured for, and
  /// triggers a rebuild. This keeps the visible text (which a low-vision or
  /// sighted-helper user might read) in sync with the app's chosen
  /// language, on both initial load and after the user picks a language.
  Future<void> _refreshOnScreenText() async {
    _titleText = await _translationService.translate(
      AppStrings.voiceOnboardingScreenTitle,
    );
    _statusText = await _translationService.translate(_currentStatusKey);
    if (mounted) setState(() {});
  }

  /// Tracks the untranslated (English) key for whatever status is currently
  /// being shown, so it can be re-translated on demand (e.g. if the
  /// language changes while a status is on screen) without re-deriving it
  /// from the already-translated `_statusText`.
  String _currentStatusKey = AppStrings.voiceOnboardingStatusInitial;

  /// Updates [_statusText] from an English [statusKey], translating it into
  /// the current app language first. This is the single place that writes
  /// to `_statusText` so that Voice #2 (TalkBack/VoiceOver) — if it were
  /// ever allowed to read this text — and any sighted glance at the screen
  /// would see the same language Vision speaks aloud.
  Future<void> _setStatus(String statusKey) async {
    _currentStatusKey = statusKey;
    _statusText = await _translationService.translate(statusKey);
    if (mounted) setState(() {});
  }

  Future<void> _startFlow() async {
    _isWorking = true;
    if (mounted) setState(() {});

    final rawLanguages = await _speechService.getLanguages();
    _supportedLanguages = LocaleUtils.parseTtsLanguages(rawLanguages);

    final preferred = await _onboardingService.getPreferredLanguage();
    final deviceLang =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _deviceLocale = deviceLang.isEmpty ? 'en' : deviceLang;
    final initialLang = preferred ?? _deviceLocale;

    await _speechService.setLanguage(initialLang);
    // We don't know the user's preferred language yet (that's the question
    // we're about to ask), so use the device locale as a best-effort guess
    // for translating the greeting itself.
    try {
      await _translationService.init(initialLang);
    } catch (_) {
      // Keep onboarding resilient even if translation setup fails.
    }

    // Translate the on-screen title/status now that a best-effort target
    // language is set up, so anyone glancing at the screen (e.g. a sighted
    // helper, or a low-vision user reading rather than listening) sees text
    // in the same language Vision is about to speak.
    await _refreshOnScreenText();

    await _speak(AppStrings.voiceOnboardingGreeting);

    final selectedLanguage = await _askForPreferredLanguage();
    final selectedLocale = selectedLanguage.locale;

    await _onboardingService.setPreferredLanguage(selectedLocale);
    await _onboardingService.setSelectedLanguage(selectedLocale);
    await _speechService.setLanguage(selectedLanguage.ttsLocale);
    try {
      await _translationService.init(selectedLocale);
    } catch (_) {
      // Keep onboarding resilient even if translation setup fails.
    }
    // Re-translate now that the user's *actual* chosen language (not just
    // the device-locale guess) is known.
    await _refreshOnScreenText();

    final userName = await _askForName();
    await _onboardingService.setUserName(userName);

    final chosenLanguageName = selectedLanguage.displayName;
    // Built from translated fragments around dynamic values (name, chosen
    // language, wake/stop phrases) rather than translating one interpolated
    // string, since translate() caches by exact text and the wake/stop
    // phrases must stay in English regardless of the chosen language.
    final part1 = await _translationService.translate(
      AppStrings.voiceOnboardingCompletePart1,
    );
    final part2 = await _translationService.translate(
      AppStrings.voiceOnboardingCompletePart2,
    );
    final part3 = await _translationService.translate(
      AppStrings.voiceOnboardingCompletePart3,
    );
    final part4 = await _translationService.translate(
      AppStrings.voiceOnboardingCompletePart4,
    );
    final part5 = await _translationService.translate(
      AppStrings.voiceOnboardingCompletePart5,
    );
    final completionMessage =
        '$part1$userName$part2$chosenLanguageName$part3'
        '${AppStrings.wakeWordPhrase}$part4${AppStrings.stopWordPhrase}$part5';
    await _speechService.speakAndAwait(completionMessage);

    await _onboardingService.markCompleted();
    await _onboardingService.setInteractiveOnboardingCompleted(true);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<LanguageOption> _askForPreferredLanguage() async {
    for (int attempt = 1; attempt <= _maxSttRetries; attempt++) {
      if (attempt > 1) {
        await _speak(AppStrings.voiceOnboardingLanguageRetry);
      }

      final chosen = await _listenForText(
        listeningStatus: AppStrings.voiceOnboardingStatusListeningLanguage,
      );

      if (chosen == null || chosen.trim().isEmpty) {
        continue;
      }

      final match = _normalizeLanguage(chosen);
      if (match != null) {
        return match;
      }

      await _speak(AppStrings.voiceOnboardingLanguageNotRecognized);
    }

    final fallback = _fallbackLanguageForDevice();
    final prefix = await _translationService.translate(
      AppStrings.voiceOnboardingLanguageFallbackPrefix,
    );
    final suffix = await _translationService.translate(
      AppStrings.voiceOnboardingLanguageFallbackSuffix,
    );
    await _speechService.speakAndAwait('$prefix${fallback.displayName}$suffix');
    return fallback;
  }

  Future<String> _askForName() async {
    for (int attempt = 1; attempt <= _maxSttRetries; attempt++) {
      if (attempt == 1) {
        await _speak(AppStrings.voiceOnboardingAskName);
      } else {
        await _speak(AppStrings.voiceOnboardingAskNameRetry);
      }

      final spokenName = await _listenForText(
        listeningStatus: AppStrings.voiceOnboardingStatusListeningName,
      );

      final normalizedName = _normalizeName(spokenName);
      if (normalizedName != null) {
        return normalizedName;
      }
    }

    final prefix = await _translationService.translate(
      AppStrings.voiceOnboardingNameFallbackPrefix,
    );
    final suffix = await _translationService.translate(
      AppStrings.voiceOnboardingNameFallbackSuffix,
    );
    await _speechService.speakAndAwait('$prefix$_defaultGuestName$suffix');
    return _defaultGuestName;
  }

  Future<String?> _listenForText({required String listeningStatus}) async {
    final completer = Completer<String?>();
    var completed = false;
    var heardAnyText = false;
    String lastHeardText = '';

    _isListening = true;
    _isWorking = true;
    await _setStatus(listeningStatus);

    final isReady = await _speechRecognitionService.init();
    if (!isReady) {
      _isListening = false;
      _isWorking = false;
      if (mounted) setState(() {});
      return null;
    }

    Timer? timeoutTimer;

    try {
      await _speechRecognitionService.startListening(
        onResult: (String text, bool isFinal) {
          if (completed) return;
          final trimmed = text.trim();
          if (trimmed.isNotEmpty) {
            heardAnyText = true;
            lastHeardText = trimmed;
          }

          if (isFinal && trimmed.isNotEmpty) {
            completed = true;
            completer.complete(trimmed);
          }
        },
        onStatus: (String status) {
          if (completed) return;
          if (status == 'done' || status == 'notListening') {
            completed = true;
            completer.complete(lastHeardText.isEmpty ? null : lastHeardText);
          }
        },
        onError: (dynamic error) {
          if (completed) return;
          completed = true;
          completer.complete(null);
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      );

      timeoutTimer = Timer(_sttResponseTimeout, () {
        if (completed || heardAnyText) return;
        completed = true;
        completer.complete(null);
      });

      final result = await completer.future;
      return result;
    } catch (_) {
      return null;
    } finally {
      timeoutTimer?.cancel();
      await _speechRecognitionService.stopListening();

      _isListening = false;
      _isWorking = false;
      if (mounted) setState(() {});
    }
  }

  LanguageOption _fallbackLanguageForDevice() {
    final normalizedDevice = _deviceLocale.toLowerCase();

    for (final language in _supportedLanguages) {
      if (language.locale.toLowerCase().startsWith(normalizedDevice) ||
          language.locale.toLowerCase().startsWith('$normalizedDevice-') ||
          language.ttsLocale.toLowerCase().startsWith(normalizedDevice) ||
          language.ttsLocale.toLowerCase().startsWith('$normalizedDevice-')) {
        return language;
      }
    }

    for (final language in _supportedLanguages) {
      if (language.locale.toLowerCase().startsWith('en')) {
        return language;
      }
    }

    if (_supportedLanguages.isNotEmpty) {
      return _supportedLanguages.first;
    }

    return const LanguageOption(
      locale: 'en',
      displayName: 'English',
      ttsLocale: 'en-US',
    );
  }

  String? _normalizeName(String? rawText) {
    if (rawText == null) return null;
    final cleaned = rawText.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return null;

    if (cleaned.length > 40) {
      return cleaned.substring(0, 40);
    }

    return cleaned;
  }

  LanguageOption? _normalizeLanguage(String rawText) {
    final normalized = rawText.trim().toLowerCase();

    if (_supportedLanguages.isEmpty) {
      final fallback = LocaleUtils.parseTtsLanguages([
        'en-US',
        'fr-FR',
        'ar-SA',
      ]);
      _supportedLanguages = fallback;
    }

    for (final language in _supportedLanguages) {
      final displayMatch = language.displayName.toLowerCase();
      final localeMatch = language.locale.toLowerCase();
      final ttsMatch = language.ttsLocale.toLowerCase();

      if (displayMatch == normalized ||
          displayMatch.contains(normalized) ||
          normalized.contains(displayMatch) ||
          localeMatch.contains(normalized) ||
          normalized.contains(localeMatch) ||
          ttsMatch.contains(normalized) ||
          normalized.contains(ttsMatch)) {
        return language;
      }
    }

    return null;
  }

  @override
  void dispose() {
    _speechRecognitionService.stopListening();
    super.dispose();
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
                        Icons.record_voice_over_rounded,
                        size: 64,
                        color: AppColors.electricCyan,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ExcludeSemantics: this title/status text is a visual
                    // echo of what SpeechService is already speaking aloud
                    // (Voice #1). Without this, a TalkBack/VoiceOver user
                    // (Voice #2) would have it read out a second time,
                    // which is redundant at best and, since it was
                    // previously untranslated, confusing at worst. The
                    // guided flow here is fully audio-driven, so the visual
                    // text only needs to serve sighted/low-vision users
                    // glancing at the screen, translated like everything
                    // else — it doesn't need to also be screen-reader
                    // focusable.
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
                        _statusText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.crispWhite.withValues(alpha: 0.9),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isListening || _isWorking)
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
