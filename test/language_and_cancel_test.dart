/// The interface follows the chosen language everywhere, and a running batch
/// can always be stopped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/pipeline.dart';
import 'package:labscale/l10n/strings.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/state/app_controller.dart';
import 'package:labscale/ui/home_page.dart';
import 'package:labscale/ui/widgets/file_grid.dart';

MediaFile _file(String name) =>
    MediaFile(path: '/tmp/$name', sizeBytes: 2048, isImage: true);

Future<void> _pumpHome(
  WidgetTester tester,
  AppController controller, {
  S strings = S.id,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    LocaleScope(
      strings: strings,
      child: MaterialApp(home: HomePage(controller: controller)),
    ),
  );
}

void main() {
  test('first launch picks Indonesian for an Indonesian language or region', () {
    expect(S.forLocale('id_ID'), S.id);
    expect(S.forLocale('id'), S.id);
    expect(S.forLocale('en_ID'), S.id, reason: 'Mac berbahasa Inggris di Indonesia');
    expect(S.forLocale('en_US'), S.en);
    expect(S.forLocale('en-GB'), S.en);
    expect(S.forLocale('de_DE.UTF-8'), S.en);
    expect(S.forLocale('C'), S.en);
  });

  testWidgets('English shows English text', (tester) async {
    await _pumpHome(tester, AppController.inState(), strings: S.en);
    expect(find.text('Process Files'), findsOneWidget);
    expect(find.text('Choose Files'), findsOneWidget);
    expect(find.text('Proses File'), findsNothing);
  });

  testWidgets('a running batch offers Cancel, an idle one does not',
      (tester) async {
    await _pumpHome(
      tester,
      AppController.inState(
        files: [_file('a.png'), _file('b.png')],
        phase: JobPhase.running,
        activeIndex: 0,
      ),
      strings: S.en,
    );
    expect(find.text('Cancel'), findsOneWidget);

    await _pumpHome(tester, AppController.inState(files: [_file('a.png')]));
    expect(find.text('Batalkan'), findsNothing);
  });

  testWidgets('cancelled files say so on their tile', (tester) async {
    final controller = AppController.inState(
      files: [_file('a.png'), _file('b.png')],
      phase: JobPhase.done,
      results: [
        const JobResult(sourceName: 'a.png', outputPath: '/out/a.png'),
        const JobResult.cancelled('b.png'),
      ],
    );
    expect(controller.statusFor(1), FileStatus.cancelled);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 400,
            child: FileGrid(controller: controller),
          ),
        ),
      ),
    );
    expect(find.text('dibatalkan'), findsOneWidget);
    expect(controller.statusText(S.en), '1/2 processed · the rest cancelled');
  });
}
