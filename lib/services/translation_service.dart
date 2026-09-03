import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'network_service.dart';

class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  OnDeviceTranslator? _translator;
  TranslateLanguage _targetLanguage = TranslateLanguage.english;
  String _currentLocaleCode = 'en';

  final Map<String, String> _cache = {};
  bool _isDownloading = false;
  bool _needsRetry = false;
  bool _reconnectListenerRegistered = false;

  TranslateLanguage get targetLanguage => _targetLanguage;
  String get currentLocaleCode => _currentLocaleCode;
  bool get isDownloading => _isDownloading;
  bool get needsRetry => _needsRetry;

  TranslateLanguage resolveLanguage(String localeCode) {
    if (localeCode.isEmpty) return TranslateLanguage.english;
    final cleanCode = localeCode
        .replaceAll('_', '-')
        .split('-')
        .first
        .toLowerCase();
    for (final lang in TranslateLanguage.values) {
      if (lang.bcpCode == cleanCode) {
        return lang;
      }
    }
    return TranslateLanguage.english;
  }

  bool isEnglish(String localeCode) {
    return resolveLanguage(localeCode) == TranslateLanguage.english;
  }

  Future<bool> init(String localeCode) async {
    _currentLocaleCode = localeCode;
    _targetLanguage = resolveLanguage(localeCode);

    if (!_reconnectListenerRegistered) {
      _reconnectListenerRegistered = true;
      NetworkService().addOnReconnectedCallback(() {
        if (_needsRetry) {
          debugPrint(
            'TranslationService: Network restored. Retrying background model download...',
          );
          init(_currentLocaleCode);
        }
      });
    }

    if (_targetLanguage == TranslateLanguage.english) {
      _needsRetry = false;
      _isDownloading = false;
      _closeTranslator();
      return true;
    }

    final isTargetDownloaded = await _modelManager.isModelDownloaded(
      _targetLanguage.bcpCode,
    );

    if (isTargetDownloaded) {
      _needsRetry = false;
      _createTranslator();
      return true;
    }

    if (!NetworkService().isOnline) {
      debugPrint(
        'TranslationService: Target model ${_targetLanguage.bcpCode} not downloaded & device is OFFLINE.',
      );
      _needsRetry = true;
      _isDownloading = false;
      return false;
    }

    _isDownloading = true;
    try {
      debugPrint(
        'TranslationService: Downloading ML Kit model for ${_targetLanguage.bcpCode}...',
      );
      final downloaded = await _modelManager.downloadModel(
        _targetLanguage.bcpCode,
      );

      _isDownloading = false;

      if (downloaded) {
        _needsRetry = false;
        _createTranslator();
        return true;
      } else {
        _needsRetry = true;
        return false;
      }
    } catch (e) {
      debugPrint('TranslationService: Model download exception: $e');
      _isDownloading = false;
      _needsRetry = true;
      return false;
    }
  }

  void _createTranslator() {
    _closeTranslator();
    _translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: _targetLanguage,
    );
  }

  void _closeTranslator() {
    _translator?.close();
    _translator = null;
  }

  Future<String> translate(String englishText) async {
    if (englishText.isEmpty) return englishText;
    if (_targetLanguage == TranslateLanguage.english) return englishText;

    if (_cache.containsKey(englishText)) {
      return _cache[englishText]!;
    }

    if (_translator == null) {
      return englishText;
    }

    try {
      final translated = await _translator!.translateText(englishText);
      _cache[englishText] = translated;
      return translated;
    } catch (e) {
      debugPrint('Translation error for "$englishText": $e');
      return englishText;
    }
  }

  Future<bool> switchLanguage(String newLocaleCode) async {
    _cache.clear();
    return await init(newLocaleCode);
  }

  void dispose() {
    _cache.clear();
    _closeTranslator();
  }
}
