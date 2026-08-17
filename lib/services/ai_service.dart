import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/ai_prompts.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/onboarding_prompts.dart';
import '../models/conversation_message.dart';
import '../models/onboarding_turn_result.dart';
import 'network_service.dart';
import 'translation_service.dart';

class AIService {
  static const String _visionRelayUrl =
      'https://vision-ai-relay.vercel.app/api/vision-query';

  static const Duration _requestTimeout = Duration(seconds: 50);

  static const int _maxHistoryTurns = 6;

  final http.Client _httpClient;

  AIService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<String> processQuery(
    String query,
    List<ConversationMessage> history, {
    Uint8List? imageBytes,
  }) async {
    if (!NetworkService().isOnline) {
      debugPrint('AIService: Device is offline.');
      return await TranslationService().translate(
        AppStrings.aiRequiresInternet,
      );
    }

    for (var attempt = 1; attempt <= 2; attempt++) {
      debugPrint(
        'AIService: sending query="$query" '
        'withImage=${imageBytes != null} historyLen=${history.length} '
        'attempt=$attempt',
      );

      try {
        final requestBody = jsonEncode({
          'system_prompt': AiPrompts.visionSystemPrompt,
          'query': query,
          'image_base64': imageBytes != null ? base64Encode(imageBytes) : null,
          'history': _recentHistoryAsJson(history),
        });

        final response = await _httpClient
            .post(
              Uri.parse(_visionRelayUrl),
              headers: {'Content-Type': 'application/json'},
              body: requestBody,
            )
            .timeout(_requestTimeout);

        if (response.statusCode != 200) {
          debugPrint(
            'AIService: relay returned ${response.statusCode}: ${response.body}',
          );

          if (attempt == 1) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }

          return await TranslationService().translate(
            AppStrings.aiRequestFailed,
          );
        }

        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final answer = decoded['answer'] as String?;

        if (answer == null || answer.trim().isEmpty) {
          debugPrint('AIService: relay response had no answer field.');

          if (attempt == 1) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }

          return await TranslationService().translate(
            AppStrings.aiRequestFailed,
          );
        }

        return answer.trim();
      } catch (e) {
        debugPrint('AIService: request failed: $e');

        if (attempt == 1) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        return await TranslationService().translate(AppStrings.aiRequestFailed);
      }
    }

    return await TranslationService().translate(AppStrings.aiRequestFailed);
  }

  Future<OnboardingTurnResult?> runOnboardingTurn(
    String userUtterance,
    List<ConversationMessage> history,
  ) async {
    if (!NetworkService().isOnline) {
      debugPrint('AIService: onboarding turn skipped, device offline.');
      return null;
    }

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final requestBody = jsonEncode({
          'system_prompt': OnboardingPrompts.onboardingSystemPrompt,
          'query': userUtterance,
          'image_base64': null,
          'history': _recentHistoryAsJson(history),
          'max_output_tokens': 1500,
        });

        final response = await _httpClient
            .post(
              Uri.parse(_visionRelayUrl),
              headers: {'Content-Type': 'application/json'},
              body: requestBody,
            )
            .timeout(_requestTimeout);

        if (response.statusCode != 200) {
          debugPrint(
            'AIService: onboarding relay returned ${response.statusCode}: '
            '${response.body}',
          );

          if (attempt == 1) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }

          return null;
        }

        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final answer = decoded['answer'] as String?;

        if (answer == null || answer.trim().isEmpty) {
          debugPrint('AIService: onboarding relay response had no answer.');

          if (attempt == 1) {
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }

          return null;
        }

        final parsed = OnboardingTurnResult.tryParse(answer);

        if (parsed == null) {
          debugPrint('AIService: could not parse onboarding JSON: $answer');
        }

        return parsed;
      } catch (e) {
        debugPrint('AIService: onboarding turn failed: $e');

        if (attempt == 1) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        return null;
      }
    }

    return null;
  }

  List<Map<String, String>> _recentHistoryAsJson(
    List<ConversationMessage> history,
  ) {
    final recent = history.length > _maxHistoryTurns
        ? history.sublist(history.length - _maxHistoryTurns)
        : history;

    return recent
        .map((m) => {'role': m.role.name, 'text': m.text})
        .toList(growable: false);
  }
}
