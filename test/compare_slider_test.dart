/// The comparison divider: where it sits, and that the preview only offers it
/// once there is actually an "after" to show.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/pipeline.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/ui/widgets/compare_slider.dart';
import 'package:labscale/ui/widgets/preview_card.dart';

/// Reads back the clip the "before" side is drawn through.
double _revealedWidth(WidgetTester tester, {required double of}) {
  final clip = tester.widget<ClipRect>(
    find.byWidgetPredicate((w) => w is ClipRect && w.clipper != null),
  );
  return clip.clipper!.getClip(Size(of, 100)).width;
}

Future<void> _pumpSlider(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: CompareSlider(
              beforePath: '/tmp/before.png',
              afterPath: '/tmp/after.png',
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the divider starts halfway across', (tester) async {
    await _pumpSlider(tester);
    expect(_revealedWidth(tester, of: 200), closeTo(100, 0.01));
  });

  testWidgets('tapping moves the divider to that point', (tester) async {
    await _pumpSlider(tester);

    // The slider is centred in an 800x600 test surface, so its left edge sits
    // at x=300; tapping 40px in should reveal 40px of the "before" side.
    await tester.tapAt(const Offset(340, 300));
    await tester.pump();

    expect(_revealedWidth(tester, of: 200), closeTo(40, 0.01));
  });

  testWidgets('dragging past an edge clamps instead of overshooting',
      (tester) async {
    await _pumpSlider(tester);

    await tester.dragFrom(const Offset(400, 300), const Offset(-500, 0));
    await tester.pump();
    expect(_revealedWidth(tester, of: 200), 0);

    await tester.dragFrom(const Offset(400, 300), const Offset(500, 0));
    await tester.pump();
    expect(_revealedWidth(tester, of: 200), 200);
  });

  testWidgets('preview offers no comparison until a result exists',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewCard(
            file: MediaFile(
              path: '/tmp/a.png',
              sizeBytes: 10,
              isImage: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CompareSlider), findsNothing);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('a failed job is not offered as a comparison', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewCard(
            file: MediaFile(path: '/tmp/a.png', sizeBytes: 10, isImage: true),
            result: JobResult(
              sourceName: 'a.png',
              outputPath: '/tmp/never-written.png',
              error: 'meledak',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CompareSlider), findsNothing);
  });
}
