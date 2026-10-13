/// LabScale — local upscaling and frame interpolation for photos and video.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'l10n/strings.dart';
import 'state/app_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  LicenseRegistry.addLicense(_bundledToolLicenses);

  final controller = AppController();
  await controller.initialize();

  runApp(LabScaleApp(controller: controller));
}

/// The licences page lists Flutter packages on its own; the tools and models
/// in bin/ are not Dart packages, so their notices are added from the same
/// file that ships beside the binaries.
Stream<LicenseEntry> _bundledToolLicenses() async* {
  final notices = await rootBundle.loadString('THIRD_PARTY_NOTICES.md');
  yield LicenseEntryWithLineBreaks(
    const ['LabScale — bundled tools & models'],
    notices,
  );
}

class LabScaleApp extends StatelessWidget {
  const LabScaleApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // The scope sits above MaterialApp so every route — dialogs, the
    // full-window viewer — switches language together with the main page.
    return ValueListenableBuilder<S>(
      valueListenable: controller.language,
      builder: (context, strings, _) => LocaleScope(
        strings: strings,
        child: MaterialApp(
          title: 'LabScale',
          debugShowCheckedModeBanner: false,
          theme: buildLabScaleTheme(),
          home: HomePage(controller: controller),
        ),
      ),
    );
  }
}
