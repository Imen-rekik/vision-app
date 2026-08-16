import 'package:flutter/foundation.dart';
import 'speech_recognition_service.dart';

class WakeWordService {
  final SpeechRecognitionService _speechRecognitionService;
  Function()? _onWakeWordDetected;

  bool _isDetecting = false;

  bool _sessionListening = false;

  bool _isAppInForeground = true;

  WakeWordService({SpeechRecognitionService? speechRecognitionService})
    : _speechRecognitionService =
          speechRecognitionService ?? SpeechRecognitionService();

  bool get isDetecting => _isDetecting;
  bool get isAppInForeground => _isAppInForeground;

  void setOnWakeWordDetected(Function() callback) {
    _onWakeWordDetected = callback;
  }

  Future<void> startDetection() async {
    if (_sessionListening || !_isAppInForeground) return;

    _isDetecting = true;
    _sessionListening = true;
    debugPrint('WakeWordService: starting detection for "Hey Vision"...');

    await _speechRecognitionService.startListening(
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      onResult: (String text, bool isFinal) {
        if (!_isDetecting) return;

        final normalized = text.toLowerCase().trim();
        debugPrint('WakeWordService heard: "$normalized"');

        if (_containsWakeWord(normalized)) {
          debugPrint('WakeWordService: WAKE WORD DETECTED!');
          stopDetection();
          if (_onWakeWordDetected != null) {
            _onWakeWordDetected!();
          }
        }
      },
      onStatus: (String status) {
        if (status == 'done' || status == 'notListening') {
          _sessionListening = false;

          if (_isDetecting && _isAppInForeground) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (_isDetecting && _isAppInForeground) {
                startDetection();
              }
            });
          }
        }
      },
      onError: (dynamic error) {
        debugPrint('WakeWordService error: $error');
        _sessionListening = false;
      },
    );
  }

  static final RegExp _wakeWordPattern = RegExp(
    r'\b(hey|hi|hay|ay|a)?\s*(vizio|vizo|vishon|vizion|vision)\w*\b',
  );

  bool _containsWakeWord(String text) {
    return _wakeWordPattern.hasMatch(text);
  }

  Future<void> stopDetection() async {
    _isDetecting = false;
    _sessionListening = false;
    await _speechRecognitionService.stopListening();
    debugPrint('WakeWordService: stopped detection.');
  }

  void pauseForBackground() {
    debugPrint('WakeWordService: paused due to background state.');
    _isAppInForeground = false;
    stopDetection();
  }

  void resumeForForeground() {
    debugPrint('WakeWordService: resumed due to foreground state.');
    _isAppInForeground = true;
  }

  void dispose() {
    _isDetecting = false;
    _sessionListening = false;
    _speechRecognitionService.dispose();
  }
}
