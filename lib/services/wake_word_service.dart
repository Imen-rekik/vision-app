import 'package:flutter/foundation.dart';
import 'speech_recognition_service.dart';

class WakeWordService {
  final SpeechRecognitionService _speechRecognitionService;
  Function()? _onWakeWordDetected;
  bool _isDetecting = false;
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
    if (_isDetecting || !_isAppInForeground) return;

    _isDetecting = true;
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
          // If detection was interrupted by platform timeout but should still be active, restart safely
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
      },
    );
  }

  bool _containsWakeWord(String text) {
    return text.contains('hey vision') ||
        text.contains('hi vision') ||
        text.contains('hay vision') ||
        text.contains('hey vishon') ||
        text.contains('hey vizion') ||
        text == 'vision';
  }

  Future<void> stopDetection() async {
    _isDetecting = false;
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
    _speechRecognitionService.dispose();
  }
}
