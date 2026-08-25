/// The full-window viewer, which exists because a preview pane inside the
/// workspace is too small to judge an upscale.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/state/app_controller.dart';
import 'package:labscale/ui/compare_view.dart';
import 'package:labscale/ui/widgets/file_grid.dart';

MediaFile _file(String name) =>
    MediaFile(path: '/tmp/$name', sizeBytes: 2048, isImage: true);

Future<void> _pumpViewer(
  WidgetTester tester,
  AppController controller, {
  int at = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CompareView(controller: controller, initialIndex: at),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the file it was opened on, and where it sits in the queue',
      (tester) async {
    await _pumpViewer(
      tester,
      AppController.inState(files: [_file('a.png'), _file('b.png'), _file('c.png')]),
      at: 1,
    );

    expect(find.text('b.png'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('arrow keys step through the batch and wrap around',
      (tester) async {
    await _pumpViewer(
      tester,
      AppController.inState(files: [_file('a.png'), _file('b.png')]),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('b.png'), findsOneWidget);

    // Wrapping is what makes holding the key sweep the whole batch.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('a.png'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('b.png'), findsOneWidget);
  });

  testWidgets('a lone file offers no stepping controls', (tester) async {
    await _pumpViewer(tester, AppController.inState(files: [_file('a.png')]));

    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.text('1/1'), findsNothing);
  });

  testWidgets('an unprocessed file says so instead of implying a comparison',
      (tester) async {
    await _pumpViewer(tester, AppController.inState(files: [_file('a.png')]));

    expect(find.textContaining('Belum diproses'), findsOneWidget);
  });

  testWidgets('tapping a tile opens the viewer', (tester) async {
    final controller = AppController.inState(
      files: [_file('a.png'), _file('b.png')],
    );

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

    expect(find.byType(CompareView), findsNothing);

    await tester.tap(find.text('b.png'));
    await tester.pumpAndSettle();

    expect(find.byType(CompareView), findsOneWidget);
    expect(controller.previewFile?.path, '/tmp/b.png');
  });

  testWidgets('Escape closes the viewer', (tester) async {
    final controller = AppController.inState(files: [_file('a.png')]);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openCompareView(context, controller, _file('a.png')),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    expect(find.byType(CompareView), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CompareView), findsNothing);
  });

  testWidgets('clearing the selection dismisses the viewer', (tester) async {
    final controller = AppController.inState(files: [_file('a.png')]);
    await _pumpViewer(tester, controller);
    expect(find.byType(CompareView), findsOneWidget);

    controller.clearSelection();
    await tester.pumpAndSettle();

    expect(find.text('a.png'), findsNothing);
  });
}
