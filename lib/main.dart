/// LabScale — local upscaling and frame interpolation for photos and video.
library;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'state/app_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final controller = AppController();
  await controller.initialize();

  runApp(LabScaleApp(controller: controller));
}

class LabScaleApp extends StatelessWidget {
  const LabScaleApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LabScale',
      debugShowCheckedModeBanner: false,
      theme: buildLabScaleTheme(),
      home: HomePage(controller: controller),
    );
  }
}
