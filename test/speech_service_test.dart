import 'package:flutter_test/flutter_test.dart';
import 'package:blindapp/services/speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SpeechService is a singleton across multiple instantiations', () {
    final instance1 = SpeechService();
    final instance2 = SpeechService();
    expect(identical(instance1, instance2), isTrue);
  });
}
