import 'package:flutter/foundation.dart';
import '../models/conversation_message.dart';
import '../services/ai_service.dart';
import '../services/speech_recognition_service.dart';
import '../services/speech_service.dart';
import '../services/wake_word_service.dart';
import '../widgets/voice_orb/orb_state.dart';

class ConversationController {
  final SpeechService _speechService;
  final WakeWordService _wakeWordService;
  final SpeechRecognitionService _speechRecognitionService;
  final AIService _aiService;

  int _sessionGeneration = 0;

  bool _conversationActive = false;
  bool _listening = false;
  bool _processing = false;
  bool _speaking = false;

  final List<ConversationMessage> _contextHistory = [];

  Function(OrbState state)? _onOrbStateChanged;

  Future<Uint8List?> Function()? _captureFrame;

  ConversationController({
    required SpeechService speechService,
    WakeWordService? wakeWordService,
    SpeechRecognitionService? speechRecognitionService,
    AIService? aiService,
  }) : _speechService = speechService,
       _speechRecognitionService =
           speechRecognitionService ?? SpeechRecognitionService(),
       _wakeWordService =
           wakeWordService ??
           WakeWordService(speechRecognitionService: speechRecognitionService),
       _aiService = aiService ?? AIService();

  bool get conversationActive => _conversationActive;
  bool get listening => _listening;
  bool get processing => _processing;
  bool get speaking => _speaking;
  int get sessionGeneration => _sessionGeneration;

  OrbState get orbState {
    if (_speaking) return OrbState.speaking;
    if (_processing) return OrbState.thinking;
    if (_listening) return OrbState.listening;
    return OrbState.idle;
  }

  bool _isCurrentGeneration(int generation) => generation == _sessionGeneration;

  void setOnOrbStateChanged(Function(OrbState state) callback) {
    _onOrbStateChanged = callback;
  }

  void setCaptureFrameProvider(Future<Uint8List?> Function() provider) {
    _captureFrame = provider;
  }

  void _notifyStateChanged() {
    if (_onOrbStateChanged != null) {
      _onOrbStateChanged!(orbState);
    }
  }

  Future<void> start() async {
    debugPrint('ConversationController: initializing...');
    await _speechService.init();
    await _speechRecognitionService.init();

    _speechService.setCompletionHandler(() {
      _handleTtsCompleted();
    });

    _wakeWordService.setOnWakeWordDetected(() {
      _handleWakeWordDetected();
    });

    await _startWakeWordMode();
  }

  Future<void> _handleWakeWordDetected() async {
    _sessionGeneration++;
    final currentGen = _sessionGeneration;
    debugPrint(
      'ConversationController: Wake word detected! [Gen: $currentGen]',
    );

    _conversationActive = true;
    _notifyStateChanged();

    await _startConversationalListening(gen: currentGen);
  }

  Future<void> _startConversationalListening({int? gen}) async {
    final currentGen = gen ?? _sessionGeneration;
    if (!_isCurrentGeneration(currentGen) || !_conversationActive) return;

    await _wakeWordService.stopDetection();

    if (!_isCurrentGeneration(currentGen) || !_conversationActive) return;

    _listening = true;
    _processing = false;
    _speaking = false;
    _notifyStateChanged();

    debugPrint(
      'ConversationController: listening for user speech [Gen: $currentGen]...',
    );

    await _speechRecognitionService.startListening(
      onResult: (String text, bool isFinal) {
        if (!_isCurrentGeneration(currentGen) || !_conversationActive) return;
        if (text.isEmpty) return;

        final normalized = text.toLowerCase().trim();

        // Check for STOP COMMAND
        if (_isStopCommand(normalized)) {
          debugPrint(
            'ConversationController: STOP COMMAND detected ("$text") [Gen: $currentGen]',
          );
          stopConversation();
          return;
        }

        if (isFinal && _listening) {
          _handleUserQuery(text, currentGen);
        }
      },
      onStatus: (String status) {
        debugPrint('Conversational STT status: $status [Gen: $currentGen]');
        if ((status == 'done' || status == 'notListening') &&
            _listening &&
            !_processing &&
            !_speaking) {
          _listening = false;
          _notifyStateChanged();

          if (_conversationActive && _isCurrentGeneration(currentGen)) {
            // Auto-restart listening if conversation is still active for this generation
            Future.delayed(const Duration(milliseconds: 500), () {
              if (_isCurrentGeneration(currentGen) &&
                  _conversationActive &&
                  !_listening &&
                  !_processing &&
                  !_speaking) {
                _startConversationalListening(gen: currentGen);
              }
            });
          }
        }
      },
      onError: (dynamic error) {
        debugPrint('Conversational STT error: $error [Gen: $currentGen]');
        if (!_isCurrentGeneration(currentGen)) return;
        _listening = false;
        _notifyStateChanged();
      },
    );
  }

  bool _isStopCommand(String text) {
    return text.contains('stop vision') ||
        text.contains('stop, vision') ||
        text == 'stop' ||
        text == 'stop vision.' ||
        text.contains('end conversation') ||
        text.contains('cancel vision');
  }

  Future<void> _handleUserQuery(String query, int currentGen) async {
    if (!_isCurrentGeneration(currentGen) || !_conversationActive) return;
    debugPrint(
      'ConversationController: user query = "$query" [Gen: $currentGen]',
    );

    await _speechRecognitionService.stopListening();
    if (!_isCurrentGeneration(currentGen) || !_conversationActive) return;

    _listening = false;
    _processing = true;
    _speaking = false;
    _notifyStateChanged();

    _contextHistory.add(
      ConversationMessage(role: MessageRole.user, text: query),
    );

    final Uint8List? frame = _captureFrame != null
        ? await _captureFrame!()
        : null;
    if (!_isCurrentGeneration(currentGen) || !_conversationActive) return;

    final responseText = await _aiService.processQuery(
      query,
      List.unmodifiable(_contextHistory),
      imageBytes: frame,
    );

    if (!_isCurrentGeneration(currentGen) || !_conversationActive) return;

    _contextHistory.add(
      ConversationMessage(role: MessageRole.assistant, text: responseText),
    );

    _processing = false;
    _speaking = true;
    _notifyStateChanged();

    debugPrint(
      'ConversationController: speaking response = "$responseText" [Gen: $currentGen]',
    );
    await _speechService.speak(responseText);
  }

  void _handleTtsCompleted() {
    final currentGen = _sessionGeneration;
    debugPrint(
      'ConversationController: TTS completed. active = $_conversationActive [Gen: $currentGen]',
    );
    _speaking = false;
    _notifyStateChanged();

    if (_conversationActive && _isCurrentGeneration(currentGen)) {
      _startConversationalListening(gen: currentGen);
    } else {
      _startWakeWordMode();
    }
  }

  Future<void> stopConversation() async {
    _sessionGeneration++;
    debugPrint(
      'ConversationController: Stopping conversation [New Gen: $_sessionGeneration]...',
    );
    _conversationActive = false;
    _listening = false;
    _processing = false;

    await _speechRecognitionService.stopListening();
    _notifyStateChanged();

    await _startWakeWordMode();
  }

  Future<void> _startWakeWordMode() async {
    if (_speaking || _listening || _processing) return;

    await _speechRecognitionService.stopListening();
    _listening = false;
    _notifyStateChanged();

    await _wakeWordService.startDetection();
  }

  Future<void> speakProactive(String text, {bool interrupt = false}) async {
    debugPrint(
      'ConversationController: Proactive speech trigger: "$text" (interrupt: $interrupt)',
    );

    if (interrupt && _speaking) {
      await _speechService.stop();
    }

    await _wakeWordService.stopDetection();
    await _speechRecognitionService.stopListening();

    _listening = false;
    _speaking = true;
    _notifyStateChanged();

    await _speechService.speak(text);
  }

  void handleAppBackground() {
    _sessionGeneration++;
    debugPrint(
      'ConversationController: App backgrounded [New Gen: $_sessionGeneration]. Pausing mic...',
    );
    _wakeWordService.pauseForBackground();
    _speechRecognitionService.stopListening();
    _listening = false;
    _notifyStateChanged();
  }

  void handleAppForeground() {
    _sessionGeneration++;
    final currentGen = _sessionGeneration;
    debugPrint(
      'ConversationController: App foregrounded [New Gen: $currentGen].',
    );
    _wakeWordService.resumeForForeground();

    if (!_conversationActive && !_speaking && !_processing) {
      _startWakeWordMode();
    } else if (_conversationActive && !_speaking && !_processing) {
      _startConversationalListening(gen: currentGen);
    }
  }

  void dispose() {
    _sessionGeneration++;
    debugPrint(
      'ConversationController: disposing [New Gen: $_sessionGeneration]...',
    );
    _wakeWordService.dispose();
    _speechRecognitionService.dispose();
    _speechService.stop();
    _contextHistory.clear();
  }
}
