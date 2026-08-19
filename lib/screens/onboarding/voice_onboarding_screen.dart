import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:gemini_live/gemini_live.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/onboarding_prompts.dart';
import '../../models/conversation_message.dart';
import '../../models/language_option.dart';
import '../../services/ai_service.dart';
import '../../services/network_service.dart';
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
  static const String _liveTokenUrl =
      'https://vision-ai-relay.vercel.app/api/live-token';

  final SpeechService _speechService = SpeechService();
  final SpeechRecognitionService _speechRecognitionService =
      SpeechRecognitionService();
  final OnboardingService _onboardingService = OnboardingService();
  final AIService _aiService = AIService();

  bool _isListening = false;
  bool _isWorking = false;
  String _titleText = AppStrings.voiceOnboardingScreenTitle;
  String _statusText = AppStrings.voiceOnboardingStatusInitial;
  List<LanguageOption> _supportedLanguages = const [];
  String _deviceLocale = 'en';

  final TranslationService _translationService = TranslationService();

  LiveSession? _liveSession;
  final AudioRecorder _liveRecorder = AudioRecorder();
  StreamSubscription<List<int>>? _liveMicSubscription;
  final FlutterSoundPlayer _livePlayer = FlutterSoundPlayer();
  bool _livePlayerReady = false;
  final List<Uint8List> _liveAudioQueue = [];
  bool _isFeedingLiveAudio = false;
  bool _liveFallbackTriggered = false;
  bool _onboardingCompletedSuccessfully = false;
  final Stopwatch _liveTimingStopwatch = Stopwatch();
  bool _firstAudioChunkLogged = false;
  Timer? _firstResponseWatchdog;

  @override
  void initState() {
    super.initState();
    _initAndStart();
  }

  Future<void> _initAndStart() async {
    await _speechService.init();
    _speechService.speak('Setting things up for you, one moment.');

    await _startLiveDrivenOnboarding();
  }

  Future<void> _startLiveDrivenOnboarding() async {
    _isWorking = true;
    _liveFallbackTriggered = false;
    _firstAudioChunkLogged = false;
    _liveTimingStopwatch
      ..reset()
      ..start();
    if (mounted) setState(() {});

    if (!NetworkService().isOnline) {
      debugPrint('VoiceOnboardingScreen: offline, skipping live session');
      await _fallBackToAiDrivenOnboarding();
      return;
    }

    try {
      if (!_livePlayerReady) {
        debugPrint('TIMING: opening player at 0ms');
        await _livePlayer.openPlayer();
        await _livePlayer.startPlayerFromStream(
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 24000,
          bufferSize: 8192,
          interleaved: true,
        );
        _livePlayerReady = true;
        debugPrint(
          'TIMING: player ready at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
        );
      }

      debugPrint(
        'TIMING: requesting token at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
      );
      final tokenResponse = await http
          .post(Uri.parse(_liveTokenUrl))
          .timeout(const Duration(seconds: 8));
      debugPrint(
        'TIMING: got token response at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
      );

      if (tokenResponse.statusCode != 200) {
        debugPrint(
          'VoiceOnboardingScreen: token request failed '
          '(${tokenResponse.statusCode}), falling back',
        );
        await _fallBackToAiDrivenOnboarding();
        return;
      }

      final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final token = tokenData['token'] as String;

      final genAI = GoogleGenAI(apiKey: token, apiVersion: 'v1alpha');

      debugPrint(
        'TIMING: starting connect at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
      );

      _liveSession = await genAI.live
          .connect(
            LiveConnectParameters(
              model: 'gemini-3.1-flash-live-preview',

              config: GenerationConfig(responseModalities: [Modality.AUDIO]),
              systemInstruction: Content(
                parts: [
                  Part(text: OnboardingPrompts.liveOnboardingSystemPrompt),
                ],
              ),
              tools: [OnboardingPrompts.completeOnboardingTool],
              callbacks: LiveCallbacks(
                onOpen: () {
                  debugPrint(
                    'TIMING: connected (onOpen) at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
                  );
                  debugPrint(
                    'TIMING: sending greeting prompt to Gemini Live at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
                  );
                  _liveSession?.sendText(
                    'Please greet the user warmly as Vision, introduce yourself, and ask what language they would like to speak.',
                  );

                  _firstResponseWatchdog = Timer(const Duration(seconds: 8), () {
                    debugPrint(
                      'TIMING: no response from Gemini after 8s, falling back to AI turn-based onboarding',
                    );
                    _fallBackToAiDrivenOnboarding();
                  });
                },
                onMessage: (LiveServerMessage message) {
                  debugPrint(
                    'RAW MESSAGE at ${_liveTimingStopwatch.elapsedMilliseconds}ms: '
                    'data=${message.data != null} '
                    'toolCall=${message.toolCall != null} '
                    'text=${message.text} '
                    'serverContent=${message.serverContent} '
                    'turnComplete=${message.serverContent?.turnComplete}',
                  );

                  if (message.data != null) {
                    if (!_firstAudioChunkLogged) {
                      _firstAudioChunkLogged = true;
                      _firstResponseWatchdog?.cancel();
                      _speechService.stop();
                      debugPrint(
                        'TIMING: first audio chunk received at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
                      );
                      // Start mic stream now that Gemini is producing its opening speech turn
                      _startLiveMicStream();
                    }
                    final bytes = base64Decode(message.data!);
                    _liveAudioQueue.add(bytes);
                    _drainLiveAudioQueue();
                  }

                  if (message.toolCall != null) {
                    _handleOnboardingToolCall(message.toolCall!);
                  }
                },
                onError: (e, s) {
                  debugPrint('VoiceOnboardingScreen: Live API error: $e');
                  _fallBackToAiDrivenOnboarding();
                },
                onClose: (code, reason) {
                  debugPrint('VoiceOnboardingScreen: Live API closed: $reason');
                  if (!_onboardingCompletedSuccessfully && mounted) {
                    _fallBackToAiDrivenOnboarding();
                  }
                },
              ),
            ),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('VoiceOnboardingScreen: Live onboarding setup failed: $e');
      await _fallBackToAiDrivenOnboarding();
    }
  }

  Future<void> _startLiveMicStream() async {
    try {
      final hasPermission = await _liveRecorder.hasPermission();

      if (!hasPermission) {
        await _fallBackToAiDrivenOnboarding();
        return;
      }

      debugPrint(
        'TIMING: starting mic stream at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
      );
      final stream = await _liveRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            audioManagerMode: AudioManagerMode.modeInCommunication,
          ),
        ),
      );
      debugPrint(
        'TIMING: mic stream ready at ${_liveTimingStopwatch.elapsedMilliseconds}ms',
      );

      _liveMicSubscription = stream.listen((chunk) {
        _liveSession?.sendAudio(chunk);
      });
    } catch (e) {
      debugPrint('VoiceOnboardingScreen: mic stream failed: $e');
      await _fallBackToAiDrivenOnboarding();
    }
  }

  Future<void> _drainLiveAudioQueue() async {
    if (_isFeedingLiveAudio) return;
    _isFeedingLiveAudio = true;
    while (_liveAudioQueue.isNotEmpty) {
      final chunk = _liveAudioQueue.removeAt(0);
      await _livePlayer.feedUint8FromStream(chunk);
    }
    _isFeedingLiveAudio = false;
  }

  Future<void> _handleOnboardingToolCall(LiveServerToolCall toolCall) async {
    for (final call in toolCall.functionCalls ?? const <FunctionCall>[]) {
      if (call.name != 'complete_onboarding') continue;
      if (call.id == null) continue;

      final args = call.args ?? const {};
      final language = args['language'] as String?;
      final name = args['name'] as String?;

      _liveSession?.sendFunctionResponse(
        id: call.id!,
        name: call.name!,
        response: {'result': 'success'},
      );

      _onboardingCompletedSuccessfully = true;
      await _stopLiveSession();

      if (language != null) {
        await _onboardingService.setPreferredLanguage(language);
        await _onboardingService.setSelectedLanguage(language);
      }

      if (name != null) {
        await _onboardingService.setUserName(name);
      }

      await _onboardingService.markCompleted();
      await _onboardingService.setInteractiveOnboardingCompleted(true);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }
  }

  Future<void> _stopLiveSession() async {
    _firstResponseWatchdog?.cancel();
    _firstResponseWatchdog = null;
    await _liveMicSubscription?.cancel();
    _liveMicSubscription = null;
    try {
      await _liveRecorder.stop();
    } catch (e) {
      debugPrint('VoiceOnboardingScreen: recorder stop error (ignored): $e');
    }
    _liveSession?.close();
    _liveSession = null;

    if (_livePlayerReady) {
      try {
        await _livePlayer.stopPlayer();
      } catch (e) {
        debugPrint('VoiceOnboardingScreen: player stop error (ignored): $e');
      }
      _livePlayerReady = false;
    }
  }

  Future<void> _fallBackToAiDrivenOnboarding() async {
    if (_liveFallbackTriggered) return;
    _liveFallbackTriggered = true;

    await _stopLiveSession();
    await _startAiDrivenOnboarding();
  }

  Future<void> _startAiDrivenOnboarding() async {
    _isWorking = true;
    if (mounted) setState(() {});

    final List<ConversationMessage> onboardingHistory = [];
    String userUtterance = '';
    String? collectedLanguage;
    String? collectedName;

    while (true) {
      final result = await _aiService.runOnboardingTurn(
        userUtterance,
        onboardingHistory,
      );

      if (result == null) {
        debugPrint(
          'VoiceOnboardingScreen: AI-driven onboarding failed, '
          'falling back to scripted flow.',
        );
        await _startFlow();
        return;
      }

      onboardingHistory.add(
        ConversationMessage(
          role: MessageRole.assistant,
          text: result.spokenText,
        ),
      );

      if (result.collectedLanguage != null) {
        collectedLanguage = result.collectedLanguage;
        await _speechService.setLanguage(collectedLanguage!);
      }

      if (result.collectedName != null) {
        collectedName = result.collectedName;
      }

      await _speechService.speakAndAwait(result.spokenText);

      if (result.onboardingComplete) {
        if (collectedLanguage != null) {
          await _onboardingService.setPreferredLanguage(collectedLanguage);
          await _onboardingService.setSelectedLanguage(collectedLanguage);
        }

        if (collectedName != null) {
          await _onboardingService.setUserName(collectedName);
        }

        await _onboardingService.markCompleted();
        await _onboardingService.setInteractiveOnboardingCompleted(true);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        return;
      }

      final heard = await _listenForText(
        listeningStatus: AppStrings.voiceOnboardingStatusListeningLanguage,
      );

      userUtterance = (heard != null && heard.trim().isNotEmpty)
          ? heard
          : '(the user did not say anything)';

      if (heard != null && heard.trim().isNotEmpty) {
        onboardingHistory.add(
          ConversationMessage(role: MessageRole.user, text: heard),
        );
      }
    }
  }

  Future<void> _speak(String englishText) async {
    final translated = await _translationService.translate(englishText);
    await _speechService.speakAndAwait(translated);
  }

  Future<void> _refreshOnScreenText() async {
    _titleText = await _translationService.translate(
      AppStrings.voiceOnboardingScreenTitle,
    );
    _statusText = await _translationService.translate(_currentStatusKey);

    if (mounted) setState(() {});
  }

  String _currentStatusKey = AppStrings.voiceOnboardingStatusInitial;

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

    try {
      await _translationService.init(initialLang);
    } catch (_) {}

    await _refreshOnScreenText();

    await _speak(AppStrings.voiceOnboardingGreeting);

    final selectedLanguage = await _askForPreferredLanguage();
    final selectedLocale = selectedLanguage.locale;

    await _onboardingService.setPreferredLanguage(selectedLocale);
    await _onboardingService.setSelectedLanguage(selectedLocale);
    await _speechService.setLanguage(selectedLanguage.ttsLocale);

    try {
      await _translationService.init(selectedLocale);
    } catch (_) {}

    await _refreshOnScreenText();

    final userName = await _askForName();
    await _onboardingService.setUserName(userName);

    final chosenLanguageName = selectedLanguage.displayName;

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
    _firstResponseWatchdog?.cancel();
    _liveMicSubscription?.cancel();
    _liveRecorder.dispose();
    _liveSession?.close();
    if (_livePlayerReady) {
      _livePlayer.stopPlayer();
    }
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
