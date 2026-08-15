import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:blindapp/core/constants/app_strings.dart';
import 'package:blindapp/services/translation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TranslationService tests', () {
    test('AppStrings contains expected constants', () {
      expect(AppStrings.welcomeToVision, equals('Welcome to Vision'));
      expect(AppStrings.permissionsTitle, equals('Permissions'));
      expect(AppStrings.selectLanguageTitle, equals('Select Language'));
    });

    test('TranslationService singleton identity', () {
      final t1 = TranslationService();
      final t2 = TranslationService();
      expect(identical(t1, t2), isTrue);
    });

    test('resolveLanguage maps locale codes correctly', () {
      final ts = TranslationService();
      expect(ts.resolveLanguage('fr-FR'), equals(TranslateLanguage.french));
      expect(ts.resolveLanguage('ar_SA'), equals(TranslateLanguage.arabic));
      expect(ts.resolveLanguage('es'), equals(TranslateLanguage.spanish));
      expect(ts.resolveLanguage(''), equals(TranslateLanguage.english));
    });

    test('isEnglish helper identifies English locale codes', () {
      final ts = TranslationService();
      expect(ts.isEnglish('en-US'), isTrue);
      expect(ts.isEnglish('en'), isTrue);
      expect(ts.isEnglish('fr-FR'), isFalse);
      expect(ts.isEnglish('ar'), isFalse);
    });

    test(
      'translate returns original English string when target is English',
      () async {
        final ts = TranslationService();
        await ts.init('en-US');
        final result = await ts.translate(AppStrings.welcomeToVision);
        expect(result, equals('Welcome to Vision'));
      },
    );
  });
}
