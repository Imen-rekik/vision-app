class AppStrings {
  // Onboarding & Splash
  static const String welcomeToVision = "Welcome to Vision";
  static const String settingUpLanguage = "Setting up application language...";
  static const String stillSettingUpLanguage =
      "Still setting up, almost there...";
  static const String downloadingLanguagePack = "please wait a moment...";
  static const String languageRequiresInternet =
      "You're offline. Please connect to the internet to continue.";
  static const String selectLanguagePrompt =
      "Please select your preferred language.";
  static const String selectLanguageTitle = "Select Language";
  static const String noLanguagesFound = "No languages found";

  // Permissions
  static const String permissionsExplanation =
      "Vision needs access to your camera, microphone and location to help you. "
      "Please grant these permissions on the next screen.";
  static const String permissionsNotGranted =
      "Permissions were not granted. Vision requires permissions to assist you.";
  static const String permissionsTitle = "Permissions";
  static const String permissionsDescription =
      "Vision requires camera, microphone and location access to function as your assistant.";

  // Permission Recovery
  static const String permissionsRecoveryPrompt =
      "Vision needs permissions to continue. Please open settings and grant them.";
  static const String permissionsStillMissing =
      "Permissions are still missing.";
  static const String permissionsRequiredTitle = "Permissions Required";
  static const String permissionsRequiredDesc =
      "Vision needs camera, microphone and location access to function. Please grant them in settings.";
  static const String openSettings = "Open Settings";
  static const String iHaveGrantedThem = "I have granted them";

  // Fixed trigger phrases recognized by WakeWordService - must stay in English regardless of app language, or the wake-word engine won't recognize what the user is told to say.
  static const String wakeWordPhrase = "Hey Vision";
  static const String stopWordPhrase = "Stop Vision";

  // Voice Onboarding (Interactive AI Setup)
  static const String voiceOnboardingGreeting =
      "Hello, I am Vision. I help you understand the world around you. "
      "Which language would you prefer to talk with? Please say the name "
      "of the language you want.";
  static const String voiceOnboardingLanguageRetry =
      "I did not catch that. What language do you prefer?";
  static const String voiceOnboardingLanguageNotRecognized =
      "I did not recognize that language. Please say it again.";
  static const String voiceOnboardingLanguageFallbackPrefix = "I will use ";
  static const String voiceOnboardingLanguageFallbackSuffix = " for now.";
  static const String voiceOnboardingAskName = "Please tell me your name.";
  static const String voiceOnboardingAskNameRetry =
      "I did not catch that. Please tell me your name.";
  static const String voiceOnboardingNameFallbackPrefix = "I will call you ";
  static const String voiceOnboardingNameFallbackSuffix = " for now.";
  static const String voiceOnboardingCompletePart1 = "Great, ";
  static const String voiceOnboardingCompletePart2 =
      ". Your preferred language is now ";
  static const String voiceOnboardingCompletePart3 =
      ". I am Vision. I can describe what is around you, help you "
      "navigate, and answer your questions out loud. To talk to me, say ";
  static const String voiceOnboardingCompletePart4 =
      ". To end a conversation, say ";
  static const String voiceOnboardingCompletePart5 = ".";
  static const String voiceOnboardingStatusInitial = "Voice setup";
  static const String voiceOnboardingStatusListeningLanguage =
      "Listening for language";
  static const String voiceOnboardingStatusListeningName =
      "Listening for your name";
  static const String voiceOnboardingScreenTitle = "AI Setup";

  // How to Use Walkthrough
  static const String howToUseWalkthroughPart1 =
      "You are now ready to use Vision. I'm your AI assistant, designed to help you understand and interact with the world around you. To talk to me, simply say: ";
  static const String howToUseWalkthroughPart2 =
      ". You can ask questions, ask for descriptions, or ask for help with your surroundings. Say ";
  static const String howToUseWalkthroughPart3 =
      " when you want to end the conversation. If I detect something important, such as a dangerous obstacle, I can alert you immediately. You're ready to use Vision.";
  static const String howToUseTitle = "How to Use Vision";
  static const String howToUseSubtitleSay = "Say";
  static const String howToUseSubtitleToStart = "to start talking with Vision.";
  static const String howToUseSubtitleToEnd = "to end the conversation.";

  // Network Alerts
  static const String internetLost = "Internet connection lost.";
  static const String internetRestored = "Internet connection restored.";
  static const String aiRequiresInternet =
      "AI assistant requires internet connection. Please connect and try again.";
  static const String aiRequestFailed =
      "I could not process that just now. Please try again.";

  // Camera & Errors
  static const String cameraUnavailable =
      "Camera unavailable. Voice features remain active.";
  static const String noCameraHardware =
      "No camera hardware detected on this device.";
  static const String settingThingsUp =
      "Setting things up for you. This will just take a moment.";
  static const String retryCamera = "Retry Camera";

  static const String liveConnectionProblem =
      "There's a problem with the vision assistant right now. "
      "I won't be able to warn you automatically, so please be careful.";
  static const String liveConnectionRestored =
      "The vision assistant is working again.";
  static const String liveUnavailableDuringConversation =
      "I can't reach the assistant right now. Please try again in a moment.";
}
