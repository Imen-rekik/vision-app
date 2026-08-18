import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../app/theme/app_theme.dart';
import '../../controllers/conversation_controller.dart';
import '../../core/constants/app_strings.dart';
import '../../services/onboarding_service.dart';
import '../../services/camera_capture_service.dart';
import '../../services/permission_service.dart';
import '../../services/speech_service.dart';
import '../../services/translation_service.dart';
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
  late final ConversationController _conversationController;
  late final TranslationService _translationService;
  late final OnboardingService _onboardingService;
  final CameraCaptureService _cameraCaptureService = CameraCaptureService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _speechService = SpeechService();
    _permissionService = PermissionService();
    _translationService = TranslationService();
    _onboardingService = OnboardingService();

    _conversationController = ConversationController(
      speechService: _speechService,
    );

    _conversationController.setOnOrbStateChanged((OrbState state) {
      if (mounted) {
        setState(() {
          _orbState = state;
        });
      }
    });

    // The controller asks for a frame only at the moment it actually needs
    // one (right when a user query is ready to send) — this closure just
    // hands it whatever CameraController currently holds, without the
    // controller needing to know CameraController exists.
    _conversationController.setCaptureFrameProvider(
      () => _cameraCaptureService.captureFrame(_cameraController),
    );

    _loadTranslations();
    _verifyPermissionsAndInitialize();
  }

  Future<void> _loadTranslations() async {
    _retryButtonText = await _translationService.translate(
      AppStrings.retryCamera,
    );
    if (mounted) setState(() {});
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

    await _initializeCamera();
    _conversationController.start();
  }

  Future<void> _initializeCamera() async {
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
      );

      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      debugPrint("CameraException [${e.code}]: ${e.description}");
      if (!mounted) return;

      if (e.code == 'CameraAccessDenied' ||
          e.code == 'cameraPermission' ||
          e.code == 'CameraAccessRestricted') {
        _navigateToPermissionRecovery();
      } else {
        final errorMsg = await _translationService.translate(
          AppStrings.cameraUnavailable,
        );
        if (mounted) {
          setState(() {
            _cameraError = "$errorMsg (${e.description ?? e.code})";
          });
        }
      }
    } catch (e) {
      debugPrint("Generic camera initialization error: $e");
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
    _conversationController.handleAppBackground();
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
      _conversationController.handleAppBackground();
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
      await _initializeCamera();
    }

    _conversationController.handleAppForeground();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _conversationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CelestialBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Layer: Camera Preview or Error/Loading
            if (_cameraController != null &&
                _cameraController!.value.isInitialized)
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0.65,
                  child: CameraPreview(_cameraController!),
                ),
              )
            else if (_cameraError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
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
              )
            else
              const Center(
                child: ExcludeSemantics(
                  child: CircularProgressIndicator(
                    color: AppColors.electricCyan,
                  ),
                ),
              ),

            // Semi-Transparent Dark Glass Overlay for visual contrast
            Container(color: AppColors.deepMidnight.withValues(alpha: 0.45)),

            // Central VoiceOrb Component
            Center(child: VoiceOrb(state: _orbState)),
          ],
        ),
      ),
    );
  }
}
