import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_strings.dart';
import 'speech_service.dart';

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final ValueNotifier<bool> _isOnlineNotifier = ValueNotifier<bool>(true);

  bool _initialized = false;
  bool? _previousOnlineState;
  Function()? _onReconnectedCallback;
  Future<String> Function(String)? _translateCallback;

  ValueNotifier<bool> get isOnlineNotifier => _isOnlineNotifier;
  bool get isOnline => _isOnlineNotifier.value;

  void setOnReconnectedCallback(Function() callback) {
    _onReconnectedCallback = callback;
  }

  void setTranslateCallback(Future<String> Function(String) callback) {
    _translateCallback = callback;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final results = await _connectivity.checkConnectivity();
      _updateState(results, initial: true);
    } catch (e) {
      debugPrint('NetworkService init exception: $e');
    }

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateState(results);
    });
  }

  Future<bool> hasRealInternetAccess() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return false;
      }

      final socket = await Socket.connect(
        'example.com',
        80,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _updateState(
    List<ConnectivityResult> results, {
    bool initial = false,
  }) async {
    final online =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);

    _isOnlineNotifier.value = online;

    if (initial) {
      _previousOnlineState = online;
      return;
    }

    if (_previousOnlineState != null && _previousOnlineState != online) {
      if (!online) {
        debugPrint('NetworkService: Internet connection lost.');
        final message = _translateCallback != null
            ? await _translateCallback!(AppStrings.internetLost)
            : AppStrings.internetLost;
        unawaited(SpeechService().speak(message));
      } else {
        debugPrint('NetworkService: Internet connection restored.');
        final message = _translateCallback != null
            ? await _translateCallback!(AppStrings.internetRestored)
            : AppStrings.internetRestored;
        unawaited(SpeechService().speak(message));
        if (_onReconnectedCallback != null) {
          _onReconnectedCallback!();
        }
      }
    }

    _previousOnlineState = online;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}
