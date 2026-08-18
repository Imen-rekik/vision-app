import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:gemini_live/gemini_live.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

class LiveTestScreen extends StatefulWidget {
  const LiveTestScreen({super.key});

  @override
  State<LiveTestScreen> createState() => _LiveTestScreenState();
}

class _LiveTestScreenState extends State<LiveTestScreen> {
  String _status = 'Not connected';
  LiveSession? _session;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<List<int>>? _micSubscription;
  bool _isTalking = false;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _playerReady = false;
  final List<Uint8List> _audioQueue = [];
  bool _isFeedingAudio = false;

  Future<void> _connect() async {
    setState(() => _status = 'Getting token...');

    if (!_playerReady) {
      await _player.openPlayer();
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 24000,
        bufferSize: 8192,
        interleaved: true,
      );
      _playerReady = true;
    }

    final tokenResponse = await http.post(
      Uri.parse('https://vision-ai-relay.vercel.app/api/live-token'),
    );

    if (tokenResponse.statusCode != 200) {
      setState(() => _status = 'Token request failed: ${tokenResponse.body}');
      return;
    }

    final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    final token = tokenData['token'] as String;

    setState(() => _status = 'Connecting to Gemini...');

    final genAI = GoogleGenAI(apiKey: token, apiVersion: 'v1alpha');

    try {
      _session = await genAI.live.connect(
        LiveConnectParameters(
          model: 'gemini-3.1-flash-live-preview',
          config: GenerationConfig(responseModalities: [Modality.AUDIO]),
          callbacks: LiveCallbacks(
            onOpen: () {
              setState(() => _status = 'Connected!');
            },
            onMessage: (LiveServerMessage message) {
              if (message.data != null) {
                final bytes = base64Decode(message.data!);
                _audioQueue.add(bytes);
                _drainAudioQueue();
                setState(() => _status = 'Playing reply...');
              } else {
                setState(() => _status = 'Got a message from Gemini');
              }
            },
            onError: (e, s) {
              setState(() => _status = 'Error: $e');
            },
            onClose: (code, reason) {
              setState(() => _status = 'Closed: $reason');
            },
          ),
        ),
      );
    } catch (e) {
      setState(() => _status = 'Connect failed: $e');
    }
  }

  Future<void> _drainAudioQueue() async {
    if (_isFeedingAudio) return;
    _isFeedingAudio = true;
    while (_audioQueue.isNotEmpty) {
      final chunk = _audioQueue.removeAt(0);
      await _player.feedUint8FromStream(chunk);
    }
    _isFeedingAudio = false;
  }

  Future<void> _startTalking() async {
    if (_session == null) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() => _status = 'Microphone permission denied');
      return;
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    setState(() {
      _isTalking = true;
      _status = 'Listening...';
    });

    _micSubscription = stream.listen((chunk) {
      _session?.sendAudio(chunk);
    });
  }

  Future<void> _stopTalking() async {
    await _recorder.stop();
    await _micSubscription?.cancel();
    _micSubscription = null;
    _session?.sendAudioStreamEnd();

    setState(() {
      _isTalking = false;
      _status = 'Sent. Waiting for reply...';
    });
  }

  @override
  void dispose() {
    _micSubscription?.cancel();
    _recorder.dispose();
    _session?.close();
    if (_playerReady) {
      _player.stopPlayer();
      _player.closePlayer();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live API Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_status, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _connect, child: const Text('Connect')),
            const SizedBox(height: 24),
            if (_session != null)
              GestureDetector(
                onLongPressStart: (_) => _startTalking(),
                onLongPressEnd: (_) => _stopTalking(),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: _isTalking ? Colors.red : Colors.blue,
                  child: const Icon(Icons.mic, color: Colors.white, size: 32),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
