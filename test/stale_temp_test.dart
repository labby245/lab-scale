/// Frames from a job cut short by a crash or force quit must not stay in the
/// temp folder forever — but a live job must never be swept away.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/pipeline.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('labscale_sweep_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Directory make(String name) =>
      Directory(p.join(temp.path, name))..createSync();

  test("old LabScale work folders go; other apps' folders stay", () {
    final frames = make('labscale_abc');
    File(p.join(frames.path, 'frame_000001.png')).writeAsStringSync('x');
    final probe = make('gpu_probe_abc');
    final foreign = make('someone_else');

    // "Now" is a day ahead, so everything created above counts as a day old.
    final removed = Pipeline.cleanStaleWorkDirs(
      temp.path,
      now: DateTime.now().add(const Duration(days: 1)),
    );
    expect(removed, 2);
    expect(frames.existsSync(), isFalse);
    expect(probe.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue, reason: 'bukan folder milik LabScale');
  });

  test('a folder touched recently is left alone', () {
    final live = make('labscale_live');
    expect(Pipeline.cleanStaleWorkDirs(temp.path), 0);
    expect(live.existsSync(), isTrue);
  });

  test('a missing temp folder is not an error', () {
    expect(Pipeline.cleanStaleWorkDirs(p.join(temp.path, 'nope')), 0);
  });
}
