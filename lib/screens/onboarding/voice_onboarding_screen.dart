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

enum OnboardingVoiceMode {
  aiLive('AI Live Voice', Icons.graphic_eq_rounded, AppColors.electricCyan),
  aiTurnBased('AI Assistant Voice', Icons.smart_toy_rounded, Color(0xFF9D4EDD)),
  scripted(
    'Scripted Voice',
    Icons.record_voice_over_rounded,
    Colors.orangeAccent,
  );

  final String label;
  final IconData icon;
  final Color color;

  const OnboardingVoiceMode(this.label, this.icon, this.color);
}

enum VoiceActivityState {
  idle('Ready', Icons.radio_button_checked_rounded, Colors.grey),
  thinking('Thinking...', Icons.psychology_rounded, Colors.amberAccent),
  speaking('Speaking...', Icons.volume_up_rounded, Color(0xFFC77DFF)),
  listening('Listening...', Icons.mic_rounded, AppColors.electricCyan);

  final String label;
  final IconData icon;
  final Color color;

  const VoiceActivityState(this.label, this.icon, this.color);
}

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

  final TranslationService _translationService = TranslationService();

  bool _isListening = false;
  bool _isWorking = false;

  String _titleText = AppStrings.voiceOnboardingScreenTitle;

  String _statusText = AppStrings.voiceOnboardingStatusInitial;

  String _currentStatusKey = AppStrings.voiceOnboardingStatusInitial;

  List<LanguageOption> _supportedLanguages = const [];

  String _deviceLocale = 'en';

  OnboardingVoiceMode _currentMode = OnboardingVoiceMode.aiLive;

  VoiceActivityState _activityState = VoiceActivityState.idle;

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

  bool _initialGeminiGreetingCompleted = false;

  bool _isStartingMic = false;

  void _setActivityState(VoiceActivityState activity, {String? statusText}) {
    if (!mounted) return;

    setState(() {
      _activityState = activity;

      if (statusText != null) {
        _statusText = statusText;
      }
    });
  }

  void _setMode(OnboardingVoiceMode mode) {
    if (!mounted) return;

    setState(() {
      _currentMode = mode;
    });
  }

  void _setLiveStatus(String text) {
    if (!mounted) return;

    setState(() {
      _statusText = text;
    });
  }

  @override
  void initState() {
    super.initState();

    _initAndStart();
  }

  Future<void> _initAndStart() async {
    await _speechService.init();

    if (!mounted) return;

    _setMode(OnboardingVoiceMode.aiLive);

    _setActivityState(
      VoiceActivityState.speaking,
      statusText: 'Setting things up for you...',
    );

    await _speechService.speakAndAwait(
      'Setting things up for you, one moment.',
    );

    if (!mounted) return;

    await _startLiveDrivenOnboarding();
  }

  Future<void> _startLiveDrivenOnboarding() async {
    _setMode(OnboardingVoiceMode.aiLive);

    _isWorking = true;

    _liveFallbackTriggered = false;

    _firstAudioChunkLogged = false;

    _initialGeminiGreetingCompleted = false;

    _isStartingMic = false;

    _liveTimingStopwatch
      ..reset()
      ..start();

    _setActivityState(
      VoiceActivityState.thinking,
      statusText: 'Connecting to Vision...',
    );

    if (!NetworkService().isOnline) {
      debugPrint(
        'VoiceOnboardingScreen: '
        'offline, skipping Live session',
      );

      await _fallBackToAiDrivenOnboarding();
      return;
    }

    try {
      if (!_livePlayerReady) {
        debugPrint('TIMING: opening player');

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
          'TIMING: player ready at '
          '${_liveTimingStopwatch.elapsedMilliseconds}ms',
        );
      }

      debugPrint('TIMING: requesting token');

      final tokenResponse = await http
          .post(Uri.parse(_liveTokenUrl))
          .timeout(const Duration(seconds: 8));

      debugPrint('TIMING: token response received');

      if (tokenResponse.statusCode != 200) {
        debugPrint(
          'VoiceOnboardingScreen: '
          'token request failed '
          '(${tokenResponse.statusCode})',
        );

        await _fallBackToAiDrivenOnboarding();
        return;
      }

      final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;

      final token = tokenData['token'] as String;

      final genAI = GoogleGenAI(apiKey: token, apiVersion: 'v1alpha');

      debugPrint('TIMING: connecting to Gemini Live');

      _liveSession = await genAI.live
          .connect(
            LiveConnectParameters(
              model: 'gemini-2.0-flash-realtime-exp',

              config: GenerationConfig(responseModalities: [Modality.AUDIO]),

              systemInstruction: Content(
                parts: [
                  Part(text: OnboardingPrompts.liveOnboardingSystemPrompt),
                ],
              ),

              tools: [OnboardingPrompts.completeOnboardingTool],

              callbacks: LiveCallbacks(
                onOpen: () {
                  debugPrint('LIVE: WebSocket connected');

                  _setActivityState(
                    VoiceActivityState.thinking,
                    statusText: 'Connected. Getting ready...',
                  );

                  _firstResponseWatchdog = Timer(
                    const Duration(seconds: 20),
                    () {
                      if (!_firstAudioChunkLogged && mounted) {
                        debugPrint(
                          'LIVE: Gemini did not '
                          'produce its first response.',
                        );

                        _fallBackToAiDrivenOnboarding();
                      }
                    },
                  );

                  debugPrint(
                    'LIVE: asking Gemini to begin '
                    'the onboarding conversation',
                  );

                  _liveSession?.sendText(
                    'Begin the onboarding conversation now. '
                    'Speak first. Do not wait for the user '
                    'to say anything.',
                  );
                },

                onMessage: (LiveServerMessage message) async {
                  if (message.data != null) {
                    if (!_firstAudioChunkLogged) {
                      _firstAudioChunkLogged = true;

                      _firstResponseWatchdog?.cancel();

                      debugPrint(
                        'LIVE: first Gemini audio '
                        'chunk received',
                      );
                    }

                    _setActivityState(
                      VoiceActivityState.speaking,
                      statusText: 'AI Speaking...',
                    );

                    try {
                      final bytes = base64Decode(message.data!);

                      _liveAudioQueue.add(bytes);

                      await _drainLiveAudioQueue();
                    } catch (e) {
                      debugPrint(
                        'LIVE: audio decode/playback '
                        'error: $e',
                      );
                    }
                  }

                  if (message.serverContent?.turnComplete == true) {
                    debugPrint('LIVE: Gemini turn completed');

                    if (!_initialGeminiGreetingCompleted) {
                      _initialGeminiGreetingCompleted = true;

                      debugPrint(
                        'LIVE: initial greeting completed. '
                        'Starting microphone now.',
                      );
                    }

                    await _startLiveMicStream();
                  }

                  if (message.toolCall != null) {
                    await _handleOnboardingToolCall(message.toolCall!);
                  }
                },

                onError: (e, s) {
                  debugPrint(
                    'VoiceOnboardingScreen: '
                    'Live API error: $e',
                  );

                  _setLiveStatus('Having trouble connecting...');

                  _fallBackToAiDrivenOnboarding();
                },

                onClose: (code, reason) {
                  debugPrint(
                    'LIVE: connection closed. '
                    'code=$code reason=$reason',
                  );

                  if (!_onboardingCompletedSuccessfully && mounted) {
                    _fallBackToAiDrivenOnboarding();
                  }
                },
              ),
            ),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint(
        'VoiceOnboardingScreen: '
        'Live onboarding setup failed: $e',
      );

      await _fallBackToAiDrivenOnboarding();
    }
  }

  Future<void> _startLiveMicStream() async {
    if (_isStartingMic) return;

    if (_liveMicSubscription != null) {
      debugPrint('LIVE MIC: already listening');

      _setActivityState(
        VoiceActivityState.listening,
        statusText: 'Listening...',
      );

      return;
    }

    _isStartingMic = true;

    try {
      final hasPermission = await _liveRecorder.hasPermission();

      if (!hasPermission) {
        debugPrint(
          'LIVE MIC: microphone permission '
          'not available',
        );

        await _fallBackToAiDrivenOnboarding();
        return;
      }

      debugPrint('LIVE MIC: starting microphone');

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

      _liveMicSubscription = stream.listen((chunk) {
        _liveSession?.sendAudio(chunk);
      });

      _setActivityState(
        VoiceActivityState.listening,
        statusText: 'Listening...',
      );

      debugPrint('LIVE MIC: microphone is now active');
    } catch (e) {
      debugPrint(
        'VoiceOnboardingScreen: '
        'mic stream failed: $e',
      );

      await _fallBackToAiDrivenOnboarding();
    } finally {
      _isStartingMic = false;
    }
  }

  Future<void> _stopLiveMicStream() async {
    if (_liveMicSubscription == null) {
      return;
    }

    debugPrint('LIVE MIC: stopping microphone');

    await _liveMicSubscription?.cancel();

    _liveMicSubscription = null;

    try {
      await _liveRecorder.stop();
    } catch (e) {
      debugPrint('LIVE MIC: stop error ignored: $e');
    }
  }

  Future<void> _drainLiveAudioQueue() async {
    if (_isFeedingLiveAudio) {
      return;
    }

    if (!_livePlayerReady) {
      return;
    }

    _isFeedingLiveAudio = true;

    try {
      while (_liveAudioQueue.isNotEmpty) {
        final chunk = _liveAudioQueue.removeAt(0);

        if (chunk.isEmpty) {
          continue;
        }

        try {
          await _livePlayer.feedUint8FromStream(chunk);
        } catch (e) {
          debugPrint('LIVE AUDIO: playback error: $e');
        }
      }
    } finally {
      _isFeedingLiveAudio = false;
    }
  }

  Future<void> _handleOnboardingToolCall(LiveServerToolCall toolCall) async {
    for (final call in toolCall.functionCalls ?? const <FunctionCall>[]) {
      if (call.name != 'complete_onboarding') {
        continue;
      }

      if (call.id == null) {
        continue;
      }

      final args = call.args ?? const {};

      final language = args['language'] as String?;

      final name = args['name'] as String?;

      _liveSession?.sendFunctionResponse(
        id: call.id!,
        name: call.name!,
        response: {'result': 'success'},
      );

      _onboardingCompletedSuccessfully = true;

      _setActivityState(VoiceActivityState.speaking, statusText: 'All set!');

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

    await _stopLiveMicStream();

    _liveSession?.close();

    _liveSession = null;

    _liveAudioQueue.clear();

    _isFeedingLiveAudio = false;

    if (_livePlayerReady) {
      try {
        await _livePlayer.stopPlayer();
      } catch (e) {
        debugPrint(
          'VoiceOnboardingScreen: '
          'player stop error ignored: $e',
        );
      }

      _livePlayerReady = false;
    }
  }

  Future<void> _fallBackToAiDrivenOnboarding() async {
    if (_liveFallbackTriggered) {
      return;
    }

    _liveFallbackTriggered = true;

    await _stopLiveSession();

    await _startAiDrivenOnboarding();
  }

  Future<void> _startAiDrivenOnboarding() async {
    _setMode(OnboardingVoiceMode.aiTurnBased);

    _isWorking = true;

    if (mounted) {
      setState(() {});
    }

    final List<ConversationMessage> onboardingHistory = [];

    String userUtterance = '';

    String? collectedLanguage;

    String? collectedName;

    while (true) {
      _setActivityState(
        VoiceActivityState.thinking,
        statusText: 'AI Thinking...',
      );

      final result = await _aiService.runOnboardingTurn(
        userUtterance,
        onboardingHistory,
      );

      if (result == null) {
        debugPrint(
          'VoiceOnboardingScreen: '
          'AI-driven onboarding failed, '
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

      _setActivityState(
        VoiceActivityState.speaking,
        statusText: 'AI Speaking...',
      );

      await _speechService.speakAndAwait(result.spokenText);

      if (result.onboardingComplete) {
        if (collectedLanguage != null) {
          await _onboardingService.setPreferredLanguage(collectedLanguage!);

          await _onboardingService.setSelectedLanguage(collectedLanguage!);
        }

        if (collectedName != null) {
          await _onboardingService.setUserName(collectedName!);
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
    _setActivityState(VoiceActivityState.speaking);

    final translated = await _translationService.translate(englishText);

    await _speechService.speakAndAwait(translated);
  }

  Future<void> _refreshOnScreenText() async {
    _titleText = await _translationService.translate(
      AppStrings.voiceOnboardingScreenTitle,
    );

    _statusText = await _translationService.translate(_currentStatusKey);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setStatus(String statusKey) async {
    _currentStatusKey = statusKey;

    _statusText = await _translationService.translate(statusKey);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startFlow() async {
    _setMode(OnboardingVoiceMode.scripted);

    _isWorking = true;

    if (mounted) {
      setState(() {});
    }

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
        '$part1'
        '$userName'
        '$part2'
        '$chosenLanguageName'
        '$part3'
        '${AppStrings.wakeWordPhrase}'
        '$part4'
        '${AppStrings.stopWordPhrase}'
        '$part5';

    _setActivityState(VoiceActivityState.speaking);

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

    await _speechService.speakAndAwait(
      '$prefix'
      '${fallback.displayName}'
      '$suffix',
    );

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

    await _speechService.speakAndAwait(
      '$prefix'
      '$_defaultGuestName'
      '$suffix',
    );

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

    _setActivityState(VoiceActivityState.listening);

    final isReady = await _speechRecognitionService.init();

    if (!isReady) {
      _isListening = false;

      _isWorking = false;

      _setActivityState(VoiceActivityState.idle);

      if (mounted) {
        setState(() {});
      }

      return null;
    }

    Timer? timeoutTimer;

    try {
      await _speechRecognitionService.startListening(
        onResult: (String text, bool isFinal) {
          if (completed) {
            return;
          }

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
          if (completed) {
            return;
          }

          if (status == 'done' || status == 'notListening') {
            completed = true;

            completer.complete(lastHeardText.isEmpty ? null : lastHeardText);
          }
        },
        onError: (dynamic error) {
          if (completed) {
            return;
          }

          completed = true;

          completer.complete(null);
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      );

      timeoutTimer = Timer(_sttResponseTimeout, () {
        if (completed || heardAnyText) {
          return;
        }

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

      _setActivityState(VoiceActivityState.idle);

      if (mounted) {
        setState(() {});
      }
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
    if (rawText == null) {
      return null;
    }

    final cleaned = rawText.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (cleaned.isEmpty) {
      return null;
    }

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
                  vertical: 36,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _currentMode.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _currentMode.color.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _currentMode.color.withValues(alpha: 0.2),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _currentMode.icon,
                            size: 16,
                            color: _currentMode.color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _currentMode.label,
                            style: TextStyle(
                              color: _currentMode.color,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _activityState.color.withValues(alpha: 0.15),
                        border: Border.all(
                          color: _activityState.color.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _activityState.color.withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _activityState == VoiceActivityState.idle
                            ? Icons.record_voice_over_rounded
                            : _activityState.icon,
                        size: 64,
                        color: _activityState.color,
                      ),
                    ),

                    const SizedBox(height: 20),

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

                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _activityState.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _activityState.color.withValues(alpha: 0.7),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _activityState.icon,
                            size: 18,
                            color: _activityState.color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _activityState.label.toUpperCase(),
                            style: TextStyle(
                              color: _activityState.color,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
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

                    const SizedBox(height: 28),

                    if (_isListening || _isWorking)
                      ExcludeSemantics(
                        child: CircularProgressIndicator(
                          color: _activityState.color,
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
