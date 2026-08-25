/// The grid's whole job is to say, at a glance, where each file stands. These
/// pin that down state by state — the running tile especially, which is the
/// one thing a batch is watched for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/pipeline.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/state/app_controller.dart';
import 'package:labscale/ui/widgets/file_grid.dart';

MediaFile _file(String name, {bool image = true}) =>
    MediaFile(path: '/tmp/$name', sizeBytes: 2048, isImage: image);

JobResult _ok(String name) =>
    JobResult(sourceName: name, outputPath: '/out/$name');

JobResult _bad(String name) =>
    JobResult(sourceName: name, outputPath: '', error: 'meledak');

Future<void> _pump(WidgetTester tester, AppController controller) async {
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
}

void main() {
  testWidgets('queued files show their size and no progress bar', (tester) async {
    await _pump(
      tester,
      AppController.inState(files: [_file('a.png'), _file('b.png')]),
    );

    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('b.png'), findsOneWidget);
    expect(find.text('2 KB'), findsNWidgets(2));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('the running file gets the progress bar and a percentage',
      (tester) async {
    await _pump(
      tester,
      AppController.inState(
        files: [_file('a.png'), _file('b.png'), _file('c.png')],
        phase: JobPhase.running,
        activeIndex: 1,
        fileProgress: 0.42,
      ),
    );

    // Exactly one tile is running, so exactly one bar and one percentage.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('memproses…'), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.42, 0.001));
  });

  testWidgets('a stage with no measurable progress leaves the bar indeterminate',
      (tester) async {
    await _pump(
      tester,
      AppController.inState(
        files: [_file('a.png')],
        phase: JobPhase.running,
        activeIndex: 0,
      ),
    );

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('finished files read as done or failed, in queue order',
      (tester) async {
    await _pump(
      tester,
      AppController.inState(
        files: [_file('a.png'), _file('b.png'), _file('c.png')],
        phase: JobPhase.running,
        activeIndex: 2,
        results: [_ok('a.png'), _bad('b.png')],
      ),
    );

    expect(find.text('selesai'), findsOneWidget);
    expect(find.text('gagal'), findsOneWidget);
    expect(find.text('memproses…'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
  });

  testWidgets('remove buttons are offered while idle and withdrawn mid-run',
      (tester) async {
    await _pump(tester, AppController.inState(files: [_file('a.png')]));
    expect(find.byIcon(Icons.close), findsOneWidget);

    await _pump(
      tester,
      AppController.inState(
        files: [_file('a.png')],
        phase: JobPhase.running,
        activeIndex: 0,
      ),
    );
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('tapping a tile hands that file to the preview', (tester) async {
    final controller = AppController.inState(
      files: [_file('a.png'), _file('b.png')],
    );
    await _pump(tester, controller);

    await tester.tap(find.text('b.png'));
    await tester.pump();

    expect(controller.previewFile?.path, '/tmp/b.png');
  });
}
