import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:gemini_live/gemini_live.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';
import '../../services/network_service.dart';
import '../../services/onboarding_service.dart';
import '../../utils/locale_utils.dart';
import '../../widgets/celestial_background.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';

enum VoiceActivityState {
  initializing(
    'Setting up...',
    Icons.hourglass_top_rounded,
    AppColors.topLightBlue,
  ),
  connecting('Connecting...', Icons.cloud_sync_rounded, AppColors.topLightBlue),
  gettingReady(
    'Getting ready...',
    Icons.psychology_rounded,
    Colors.amberAccent,
  ),
  speaking('Vision Speaking...', Icons.volume_up_rounded, Color(0xFFC77DFF)),
  listening('Listening...', Icons.mic_rounded, AppColors.electricCyan),
  processing('Thinking...', Icons.psychology_rounded, Colors.amberAccent),
  error('Connection Issue', Icons.error_outline_rounded, Colors.redAccent);

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

class _VoiceOnboardingScreenState extends State<VoiceOnboardingScreen>
    with WidgetsBindingObserver {
  static const String _liveTokenUrl =
      'https://vision-ai-relay.vercel.app/api/live-token';

  final OnboardingService _onboardingService = OnboardingService();
  final NetworkService _networkService = NetworkService();

  LiveSession? _liveSession;
  final AudioRecorder _liveRecorder = AudioRecorder();
  StreamSubscription<List<int>>? _liveMicSubscription;

  final FlutterSoundPlayer _livePlayer = FlutterSoundPlayer();
  bool _livePlayerReady = false;
  final List<Uint8List> _liveAudioQueue = [];
  bool _isFeedingLiveAudio = false;

  bool _onboardingCompletedSuccessfully = false;
  bool _isConnecting = false;
  bool _isMicActive = false;

  VoiceActivityState _activityState = VoiceActivityState.initializing;
  String _statusText = 'Setting things up for you...';
  String _titleText = AppStrings.voiceOnboardingScreenTitle;

  final Stopwatch _turnStopwatch = Stopwatch();
  int _turnBytesReceived = 0;
  Timer? _turnCompletionTimer;

  void _setActivityState(VoiceActivityState activity, {String? statusText}) {
    if (!mounted) return;
    setState(() {
      _activityState = activity;
      if (statusText != null) {
        _statusText = statusText;
      }
      if (activity == VoiceActivityState.error) {
        _titleText = 'Connection Issue';
      } else {
        _titleText = AppStrings.voiceOnboardingScreenTitle;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLiveDrivenOnboarding();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      debugPrint(
        'VoiceOnboardingScreen: App backgrounded. Cleaning up live resources...',
      );
      _cleanupLiveResources();
    } else if (state == AppLifecycleState.resumed) {
      if (!_onboardingCompletedSuccessfully &&
          mounted &&
          _activityState == VoiceActivityState.error) {
        _startLiveDrivenOnboarding();
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    _stopLiveMicStream();
    _setActivityState(VoiceActivityState.error, statusText: message);
  }

  Future<void> _startLiveDrivenOnboarding() async {
    if (_isConnecting) return;
    _isConnecting = true;

    await _cleanupLiveResources();

    if (!mounted) return;

    _setActivityState(
      VoiceActivityState.connecting,
      statusText: 'Connecting to Vision...',
    );

    final isOnline = await _networkService.hasRealInternetAccess();
    if (!isOnline) {
      _isConnecting = false;
      _showError(
        'You are offline. Please connect to the internet and tap Retry.',
      );
      return;
    }

    try {
      if (!_livePlayerReady) {
        await _livePlayer.openPlayer();
        await _livePlayer.startPlayerFromStream(
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 24000,
          bufferSize: 8192,
          interleaved: true,
        );
        _livePlayerReady = true;
      }

      final preferredLang = await _onboardingService.getPreferredLanguage();
      final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final deviceLangCode = deviceLocale.languageCode.trim().toLowerCase();
      final resolvedLangCode =
          (preferredLang != null && preferredLang.trim().isNotEmpty)
          ? preferredLang.trim().toLowerCase()
          : (deviceLangCode.isNotEmpty ? deviceLangCode : 'en');
      final resolvedLangName = LocaleUtils.getDisplayName(resolvedLangCode);

      final tokenResponse = await http
          .post(
            Uri.parse(_liveTokenUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'languageCode': resolvedLangCode,
              'languageName': resolvedLangName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (tokenResponse.statusCode != 200) {
        debugPrint(
          'VoiceOnboardingScreen: Token request failed (${tokenResponse.statusCode})',
        );
        _isConnecting = false;
        _showError(
          'Vision could not connect to Live AI. Please check your connection and tap Retry.',
        );
        return;
      }

      final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final token = tokenData['token'] as String;

      final genAI = GoogleGenAI(apiKey: token, apiVersion: 'v1alpha');

      _liveSession = await genAI.live
          .connect(
            LiveConnectParameters(
              model: 'gemini-3.1-flash-live-preview',
              config: GenerationConfig(responseModalities: [Modality.AUDIO]),
              callbacks: LiveCallbacks(
                onOpen: () {
                  debugPrint(
                    'VoiceOnboardingScreen: WebSocket connected ($resolvedLangName / $resolvedLangCode)',
                  );
                },
                onMessage: (LiveServerMessage message) {
                  if (!mounted) return;
                  _handleLiveMessage(message);
                },
                onError: (dynamic error, StackTrace? stackTrace) {
                  debugPrint('VoiceOnboardingScreen: Live API error: $error');
                  if (!_onboardingCompletedSuccessfully && mounted) {
                    _showError(
                      'Vision encountered a connection issue. Tap Retry to reconnect.',
                    );
                  }
                },
                onClose: (int? code, String? reason) {
                  debugPrint(
                    'VoiceOnboardingScreen: Live session closed (code: $code, reason: $reason)',
                  );
                  if (!_onboardingCompletedSuccessfully && mounted) {
                    _showError(
                      'Connection was closed. Tap Retry to reconnect.',
                    );
                  }
                },
              ),
            ),
          )
          .timeout(const Duration(seconds: 15));

      _isConnecting = false;

      debugPrint(
        'VoiceOnboardingScreen: Live session ready. Starting microphone stream...',
      );

      await _startLiveMicStream();
    } catch (e) {
      debugPrint('VoiceOnboardingScreen: Live setup failed: $e');
      _isConnecting = false;
      if (!_onboardingCompletedSuccessfully && mounted) {
        _showError(
          'Vision could not connect. Please check your connection and tap Retry.',
        );
      }
    }
  }

  void _handleLiveMessage(LiveServerMessage message) {
    if (message.data != null) {
      if (_isMicActive) {
        _stopLiveMicStream();
      }

      try {
        final bytes = base64Decode(message.data!);
        if (bytes.isNotEmpty) {
          if (!_turnStopwatch.isRunning) {
            _turnStopwatch.start();
          }
          _turnBytesReceived += bytes.length;

          _setActivityState(
            VoiceActivityState.speaking,
            statusText: 'Vision Speaking...',
          );

          _liveAudioQueue.add(bytes);
          _drainLiveAudioQueue();

          _turnCompletionTimer?.cancel();
          _turnCompletionTimer = null;
        }
      } catch (e) {
        debugPrint('VoiceOnboardingScreen: Failed to decode audio chunk: $e');
      }
    }

    if (message.serverContent?.turnComplete == true) {
      _scheduleListeningAfterPlaybackCompletes();
    }

    if (message.serverContent?.interrupted == true) {
      _turnCompletionTimer?.cancel();
      _turnCompletionTimer = null;
      _liveAudioQueue.clear();
      _turnStopwatch.reset();
      _turnBytesReceived = 0;
      if (!_onboardingCompletedSuccessfully) {
        _startLiveMicStream();
      }
    }

    if (message.toolCall != null) {
      _handleOnboardingToolCall(message.toolCall!);
    }
  }

  void _scheduleListeningAfterPlaybackCompletes() {
    _turnCompletionTimer?.cancel();

    final totalDurationMs = (_turnBytesReceived / 48).round();
    final elapsedMs = _turnStopwatch.elapsedMilliseconds;
    final remainingMs = max(0, totalDurationMs - elapsedMs);

    debugPrint(
      'VoiceOnboardingScreen: Turn complete. Total audio: ${totalDurationMs}ms, '
      'elapsed: ${elapsedMs}ms, remaining: ${remainingMs}ms',
    );

    _turnCompletionTimer = Timer(
      Duration(milliseconds: remainingMs + 150),
      () async {
        if (!mounted) return;

        _turnStopwatch.reset();
        _turnBytesReceived = 0;

        if (_onboardingCompletedSuccessfully) {
          return;
        }

        await _startLiveMicStream();
      },
    );
  }

  Future<void> _startLiveMicStream() async {
    if (_isMicActive || _onboardingCompletedSuccessfully || !mounted) return;

    try {
      final hasPermission = await _liveRecorder.hasPermission();
      if (!hasPermission) {
        debugPrint('VoiceOnboardingScreen: Microphone permission missing');
        _showError('Microphone permission is required for voice setup.');
        return;
      }

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

      _liveMicSubscription?.cancel();
      _liveMicSubscription = stream.listen(
        (chunk) {
          if (_liveSession != null && _isMicActive && chunk.isNotEmpty) {
            _liveSession?.sendAudio(Uint8List.fromList(chunk));
          }
        },
        onError: (e) {
          debugPrint('VoiceOnboardingScreen: Mic stream error: $e');
        },
      );

      _isMicActive = true;
      _setActivityState(
        VoiceActivityState.listening,
        statusText: 'Listening...',
      );

      debugPrint('VoiceOnboardingScreen: Microphone listening active');
    } catch (e) {
      debugPrint('VoiceOnboardingScreen: Failed to start microphone: $e');
      _showError('Could not start microphone. Tap Retry.');
    }
  }

  Future<void> _stopLiveMicStream() async {
    _isMicActive = false;
    await _liveMicSubscription?.cancel();
    _liveMicSubscription = null;

    try {
      if (await _liveRecorder.isRecording()) {
        await _liveRecorder.stop();
      }
    } catch (e) {
      debugPrint('VoiceOnboardingScreen: Recorder stop error (ignored): $e');
    }
  }

  Future<void> _drainLiveAudioQueue() async {
    if (_isFeedingLiveAudio) return;
    if (!_livePlayerReady) return;

    _isFeedingLiveAudio = true;

    try {
      while (_liveAudioQueue.isNotEmpty) {
        final chunk = _liveAudioQueue.removeAt(0);
        if (chunk.isEmpty) continue;

        try {
          await _livePlayer.feedUint8FromStream(chunk);
        } catch (e) {
          debugPrint('VoiceOnboardingScreen: Audio playback feed failed: $e');
        }
      }
    } finally {
      _isFeedingLiveAudio = false;
    }
  }

  Future<void> _handleOnboardingToolCall(LiveServerToolCall toolCall) async {
    for (final call in toolCall.functionCalls ?? const <FunctionCall>[]) {
      if (call.name != 'complete_onboarding' || call.id == null) {
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

      if (language != null && language.isNotEmpty) {
        await _onboardingService.setPreferredLanguage(language);
        await _onboardingService.setSelectedLanguage(language);
      }

      if (name != null && name.isNotEmpty) {
        await _onboardingService.setUserName(name);
      }

      await _onboardingService.markCompleted();
      await _onboardingService.setInteractiveOnboardingCompleted(true);

      final totalDurationMs = (_turnBytesReceived / 48).round();
      final elapsedMs = _turnStopwatch.elapsedMilliseconds;
      final remainingMs = max(0, totalDurationMs - elapsedMs);

      Future.delayed(Duration(milliseconds: remainingMs + 600), () async {
        if (!mounted) return;
        await _cleanupLiveResources();
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      });

      return;
    }
  }

  Future<void> _cleanupLiveResources() async {
    _turnCompletionTimer?.cancel();
    _turnCompletionTimer = null;

    await _stopLiveMicStream();

    _liveSession?.close();
    _liveSession = null;

    _liveAudioQueue.clear();
    _isFeedingLiveAudio = false;
    _turnStopwatch.reset();
    _turnBytesReceived = 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _turnCompletionTimer?.cancel();
    _liveMicSubscription?.cancel();
    _liveRecorder.dispose();
    _liveSession?.close();

    if (_livePlayerReady) {
      _livePlayer.stopPlayer();
      _livePlayer.closePlayer();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isErrorState = _activityState == VoiceActivityState.error;

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
                        color: AppColors.electricCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.electricCyan.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.electricCyan.withValues(
                              alpha: 0.2,
                            ),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.graphic_eq_rounded,
                            size: 16,
                            color: AppColors.electricCyan,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'AI Live Voice',
                            style: TextStyle(
                              color: AppColors.electricCyan,
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
                        _activityState.icon,
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

                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: isErrorState
                              ? Colors.redAccent.shade100
                              : AppColors.crispWhite.withValues(alpha: 0.9),
                          height: 1.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    if (isErrorState)
                      Semantics(
                        button: true,
                        label: 'Retry Connection',
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _startLiveDrivenOnboarding();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry Connection'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.electricCyan,
                            foregroundColor: AppColors.deepMidnight,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    else
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
