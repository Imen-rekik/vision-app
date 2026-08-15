import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';

class SpeechRecognitionService {
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;

  // `speech_to_text` only lets you register onStatus/onError ONCE, via
  // initialize(). It does not accept them per-listen() call. So we keep a
  // single stable trampoline registered with the plugin, and repoint it at
  // whichever caller is currently listening. Without this, every consumer
  // of startListening(onStatus: ...) (WakeWordService, ConversationController)
  // silently never hears 'done'/'notListening' and their listen-loops stall.
  Function(String status)? _activeStatusCallback;
  Function(dynamic error)? _activeErrorCallback;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  Future<bool> init() async {
    if (_isAvailable) return true;
    try {
      _isAvailable = await _stt.initialize(
        onError: (SpeechRecognitionError error) {
          debugPrint(
            'SpeechRecognitionService error: ${error.errorMsg} (permanent: ${error.permanent})',
          );
          _isListening = false;
          _activeErrorCallback?.call(error);
        },
        onStatus: (String status) {
          debugPrint('SpeechRecognitionService status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
          _activeStatusCallback?.call(status);
        },
      );
    } catch (e) {
      debugPrint('SpeechRecognitionService init exception: $e');
      _isAvailable = false;
    }
    return _isAvailable;
  }

  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    Function(String status)? onStatus,
    Function(dynamic error)? onError,
    Duration? listenFor,
    Duration? pauseFor,
  }) async {
    if (!_isAvailable) {
      final initialized = await init();
      if (!initialized) {
        debugPrint('SpeechRecognitionService unavailable');
        return;
      }
    }

    if (_isListening) {
      await stopListening();
    }

    _isListening = true;
    _activeStatusCallback = onStatus;
    _activeErrorCallback = onError;

    try {
      final listenOptions = stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        listenFor: listenFor ?? const Duration(seconds: 30),
        pauseFor: pauseFor ?? const Duration(seconds: 5),
      );

      await _stt.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        listenOptions: listenOptions,
      );
    } catch (e) {
      debugPrint('SpeechRecognitionService listen exception: $e');
      _isListening = false;
      onError?.call(e);
    }
  }

  Future<void> stopListening() async {
    if (_isListening) {
      try {
        await _stt.stop();
      } catch (e) {
        debugPrint('SpeechRecognitionService stop error: $e');
      } finally {
        _isListening = false;
      }
    }
    // Detach so a caller that has since disposed (e.g. a screen popped
    // mid-listen) can't get a late status/error callback into a dead widget.
    _activeStatusCallback = null;
    _activeErrorCallback = null;
  }

  Future<void> cancel() async {
    if (_isListening) {
      try {
        await _stt.cancel();
      } catch (e) {
        debugPrint('SpeechRecognitionService cancel error: $e');
      } finally {
        _isListening = false;
      }
    }
    _activeStatusCallback = null;
    _activeErrorCallback = null;
  }

  void dispose() {
    _stt.stop();
    _isListening = false;
    _activeStatusCallback = null;
    _activeErrorCallback = null;
  }
}
