/// Regressions caught by code review: adding files used to replace the queue,
/// and a file whose job threw left the rest of the batch drawn as queued.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/pipeline.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/state/app_controller.dart';

MediaFile _f(String name) =>
    MediaFile(path: '/tmp/$name', sizeBytes: 1, isImage: true);

JobResult _ok(String n) => JobResult(sourceName: n, outputPath: '/out/$n');
JobResult _bad(String n) =>
    JobResult(sourceName: n, outputPath: '', error: 'meledak');

void main() {
  group('status per file', () {
    test('a failed result reads as failed, not stuck queued', () {
      final c = AppController.inState(
        files: [_f('a'), _f('b'), _f('c')],
        phase: JobPhase.done,
        results: [_ok('a'), _bad('b'), _ok('c')],
      );
      expect(c.statusFor(0), FileStatus.done);
      expect(c.statusFor(1), FileStatus.failed);
      expect(c.statusFor(2), FileStatus.done);
    });

    test('files past the end of the results list are still queued', () {
      final c = AppController.inState(
        files: [_f('a'), _f('b')],
        phase: JobPhase.running,
        activeIndex: 1,
        results: [_ok('a')],
      );
      expect(c.statusFor(0), FileStatus.done);
      expect(c.statusFor(1), FileStatus.running);
    });
  });

  group('resultForFile', () {
    test('matches by path, not identity', () {
      final c = AppController.inState(
        files: [_f('a'), _f('b')],
        results: [_ok('a'), _bad('b')],
      );
      // A rebuilt MediaFile for the same path must still find its result.
      expect(c.resultForFile(_f('b'))?.isSuccess, isFalse);
      expect(c.resultForFile(_f('a'))?.outputPath, '/out/a');
      expect(c.resultForFile(_f('tidak-ada')), isNull);
    });
  });

  group('selection', () {
    test('removeAt drops only that file', () {
      final c = AppController.inState(files: [_f('a'), _f('b'), _f('c')]);
      c.removeAt(1);
      expect(c.files.map((f) => f.displayName), ['a', 'c']);
    });

    test('removeAt ignores an out-of-range index', () {
      final c = AppController.inState(files: [_f('a')]);
      c.removeAt(5);
      c.removeAt(-1);
      expect(c.files.length, 1);
    });

    test('selecting the same file twice closes the preview', () {
      final c = AppController.inState(files: [_f('a')]);
      c.selectForPreview(_f('a'));
      expect(c.previewFile?.path, '/tmp/a');
      c.selectForPreview(_f('a'));
      expect(c.previewFile, isNull);
    });
  });
}
