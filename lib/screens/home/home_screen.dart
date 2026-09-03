import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../app/theme/app_theme.dart';
import '../../controllers/home_live_controller.dart';
import '../../core/constants/app_strings.dart';
import '../../services/ai_localization_service.dart';
import '../../services/network_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/permission_service.dart';
import '../../services/speech_service.dart';
import '../../services/translation_service.dart';
import '../../utils/locale_utils.dart';
import '../../widgets/celestial_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/voice_orb/orb_state.dart';
import '../../widgets/voice_orb/voice_orb.dart';
import '../permission_recovery/permission_recovery_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  OrbState _orbState = OrbState.idle;
  String? _cameraError;
  String _retryButtonText = AppStrings.retryCamera;

  late final SpeechService _speechService;
  late final PermissionService _permissionService;
  late final HomeLiveController _homeLiveController;
  late final TranslationService _translationService;
  late final AiLocalizationService _aiLocalizationService;
  late final OnboardingService _onboardingService;
  late final NetworkService _networkService;
  late final Function() _onNetworkReconnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _speechService = SpeechService();
    _permissionService = PermissionService();
    _translationService = TranslationService();
    _aiLocalizationService = AiLocalizationService();
    _onboardingService = OnboardingService();
    _networkService = NetworkService();

    _homeLiveController = HomeLiveController();

    _homeLiveController.setOnOrbStateChanged((OrbState state) {
      if (mounted) {
        setState(() {
          _orbState = state;
        });
      }
    });

    _onNetworkReconnected = () {
      unawaited(_handleNetworkReconnected());
    };
    _networkService.addOnReconnectedCallback(_onNetworkReconnected);

    _loadTranslations();
    _verifyPermissionsAndInitialize();
  }

  Future<void> _loadTranslations() async {
    _retryButtonText = await _translationService.translate(
      AppStrings.retryCamera,
    );
    if (mounted) setState(() {});
  }

  Future<void> _waitForWindowReady() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    await completer.future;
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _verifyPermissionsAndInitialize() async {
    final state = await _permissionService.checkRequired();
    if (!mounted) return;

    if (state != PermissionState.granted) {
      _navigateToPermissionRecovery();
      return;
    }

    final preferredLang = await _onboardingService.getPreferredLanguage();
    final deviceLang =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final activeLang =
        preferredLang ?? (deviceLang.isEmpty ? 'en' : deviceLang);

    await _speechService.setLanguage(activeLang);
    if (preferredLang != null && preferredLang.isNotEmpty) {
      await _translationService.init(preferredLang);
    }

    final languageName = LocaleUtils.getDisplayName(activeLang);
    await _aiLocalizationService.init(activeLang, languageName);
    unawaited(_aiLocalizationService.speakLocalized('settingThingsUp'));

    await _waitForWindowReady();
    await _initializeCamera();
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _homeLiveController.start(_cameraController!);
    }
  }

  Future<void> _handleNetworkReconnected() async {
    if (!mounted) return;
    if (_homeLiveController.isConnected) return;

    unawaited(_aiLocalizationService.speakLocalized('settingThingsUp'));

    await _cameraController?.dispose();
    _cameraController = null;
    if (mounted) {
      setState(() {
        _cameraError = null;
      });
    }

    await _waitForWindowReady();
    await _initializeCamera();

    if (!mounted) return;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _homeLiveController.start(_cameraController!);
    }
  }

  Future<void> _initializeCamera({int attempt = 0}) async {
    const maxAttempts = 3;
    try {
      if (mounted) {
        setState(() {
          _cameraError = null;
        });
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        final noCameraMsg = await _translationService.translate(
          AppStrings.noCameraHardware,
        );
        if (mounted) {
          setState(() {
            _cameraError = noCameraMsg;
          });
        }
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw CameraException(
            'initTimeout',
            'Camera initialization did not respond in time.',
          );
        },
      );
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      debugPrint("CameraException [${e.code}]: ${e.description}");
      if (!mounted) return;

      if (e.code == 'CameraAccessDenied' ||
          e.code == 'cameraPermission' ||
          e.code == 'CameraAccessRestricted') {
        _navigateToPermissionRecovery();
        return;
      }

      if (attempt < maxAttempts - 1) {
        await _cameraController?.dispose();
        _cameraController = null;
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await _initializeCamera(attempt: attempt + 1);
        }
        return;
      }

      final errorMsg = await _translationService.translate(
        AppStrings.cameraUnavailable,
      );
      final rawDetail = e.description ?? e.code;
      final shortDetail = rawDetail.length > 140
          ? '${rawDetail.substring(0, 140)}...'
          : rawDetail;
      if (mounted) {
        setState(() {
          _cameraError = "$errorMsg ($shortDetail)";
        });
      }
    } catch (e) {
      debugPrint("Generic camera initialization error: $e");

      if (attempt < maxAttempts - 1) {
        await _cameraController?.dispose();
        _cameraController = null;
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await _initializeCamera(attempt: attempt + 1);
        }
        return;
      }

      final errorMsg = await _translationService.translate(
        AppStrings.cameraUnavailable,
      );
      if (mounted) {
        setState(() {
          _cameraError = errorMsg;
        });
      }
    }
  }

  void _navigateToPermissionRecovery() {
    _homeLiveController.pause();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PermissionRecoveryScreen()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _homeLiveController.pause();
    } else if (state == AppLifecycleState.resumed) {
      _checkPermissionsOnResume();
    }
  }

  Future<void> _checkPermissionsOnResume() async {
    final permState = await _permissionService.checkRequired();
    if (!mounted) return;

    if (permState != PermissionState.granted) {
      _navigateToPermissionRecovery();
      return;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _waitForWindowReady();
      await _initializeCamera();
    }

    await _homeLiveController.resume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkService.removeOnReconnectedCallback(_onNetworkReconnected);
    _cameraController?.dispose();
    _homeLiveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CelestialBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraController != null &&
                _cameraController!.value.isInitialized)
              ExcludeSemantics(child: CameraPreview(_cameraController!))
            else if (_cameraError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SingleChildScrollView(
                    child: GlassCard(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_off_rounded,
                            size: 56,
                            color: AppColors.warningOrange,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _cameraError!,
                            textAlign: TextAlign.center,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          GlassCard(
                            onTap: _initializeCamera,
                            semanticsLabel: _retryButtonText,
                            borderColor: AppColors.electricCyan,
                            fillColor: AppColors.electricCyan.withValues(
                              alpha: 0.2,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.refresh_rounded,
                                  color: AppColors.electricCyan,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _retryButtonText,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: AppColors.electricCyan,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              const Center(
                child: ExcludeSemantics(
                  child: CircularProgressIndicator(
                    color: AppColors.electricCyan,
                  ),
                ),
              ),

            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: VoiceOrb(state: _orbState, size: 100.0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
