# Vision onboarding refactor plan

## Goal
Remove the language-screen gate from first-run onboarding and replace it with an accessibility-first voice setup flow that starts from the device locale and permissions.

## Behavioral pivot
1. Remove `LanguageScreen` from the startup flow.
2. Detect the OS/device language on cold start and set TTS to that locale.
3. Route directly from `SplashScreen` to `PermissionsScreen` when permissions are needed.
4. On first landing on `HomeScreen`, run the AI interactive onboarding flow.
5. Keep all onboarding spoken prompts in the device/default language, with a clear fallback and retry loop for speech recognition failures.

## Files involved
- `lib/services/onboarding_service.dart`
- `lib/screens/splash/splash_screen.dart`
- `lib/controllers/startup_controller.dart`
- `lib/screens/onboarding/permissions_screen.dart`
- `lib/screens/home/home_screen.dart`
- `lib/controllers/conversation_controller.dart` or a new onboarding controller

## Detailed steps

### 1) Update `OnboardingService`
Add persistent fields for:
- preferred language
- user name
- interactive onboarding completion flag

Methods to add:
- `setPreferredLanguage(String langCode)`
- `getPreferredLanguage()`
- `setUserName(String name)`
- `getUserName()`
- `setInteractiveOnboardingCompleted(bool value)`
- `isInteractiveOnboardingCompleted()`

Keep the existing `selected_language` key for compatibility, but do not use it as the startup gate anymore.

### 2) Remove the language-screen boot requirement
Update `SplashScreen` so that it:
- reads the device locale via `WidgetsBinding.instance.platformDispatcher.locale.languageCode`
- applies it with `SpeechService().setLanguage(resolvedLang)`
- speaks the welcome message in that locale
- checks permissions and navigation without ever pushing `LanguageScreen`

Update `StartupController` so the startup destinations are:
- `permissions`
- `permissionRecovery`
- `home`

Remove any destination that routes to onboarding via `LanguageScreen`.

### 3) Make permissions the first required screen after splash
Update `PermissionsScreen` to:
- initialize TTS using the device locale
- speak permission prompts clearly and immediately
- request missing permissions
- if granted, navigate directly to `HomeScreen`
- if denied, navigate to `PermissionRecoveryScreen`

This keeps the app accessible and removes unnecessary visual setup before core permissions are handled.

### 4) Add the interactive onboarding flow
Create or extend a controller to implement a state machine with phases:
- `askingLanguage`
- `explainingUsage`
- `askingName`
- `ready`

The voice flow should:
1. Ask: "Which language would you prefer to talk with?"
2. Use STT and save the result with `OnboardingService.setPreferredLanguage(...)`
3. Explain Vision and how the app works
4. Ask: "What is your name?"
5. Save the result with `OnboardingService.setUserName(...)`
6. Guide the user to open the camera and tell them they can call the app by saying "Hey Vision"
7. Mark interactive onboarding complete

### 5) Trigger onboarding only on first home landing
In `HomeScreen`:
- verify permissions
- if no permissions: send user to recovery
- otherwise check `isInteractiveOnboardingCompleted()`
- if false: run the onboarding flow before continuing with camera setup and wake-word activation

This avoids launching the normal assistant flow too early while onboarding is still active.

### 6) Handle STT and speech fallbacks safely
For voice recognition failures:
- re-ask the same prompt
- do not advance the onboarding state unless the user response is valid
- keep the flow audio-first and accessible
- ensure there are no blocking calls or silent failures

### 7) Keep wake-word and normal conversation separate from onboarding
Do not start the wake-word activity while the onboarding prompt is active. Only enable the normal conversation loop after onboarding is complete.

## Implementation order
1. `OnboardingService`
2. `StartupController`
3. `SplashScreen`
4. `PermissionsScreen`
5. onboarding controller/state machine
6. `HomeScreen`

## Guardrails
- Do not reintroduce a visual language screen as part of the initial flow.
- Do not use ML Kit model downloads as a prerequisite for onboarding.
- Keep all initial prompts in the OS/device locale.
- Preserve the wake word exactly as `Hey Vision`.
- Keep the experience non-blocking, voice-first, and accessible.
