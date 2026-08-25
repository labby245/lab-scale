/// The 60 FPS row used to disappear whenever the selection held no video,
/// which reads as the app having lost a feature it advertises in its own
/// subtitle. It must stay on screen and explain itself instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/state/app_controller.dart';
import 'package:labscale/ui/widgets/ops_card.dart';

MediaFile _photo() =>
    const MediaFile(path: '/tmp/a.png', sizeBytes: 10, isImage: true);
MediaFile _clip() =>
    const MediaFile(path: '/tmp/a.mp4', sizeBytes: 10, isImage: false);

Future<void> _pump(WidgetTester tester, AppController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: OpsCard(controller: controller)),
      ),
    ),
  );
}

/// The FPS switch is the second one in the card; the first is Upscale.
Switch _fpsSwitch(WidgetTester tester) =>
    tester.widgetList<Switch>(find.byType(Switch)).elementAt(1);

void main() {
  testWidgets('the 60 FPS row is shown even with nothing selected',
      (tester) async {
    await _pump(tester, AppController.inState());

    expect(find.text('Boost ke 60 FPS'), findsOneWidget);
    expect(_fpsSwitch(tester).onChanged, isNull);
    expect(find.textContaining('pilih klip dulu'), findsOneWidget);
  });

  testWidgets('a photo-only selection says so rather than hiding the row',
      (tester) async {
    await _pump(tester, AppController.inState(files: [_photo()]));

    expect(find.text('Boost ke 60 FPS'), findsOneWidget);
    expect(_fpsSwitch(tester).onChanged, isNull);
    expect(find.textContaining('foto semua'), findsOneWidget);
  });

  testWidgets('a video in the selection arms the row', (tester) async {
    await _pump(tester, AppController.inState(files: [_photo(), _clip()]));

    expect(_fpsSwitch(tester).onChanged, isNotNull);
    expect(find.textContaining('Hanya untuk video'), findsNothing);
    // RIFE is absent in this bare controller, so the row must promise the
    // FFmpeg fallback rather than AI interpolation.
    expect(find.textContaining('minterpolate'), findsOneWidget);
  });
}
