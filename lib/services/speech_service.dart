import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;
  Function()? _onCompletionCallback;

  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    if (_isInitialized) return;
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      if (_onCompletionCallback != null) {
        _onCompletionCallback!();
      }
    });

    _flutterTts.setCancelHandler(() {
      _isSpeaking = false;
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
    });

    _isInitialized = true;
  }

  void setCompletionHandler(Function() onComplete) {
    _onCompletionCallback = onComplete;
  }

  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    _isSpeaking = true;
    await _flutterTts.speak(text);
  }

  Future<void> speakAndAwait(String text) async {
    if (!_isInitialized) await init();
    final completer = Completer<void>();
    final previousCallback = _onCompletionCallback;

    _onCompletionCallback = () {
      _isSpeaking = false;
      if (previousCallback != null) previousCallback();
      if (!completer.isCompleted) completer.complete();
    };

    _isSpeaking = true;
    final result = await _flutterTts.speak(text);

    if (result != 1 && !completer.isCompleted) {
      _isSpeaking = false;
      completer.complete();
    }

    await completer.future;
    _onCompletionCallback = previousCallback;
  }

  Future<void> stop() async {
    _isSpeaking = false;
    await _flutterTts.stop();
  }

  Future<void> setLanguage(String languageCode) async {
    if (!_isInitialized) await init();
    await _flutterTts.setLanguage(languageCode);
  }

  Future<List<dynamic>> getLanguages() async {
    if (!_isInitialized) await init();
    final languages = await _flutterTts.getLanguages;
    return languages is List ? languages : [];
  }

  void dispose() {
    _isSpeaking = false;
    _flutterTts.stop();
  }
}
