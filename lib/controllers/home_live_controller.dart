import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:gemini_live/gemini_live.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:record/record.dart';

import '../services/camera_capture_service.dart';
import '../widgets/voice_orb/orb_state.dart';

class HomeLiveController {
  static const String _homeLiveTokenUrl =
      'https://vision-ai-relay.vercel.app/api/home-live-token';

  static const int _darkThreshold = 60;
  static const int _brightThreshold = 90;

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

  bool _isMicActive = false;
  bool _isConnected = false;
  bool _flashOn = false;

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
      if (!_playerReady) {
        await _player.openPlayer();
        await _player.startPlayerFromStream(
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 24000,
          bufferSize: 8192,
          interleaved: true,
        );
        _playerReady = true;
      }

      final tokenResponse = await http
          .post(Uri.parse(_homeLiveTokenUrl))
          .timeout(const Duration(seconds: 10));

      if (tokenResponse.statusCode != 200) {
        _setOrbState(OrbState.error);
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

  Future<void> _startMicStream() async {
    try {
      final hasPermission = await _micRecorder.hasPermission();
      if (!hasPermission) return;

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
        if (_liveSession != null && _isMicActive && chunk.isNotEmpty) {
          _liveSession?.sendRealtimeInput(
            audio: Blob(
              mimeType: 'audio/pcm;rate=16000',
              data: base64Encode(chunk),
            ),
          );
        }
      });
    } catch (e) {
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
    } catch (e) {}
  }

  void _startFrameLoop() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _captureAndSendFrame();
    });
  }

  Future<void> _captureAndSendFrame() async {
    if (_liveSession == null || !_isConnected || _cameraController == null) {
      return;
    }

    var frame = await _cameraCaptureService.captureFrame(_cameraController);
    if (frame == null) return;

    final brightness = _averageBrightness(frame);

    if (brightness < _darkThreshold && !_flashOn) {
      await _setFlash(true);
      final relit = await _cameraCaptureService.captureFrame(_cameraController);
      if (relit != null) frame = relit;
    } else if (brightness > _brightThreshold && _flashOn) {
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
    } catch (e) {}
  }

  void _handleLiveMessage(LiveServerMessage message) {
    if (message.data != null) {
      if (_isMicActive) {
        _stopMicStream();
      }

      try {
        final bytes = base64Decode(message.data!);
        if (bytes.isNotEmpty) {
          if (!_turnStopwatch.isRunning) {
            _turnStopwatch.start();
          }
          _turnBytesReceived += bytes.length;

          _setOrbState(OrbState.speaking);

          _audioQueue.add(bytes);
          _drainAudioQueue();

          _turnCompletionTimer?.cancel();
          _turnCompletionTimer = null;
        }
      } catch (e) {}
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
      _startMicStream();
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
        if (_isConnected) {
          await _startMicStream();
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
        } catch (e) {}
      }
    } finally {
      _isFeedingAudio = false;
    }
  }

  void _handleToolCall(LiveServerToolCall toolCall) {
    for (final call in toolCall.functionCalls ?? const <FunctionCall>[]) {
      if (call.name != 'flag_obstacle' || call.id == null) continue;

      final args = call.args ?? const {};
      final urgency = (args['urgency'] as String? ?? 'low').toLowerCase();

      _liveSession?.sendFunctionResponse(
        id: call.id!,
        name: call.name!,
        response: {'result': 'success'},
      );

      _triggerHaptic(urgency);
    }
  }

  void _triggerHaptic(String urgency) {
    switch (urgency) {
      case 'high':
        HapticFeedback.heavyImpact();
        break;
      case 'medium':
        HapticFeedback.mediumImpact();
        break;
      default:
        HapticFeedback.lightImpact();
    }
  }

  Future<void> pause() async {
    _frameTimer?.cancel();
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
    _turnCompletionTimer?.cancel();
    await _stopMicStream();
    await _liveSession?.close();
    _liveSession = null;

    if (_playerReady) {
      try {
        await _player.stopPlayer();
      } catch (e) {}
      await _player.closePlayer();
    }

    await _micRecorder.dispose();

    if (_flashOn && _cameraController != null) {
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {}
    }
  }
}
