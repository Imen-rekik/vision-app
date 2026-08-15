import 'package:flutter/material.dart';
import 'app/app.dart';
import 'services/network_service.dart';
import 'services/translation_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NetworkService().setTranslateCallback(TranslationService().translate);
  runApp(const VisionApp());
}
