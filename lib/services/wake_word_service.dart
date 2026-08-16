import 'package:flutter/foundation.dart';
import 'speech_recognition_service.dart';

class WakeWordService {
  final SpeechRecognitionService _speechRecognitionService;
  Function()? _onWakeWordDetected;

  // Whether wake-word mode is *desired* — stays true across restarts,
  // toggled only by startDetection()/stopDetection(). This is what
  // isDetecting exposes and what onResult checks before matching.
  bool _isDetecting = false;

  // Whether a listen() call is *currently in-flight* right now. This is
  // what startDetection()'s re-entrancy guard should check — using
  // _isDetecting for this too was the bug: after a listen session ended
  // (timeout/no-match), _isDetecting was never reset, so the delayed
  // auto-restart's call to startDetection() always hit the guard and
  // silently did nothing, permanently ending wake-word detection after the
  // very first timeout.
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
          // This listen session has actually ended — clear the in-flight
          // flag so the next startDetection() call isn't blocked by its
          // own guard.
          _sessionListening = false;

          // If detection was interrupted by platform timeout but should
          // still be active, restart safely.
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
        // Errors (e.g. error_speech_timeout, error_no_match) also end the
        // in-flight session without necessarily firing onStatus 'done' —
        // clear the flag here too so a restart isn't blocked.
        _sessionListening = false;
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
