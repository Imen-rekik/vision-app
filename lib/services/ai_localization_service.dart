import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_strings.dart';
import 'network_service.dart';
import 'speech_service.dart';

class AiLocalizationService {
  static final AiLocalizationService _instance =
      AiLocalizationService._internal();
  factory AiLocalizationService() => _instance;
  AiLocalizationService._internal();

  static const String _localizeUrl =
      'https://vision-ai-relay.vercel.app/api/localize';

  static const Duration _fetchWaitTimeout = Duration(seconds: 20);

  static const Map<String, String> _sourceStrings = {
    'welcomeToVision': AppStrings.welcomeToVision,
    'permissionsTitle': AppStrings.permissionsTitle,
    'permissionsDescription': AppStrings.permissionsDescription,
    'permissionsExplanation': AppStrings.permissionsExplanation,
    'permissionsNotGranted': AppStrings.permissionsNotGranted,
    'settingThingsUp': AppStrings.settingThingsUp,
    'permissionsRecoveryPrompt': AppStrings.permissionsRecoveryPrompt,
    'permissionsStillMissing': AppStrings.permissionsStillMissing,
    'permissionsRequiredTitle': AppStrings.permissionsRequiredTitle,
    'permissionsRequiredDesc': AppStrings.permissionsRequiredDesc,
    'openSettings': AppStrings.openSettings,
    'iHaveGrantedThem': AppStrings.iHaveGrantedThem,
  };

  String? _activeLanguageCode;
  final Map<String, String> _textCache = {};
  final Set<String> _audioAvailable = {};
  bool _fetchInProgress = false;
  final List<void Function(String)> _onReadyCallbacks = [];

  void addOnReadyCallback(void Function(String languageCode) callback) {
    _onReadyCallbacks.add(callback);
  }

  void removeOnReadyCallback(void Function(String languageCode) callback) {
    _onReadyCallbacks.remove(callback);
  }

  String getText(String key) {
    final englishText = _sourceStrings[key] ?? '';
    if (_activeLanguageCode == null || _activeLanguageCode == 'en') {
      return englishText;
    }
    return _textCache[key] ?? englishText;
  }

  Future<void> init(String languageCode, String languageName) async {
    final normalized = languageCode.trim().toLowerCase();
    _activeLanguageCode = normalized;
    _textCache.clear();
    _audioAvailable.clear();

    if (normalized == 'en') {
      return;
    }

    await _loadCacheFromDisk(normalized);

    final missingKeys = _sourceStrings.keys
        .where((key) => !_textCache.containsKey(key))
        .toList();

    if (missingKeys.isEmpty) {
      debugPrint('AiLocalizationService: $normalized already fully cached');
      return;
    }

    final fetchFuture = _fetchAndCache(normalized, languageName, missingKeys);

    await fetchFuture.timeout(
      _fetchWaitTimeout,
      onTimeout: () {
        debugPrint(
          'AiLocalizationService: $normalized fetch still running after '
          '${_fetchWaitTimeout.inSeconds}s, continuing in background',
        );
      },
    );
  }

  Future<void> _loadCacheFromDisk(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    final audioDir = await _audioDirectory();

    for (final key in _sourceStrings.keys) {
      final savedText = prefs.getString(_textPrefKey(languageCode, key));
      if (savedText != null && savedText.isNotEmpty) {
        _textCache[key] = savedText;
      }

      final audioFile = File(_audioFilePath(audioDir.path, languageCode, key));
      if (await audioFile.exists()) {
        _audioAvailable.add(key);
      }
    }
  }

  Future<void> _fetchAndCache(
    String languageCode,
    String languageName,
    List<String> keys,
  ) async {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    final stopwatch = Stopwatch()..start();

    try {
      final isOnline = await NetworkService().hasRealInternetAccess();
      if (!isOnline) {
        debugPrint(
          'AiLocalizationService: offline, skipping fetch for $languageCode',
        );
        return;
      }

      final items = keys
          .map((key) => {'key': key, 'text': _sourceStrings[key] ?? ''})
          .toList();

      debugPrint(
        'AiLocalizationService: fetching ${items.length} strings for $languageCode',
      );

      final response = await http
          .post(
            Uri.parse(_localizeUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'items': items,
              'languageCode': languageCode,
              'languageName': languageName,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint(
          'AiLocalizationService: fetch failed (${response.statusCode}) '
          'after ${stopwatch.elapsedMilliseconds}ms',
        );
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final resultItems = data['items'] as List<dynamic>? ?? [];

      final prefs = await SharedPreferences.getInstance();
      final audioDir = await _audioDirectory();

      for (final raw in resultItems) {
        final item = raw as Map<String, dynamic>;
        final key = item['key'] as String?;
        final text = item['text'] as String?;
        final audioBase64 = item['audioBase64'] as String?;

        if (key == null || text == null || text.isEmpty) continue;

        _textCache[key] = text;
        await prefs.setString(_textPrefKey(languageCode, key), text);

        if (audioBase64 != null && audioBase64.isNotEmpty) {
          try {
            final bytes = base64Decode(audioBase64);
            final file = File(_audioFilePath(audioDir.path, languageCode, key));
            await file.writeAsBytes(bytes, flush: true);
            _audioAvailable.add(key);
          } catch (e) {
            debugPrint(
              'AiLocalizationService: failed to save audio for "$key": $e',
            );
          }
        }
      }

      debugPrint(
        'AiLocalizationService: cache updated for $languageCode in '
        '${stopwatch.elapsedMilliseconds}ms',
      );

      for (final callback in List<void Function(String)>.from(
        _onReadyCallbacks,
      )) {
        callback(languageCode);
      }
    } catch (e) {
      debugPrint(
        'AiLocalizationService: fetch exception after '
        '${stopwatch.elapsedMilliseconds}ms: $e',
      );
    } finally {
      _fetchInProgress = false;
    }
  }

  Future<void> speakLocalized(String key) async {
    final languageCode = _activeLanguageCode;

    if (languageCode != null &&
        languageCode != 'en' &&
        _audioAvailable.contains(key)) {
      final audioDir = await _audioDirectory();
      final path = _audioFilePath(audioDir.path, languageCode, key);
      if (await File(path).exists()) {
        final played = await _playAudioFile(path);
        if (played) return;
      }
    }

    await SpeechService().speakAndAwait(getText(key));
  }

  Future<bool> _playAudioFile(String path) async {
    final player = FlutterSoundPlayer();
    final completer = Completer<void>();

    try {
      await player.openPlayer();
      await player.startPlayer(
        fromURI: path,
        codec: Codec.pcm16WAV,
        whenFinished: () {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );
      return true;
    } catch (e) {
      debugPrint('AiLocalizationService: playback failed: $e');
      return false;
    } finally {
      await player.closePlayer();
    }
  }

  Future<Directory> _audioDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/ai_localization_audio');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _audioFilePath(String dirPath, String languageCode, String key) {
    return '$dirPath/${languageCode}_$key.wav';
  }

  String _textPrefKey(String languageCode, String key) {
    return 'ai_loc_text_${languageCode}_$key';
  }
}
