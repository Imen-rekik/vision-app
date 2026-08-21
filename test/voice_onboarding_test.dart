import 'package:flutter_test/flutter_test.dart';
import 'package:blindapp/core/constants/onboarding_prompts.dart';
import 'package:blindapp/screens/onboarding/voice_onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Voice Onboarding Tests', () {
    test(
      'buildLiveOnboardingSystemPrompt formats prompt with any chosen language',
      () {
        final frenchPrompt = OnboardingPrompts.buildLiveOnboardingSystemPrompt(
          languageCode: 'fr',
          languageName: 'French',
        );

        expect(frenchPrompt.contains('French (language code: fr)'), isTrue);
        expect(
          frenchPrompt.contains(
            'You MUST initiate the conversation and speak in French (fr)',
          ),
          isTrue,
        );
        expect(frenchPrompt.contains('complete_onboarding'), isTrue);

        final arabicPrompt = OnboardingPrompts.buildLiveOnboardingSystemPrompt(
          languageCode: 'ar',
          languageName: 'Arabic',
        );

        expect(arabicPrompt.contains('Arabic (language code: ar)'), isTrue);
        expect(
          arabicPrompt.contains(
            'You MUST initiate the conversation and speak in Arabic (ar)',
          ),
          isTrue,
        );

        final japanesePrompt =
            OnboardingPrompts.buildLiveOnboardingSystemPrompt(
              languageCode: 'ja',
              languageName: 'Japanese',
            );

        expect(japanesePrompt.contains('Japanese (language code: ja)'), isTrue);
        expect(
          japanesePrompt.contains(
            'You MUST initiate the conversation and speak in Japanese (ja)',
          ),
          isTrue,
        );
      },
    );

    test('completeOnboardingTool has proper declaration and parameters', () {
      final tool = OnboardingPrompts.completeOnboardingTool;
      expect(tool.functionDeclarations, isNotNull);
      expect(tool.functionDeclarations!.length, equals(1));

      final decl = tool.functionDeclarations!.first;
      expect(decl.name, equals('complete_onboarding'));
      expect(decl.parameters?['required'], containsAll(['language', 'name']));
    });

    test('VoiceActivityState states are properly configured', () {
      expect(
        VoiceActivityState.values,
        containsAll([
          VoiceActivityState.initializing,
          VoiceActivityState.connecting,
          VoiceActivityState.gettingReady,
          VoiceActivityState.speaking,
          VoiceActivityState.listening,
          VoiceActivityState.processing,
          VoiceActivityState.error,
        ]),
      );
    });
  });
}
