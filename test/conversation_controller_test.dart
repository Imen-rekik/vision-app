import 'package:flutter_test/flutter_test.dart';
import 'package:blindapp/controllers/conversation_controller.dart';
import 'package:blindapp/services/speech_service.dart';
import 'package:blindapp/services/wake_word_service.dart';
import 'package:blindapp/services/speech_recognition_service.dart';
import 'package:blindapp/services/ai_service.dart';
import 'package:blindapp/widgets/voice_orb/orb_state.dart';

class MockSpeechService implements SpeechService {
  bool speakCalled = false;
  bool stopCalled = false;
  String? lastSpokenText;
  Function()? completionCallback;

  @override
  bool get isSpeaking => false;

  @override
  Future<void> init() async {}

  @override
  void setCompletionHandler(Function() onComplete) {
    completionCallback = onComplete;
  }

  @override
  Future<void> speak(String text) async {
    speakCalled = true;
    lastSpokenText = text;
  }

  @override
  Future<void> speakAndAwait(String text) async {
    speakCalled = true;
    lastSpokenText = text;
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
  }

  @override
  Future<void> setLanguage(String languageCode) async {}

  @override
  Future<List<dynamic>> getLanguages() async => [];

  @override
  void dispose() {
    stopCalled = true;
  }
}

class MockWakeWordService implements WakeWordService {
  bool isDetectingState = false;
  bool isAppInForegroundState = true;
  Function()? callback;

  @override
  bool get isDetecting => isDetectingState;

  @override
  bool get isAppInForeground => isAppInForegroundState;

  @override
  void setOnWakeWordDetected(Function() cb) {
    callback = cb;
  }

  @override
  Future<void> startDetection() async {
    isDetectingState = true;
  }

  @override
  Future<void> stopDetection() async {
    isDetectingState = false;
  }

  @override
  void pauseForBackground() {
    isAppInForegroundState = false;
    isDetectingState = false;
  }

  @override
  void resumeForForeground() {
    isAppInForegroundState = true;
  }

  @override
  void dispose() {
    isDetectingState = false;
  }

  void triggerWakeWord() {
    if (callback != null) callback!();
  }
}

class MockSpeechRecognitionService implements SpeechRecognitionService {
  bool isListeningState = false;

  @override
  bool get isAvailable => true;

  @override
  bool get isListening => isListeningState;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    Function(String status)? onStatus,
    Function(dynamic error)? onError,
    Duration? listenFor,
    Duration? pauseFor,
  }) async {
    isListeningState = true;
  }

  @override
  Future<void> stopListening() async {
    isListeningState = false;
  }

  @override
  Future<void> cancel() async {
    isListeningState = false;
  }

  @override
  void dispose() {
    isListeningState = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSpeechService mockSpeechService;
  late MockWakeWordService mockWakeWordService;
  late MockSpeechRecognitionService mockSpeechRecognitionService;
  late ConversationController controller;

  setUp(() {
    mockSpeechService = MockSpeechService();
    mockSpeechRecognitionService = MockSpeechRecognitionService();
    mockWakeWordService = MockWakeWordService();

    controller = ConversationController(
      speechService: mockSpeechService,
      wakeWordService: mockWakeWordService,
      speechRecognitionService: mockSpeechRecognitionService,
      aiService: AIService(),
    );
  });

  test(
    'Initial state: conversationActive=false, listening=false, speaking=false',
    () {
      expect(controller.conversationActive, isFalse);
      expect(controller.listening, isFalse);
      expect(controller.speaking, isFalse);
      expect(controller.processing, isFalse);
      expect(controller.orbState, equals(OrbState.idle));
    },
  );

  test('Proactive speech can occur when conversationActive is FALSE', () async {
    await controller.speakProactive('Careful, obstacle ahead.');

    expect(controller.conversationActive, isFalse);
    expect(controller.speaking, isTrue);
    expect(controller.orbState, equals(OrbState.speaking));
    expect(mockSpeechService.speakCalled, isTrue);
    expect(
      mockSpeechService.lastSpokenText,
      equals('Careful, obstacle ahead.'),
    );
  });

  test('Stop conversation leaves SpeechService available', () async {
    await controller.stopConversation();

    expect(controller.conversationActive, isFalse);
    expect(controller.listening, isFalse);
    expect(controller.speaking, isFalse);

    // Can still speak proactively after stopping conversation
    await controller.speakProactive('Safety alert');
    expect(mockSpeechService.speakCalled, isTrue);
  });

  test(
    'stopConversation increments generation token and invalidates old session',
    () async {
      final initialGen = controller.sessionGeneration;
      await controller.stopConversation();
      expect(controller.sessionGeneration, greaterThan(initialGen));
    },
  );

  test('Backgrounding app increments generation token and stops listening', () {
    final initialGen = controller.sessionGeneration;
    controller.handleAppBackground();
    expect(controller.sessionGeneration, greaterThan(initialGen));
    expect(controller.listening, isFalse);
  });

  test(
    'Triggering wake word increments generation token and starts active conversation',
    () async {
      await controller.start();
      final initialGen = controller.sessionGeneration;
      mockWakeWordService.triggerWakeWord();
      expect(controller.sessionGeneration, greaterThan(initialGen));
      expect(controller.conversationActive, isTrue);
    },
  );
}
