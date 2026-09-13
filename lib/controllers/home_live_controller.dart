import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:gemini_live/gemini_live.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:record/record.dart';
import 'package:vibration/vibration.dart';

import '../services/camera_capture_service.dart';
import '../services/onboarding_service.dart';
import '../services/speech_service.dart';
import '../utils/locale_utils.dart';
import '../widgets/voice_orb/orb_state.dart';

class HomeLiveController {
  static const String _homeLiveTokenUrl =
      'https://vision-ai-relay.vercel.app/api/home-live-token';

  final OnboardingService _onboardingService = OnboardingService();
  final SpeechService _speechService = SpeechService();
  static const int _darkThreshold = 30;
  static const int _brightThreshold = 70;
  static const Duration _flashToggleCooldown = Duration(seconds: 6);

  final CameraCaptureService _cameraCaptureService = CameraCaptureService();
  final AudioRecorder _micRecorder = AudioRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  LiveSession? _liveSession;
  CameraController? _cameraController;

  StreamSubscription<List<int>>? _micSubscription;
  Timer? _frameTimer;
  Timer? _turnCompletionTimer;
  final Stopwatch _turnStopwatch = Stopwatch();
  int _turnBytesReceived = 0;

  bool _playerReady = false;
  final List<Uint8List> _audioQueue = [];
  bool _isFeedingAudio = false;

  bool get isConnected => _isConnected;

  bool _isMicActive = false;
  bool _isConnected = false;
  bool _flashOn = false;
  DateTime? _lastFlashToggleTime;
  bool _isSpeaking = false;
  String? _activeSearchTarget;

  Timer? _checkInTimer;

  Function(OrbState)? _onOrbStateChanged;

  void setOnOrbStateChanged(Function(OrbState) callback) {
    _onOrbStateChanged = callback;
  }

  void _setOrbState(OrbState state) {
    _onOrbStateChanged?.call(state);
  }

  Future<void> start(CameraController cameraController) async {
    _cameraController = cameraController;
    _setOrbState(OrbState.thinking);

    try {
      await _ensurePlayerReady();

      String? preferredLang;
      try {
        preferredLang = await _onboardingService.getPreferredLanguage().timeout(
          const Duration(seconds: 3),
        );
      } catch (e) {
        preferredLang = null;
      }
      final deviceLangCode = WidgetsBinding
          .instance
          .platformDispatcher
          .locale
          .languageCode
          .trim()
          .toLowerCase();
      final resolvedLangCode =
          (preferredLang != null && preferredLang.trim().isNotEmpty)
          ? preferredLang.trim().toLowerCase()
          : (deviceLangCode.isNotEmpty ? deviceLangCode : 'en');
      final resolvedLangName = LocaleUtils.getDisplayName(resolvedLangCode);

      final tokenResponse = await http
          .post(
            Uri.parse(_homeLiveTokenUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'languageCode': resolvedLangCode,
              'languageName': resolvedLangName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (tokenResponse.statusCode != 200) {
        _setOrbState(OrbState.error);
        unawaited(
          _speechService.speak(
            "I couldn't connect. Please check your connection and try again.",
          ),
        );
        return;
      }

      final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final token = tokenData['token'] as String;

      final genAI = GoogleGenAI(apiKey: token, apiVersion: 'v1alpha');

      _liveSession = await genAI.live
          .connect(
            LiveConnectParameters(
              model: 'models/gemini-3.1-flash-live-preview',
              config: GenerationConfig(responseModalities: [Modality.AUDIO]),
              callbacks: LiveCallbacks(
                onOpen: () {},
                onMessage: (LiveServerMessage message) {
                  _handleLiveMessage(message);
                },
                onError: (dynamic error, StackTrace? stackTrace) {
                  _isConnected = false;
                  _setOrbState(OrbState.error);
                },
                onClose: (int? code, String? reason) {
                  _isConnected = false;
                  _setOrbState(OrbState.error);
                },
              ),
            ),
          )
          .timeout(const Duration(seconds: 15));

      _isConnected = true;
      await _startMicStream();
      _startFrameLoop();
    } catch (e) {
      _setOrbState(OrbState.error);
    }
  }

  Future<void> _ensurePlayerReady({bool isRetry = false}) async {
    if (_playerReady) return;
    try {
      await _player.openPlayer().timeout(const Duration(seconds: 5));
      await _player
          .startPlayerFromStream(
            codec: Codec.pcm16,
            numChannels: 1,
            sampleRate: 24000,
            bufferSize: 8192,
            interleaved: true,
          )
          .timeout(const Duration(seconds: 5));
      _playerReady = true;
    } catch (e) {
      if (!isRetry) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _ensurePlayerReady(isRetry: true);
        return;
      }
      rethrow;
    }
  }

  Future<void> _startMicStream({bool isRetry = false}) async {
    if (_isMicActive) return;
    try {
      final hasPermission = await _micRecorder.hasPermission();
      if (!hasPermission) {
        if (!isRetry) {
          await Future.delayed(const Duration(milliseconds: 500));
          await _startMicStream(isRetry: true);
          return;
        }
        _setOrbState(OrbState.error);
        return;
      }

      final stream = await _micRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _isMicActive = true;
      _setOrbState(OrbState.listening);

      _micSubscription?.cancel();
      _micSubscription = stream.listen((chunk) {
        if (_liveSession != null &&
            _isConnected &&
            !_isSpeaking &&
            chunk.isNotEmpty) {
          _liveSession?.sendRealtimeInput(
            audio: Blob(
              mimeType: 'audio/pcm;rate=16000',
              data: base64Encode(chunk),
            ),
          );
        }
      });
    } catch (e) {
      if (!isRetry) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _startMicStream(isRetry: true);
        return;
      }
      _setOrbState(OrbState.error);
    }
  }

  Future<void> _stopMicStream() async {
    _isMicActive = false;
    await _micSubscription?.cancel();
    _micSubscription = null;
    try {
      if (await _micRecorder.isRecording()) {
        await _micRecorder.stop();
      }
    } catch (e) {
      debugPrint('HomeLiveController: mic stop error (ignored): $e');
    }
  }

  void _startFrameLoop() {
    _frameTimer?.cancel();
    _checkInTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _captureSendFrameAndCheckIn();
    });
  }

  Future<void> _captureSendFrameAndCheckIn() async {
    await _captureAndSendFrame();
    _sendObstacleCheckIn();
  }

  void _sendObstacleCheckIn() {
    if (_liveSession == null || !_isConnected || _isSpeaking) return;

    final searchTarget = _activeSearchTarget;
    final text = searchTarget == null
        ? '(SAFETY CHECK: Analyze this camera frame. Only flag something '
              'genuinely close enough to hit or trip over within the next '
              '1-2 normal walking steps - as a rough guide, it should fill '
              'a large, close-up portion of the frame, not appear as a '
              'small or distant shape. A wall, door, or piece of furniture '
              'that is still several steps away is NOT near-term yet - do '
              'not flag it. If there truly is a near-term collision or '
              'fall risk (something about to be reached: a wall, door, '
              'furniture, step, curb, drop-off, or fast-approaching '
              'person/vehicle), call flag_obstacle with the current '
              'urgency, even if it is the same obstacle as last check - '
              'keep the urgency current every check so the vibration '
              'reflects how close it still is. Only speak out loud if this '
              'is a hazard you have not mentioned yet, or its urgency has '
              'clearly increased since your last report on it (noticeably '
              'closer than before); otherwise call flag_obstacle silently, '
              'without saying anything. Do NOT mention distant or off-path '
              'objects. Do NOT describe the general scene or say "all '
              'clear". If there is no near-term obstacle at all, stay '
              'fully silent and do not call flag_obstacle.)'
        : '(SAFETY CHECK during active search for "$searchTarget": Analyze '
              'this frame. First, apply the same near-term obstacle rules '
              'as always - only flag something genuinely close enough to '
              'hit or trip over within 1-2 steps, filling a large portion '
              'of the frame, not a distant background shape. Call '
              'flag_obstacle with the current urgency every check it is '
              'still present, but only speak about it if it is new or has '
              'clearly gotten more urgent since your last report. If no '
              'obstacle is in path: if '
              '"$searchTarget" is not yet visible, you may give short '
              'scanning guidance or stay silent. If it is visible but not '
              'yet reached, tell the user its location/direction and keep '
              'guiding them closer - do NOT call stop_object_search yet. '
              'Only call stop_object_search once the object is essentially '
              'within reach and you clearly confirm this to the user, or '
              'if the user asked to stop.)';

    _liveSession?.sendClientContent(
      turns: [
        Content(
          role: 'user',
          parts: [Part(text: text)],
        ),
      ],
      turnComplete: true,
    );
  }

  Future<void> _captureAndSendFrame() async {
    if (_liveSession == null || !_isConnected || _cameraController == null) {
      return;
    }

    var frame = await _cameraCaptureService.captureFrame(_cameraController);
    if (frame == null) return;

    final brightness = _averageBrightness(frame);
    final canToggleFlash =
        _lastFlashToggleTime == null ||
        DateTime.now().difference(_lastFlashToggleTime!) >=
            _flashToggleCooldown;

    if (brightness < _darkThreshold && !_flashOn && canToggleFlash) {
      await _setFlash(true);
      final relit = await _cameraCaptureService.captureFrame(_cameraController);
      if (relit != null) frame = relit;
    } else if (brightness > _brightThreshold && _flashOn && canToggleFlash) {
      await _setFlash(false);
    }

    _liveSession?.sendRealtimeInput(
      video: Blob(mimeType: 'image/jpeg', data: base64Encode(frame)),
    );
  }

  int _averageBrightness(Uint8List jpegBytes) {
    final image = img.decodeImage(jpegBytes);
    if (image == null) return 128;

    var total = 0.0;
    var count = 0;
    final stepX = (image.width / 20).ceil().clamp(1, image.width);
    final stepY = (image.height / 20).ceil().clamp(1, image.height);

    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        total += image.getPixel(x, y).luminance;
        count++;
      }
    }

    return count == 0 ? 128 : (total / count).round();
  }

  Future<void> _setFlash(bool on) async {
    if (_cameraController == null) return;
    try {
      await _cameraController!.setFlashMode(
        on ? FlashMode.torch : FlashMode.off,
      );
      _flashOn = on;
      _lastFlashToggleTime = DateTime.now();
    } catch (e) {
      debugPrint('HomeLiveController: flash mode error (ignored): $e');
    }
  }

  void _handleLiveMessage(LiveServerMessage message) {
    if (message.data != null) {
      try {
        final bytes = base64Decode(message.data!);
        if (bytes.isNotEmpty) {
          if (!_turnStopwatch.isRunning) {
            _turnStopwatch.start();
          }
          _turnBytesReceived += bytes.length;

          _isSpeaking = true;
          _setOrbState(OrbState.speaking);

          _audioQueue.add(bytes);
          _drainAudioQueue();

          _turnCompletionTimer?.cancel();
          _turnCompletionTimer = null;
        }
      } catch (e) {
        debugPrint('HomeLiveController: audio decode error (ignored): $e');
      }
    }

    if (message.serverContent?.turnComplete == true) {
      _scheduleListeningAfterPlaybackCompletes();
    }

    if (message.serverContent?.interrupted == true) {
      _turnCompletionTimer?.cancel();
      _turnCompletionTimer = null;
      _audioQueue.clear();
      _turnStopwatch.reset();
      _turnBytesReceived = 0;
      _isSpeaking = false;
      _setOrbState(OrbState.listening);
    }

    if (message.toolCall != null) {
      _handleToolCall(message.toolCall!);
    }
  }

  void _scheduleListeningAfterPlaybackCompletes() {
    _turnCompletionTimer?.cancel();

    final totalDurationMs = (_turnBytesReceived / 48).round();
    final elapsedMs = _turnStopwatch.elapsedMilliseconds;
    final remainingMs = max(0, totalDurationMs - elapsedMs);

    _turnCompletionTimer = Timer(
      Duration(milliseconds: remainingMs + 150),
      () async {
        _turnStopwatch.reset();
        _turnBytesReceived = 0;
        _isSpeaking = false;
        if (_isConnected) {
          _setOrbState(OrbState.listening);
        }
      },
    );
  }

  Future<void> _drainAudioQueue() async {
    if (_isFeedingAudio || !_playerReady) return;
    _isFeedingAudio = true;
    try {
      while (_audioQueue.isNotEmpty) {
        final chunk = _audioQueue.removeAt(0);
        if (chunk.isEmpty) continue;
        try {
          await _player.feedUint8FromStream(chunk);
        } catch (e) {
          debugPrint('HomeLiveController: audio feed error (ignored): $e');
        }
      }
    } finally {
      _isFeedingAudio = false;
    }
  }

  void _handleToolCall(LiveServerToolCall toolCall) {
    for (final call in toolCall.functionCalls ?? const <FunctionCall>[]) {
      if (call.id == null || call.name == null) continue;

      switch (call.name!) {
        case 'flag_obstacle':
          final args = call.args ?? const {};
          final urgency = (args['urgency'] as String? ?? 'low').toLowerCase();

          debugPrint(
            'HomeLiveController: flag_obstacle received, urgency=$urgency',
          );

          _liveSession?.sendFunctionResponse(
            id: call.id!,
            name: call.name!,
            response: {'result': 'success'},
          );

          _triggerHaptic(urgency);
          break;

        case 'start_object_search':
          final args = call.args ?? const {};
          final target = (args['objectDescription'] as String? ?? '').trim();

          debugPrint('HomeLiveController: start_object_search target=$target');

          _activeSearchTarget = target.isEmpty ? 'the object' : target;

          _liveSession?.sendFunctionResponse(
            id: call.id!,
            name: call.name!,
            response: {'result': 'success'},
          );
          break;

        case 'stop_object_search':
          debugPrint('HomeLiveController: stop_object_search');

          _activeSearchTarget = null;

          _liveSession?.sendFunctionResponse(
            id: call.id!,
            name: call.name!,
            response: {'result': 'success'},
          );
          break;
      }
    }
  }

  Future<void> _triggerHaptic(String urgency) async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;

    switch (urgency) {
      case 'high':
        Vibration.vibrate(duration: 600);
        break;
      case 'medium':
        Vibration.vibrate(duration: 300);
        break;
      default:
        Vibration.vibrate(duration: 150);
    }
  }

  Future<void> pause() async {
    _frameTimer?.cancel();
    _checkInTimer?.cancel();
    _activeSearchTarget = null;
    await _stopMicStream();
  }

  Future<void> resume() async {
    if (_isConnected) {
      await _startMicStream();
      _startFrameLoop();
    }
  }

  Future<void> dispose() async {
    _frameTimer?.cancel();
    _checkInTimer?.cancel();
    _turnCompletionTimer?.cancel();
    await _stopMicStream();
    await _liveSession?.close();
    _liveSession = null;

    if (_playerReady) {
      try {
        await _player.stopPlayer();
      } catch (e) {
        debugPrint('HomeLiveController: player stop error (ignored): $e');
      }
      await _player.closePlayer();
    }

    await _micRecorder.dispose();

    if (_flashOn && _cameraController != null) {
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('HomeLiveController: flash off error (ignored): $e');
      }
    }
  }
}
