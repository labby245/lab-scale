/// The log panel must show a job to its end — its last lines are the ones
/// that say whether it worked.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/binaries.dart';
import 'package:labscale/l10n/strings.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/models/process_options.dart';
import 'package:labscale/state/app_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  test("a run's final log line reaches the panel", () async {
    final ffmpeg = Binaries.resolve(Tool.ffmpeg);
    // The image path probes with ffprobe before it touches ffmpeg.
    if (ffmpeg == null || Binaries.resolve(Tool.ffprobe) == null) {
      return markTestSkipped('ffmpeg/ffprobe tidak terpasang');
    }

    final work = Directory.systemTemp.createTempSync('labscale_log_');
    addTearDown(() => work.deleteSync(recursive: true));
    final still = p.join(work.path, 'a.png');
    final made = await Process.run(ffmpeg, [
      '-y', '-hide_banner', '-loglevel', 'error',
      '-f', 'lavfi', '-i', 'testsrc2=size=64x48', '-frames:v', '1', still,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    final controller = AppController.inState(
      files: [MediaFile.tryFrom(still)!],
      capabilities: const Capabilities(ffmpeg: true),
      options: const ProcessOptions(upscale: true, upscaleScale: 2),
      outputDir: p.join(work.path, 'out'),
      tempDir: p.join(work.path, 'tmp'),
    );
    await controller.run();

    expect(controller.results.single.isSuccess, isTrue,
        reason: controller.results.single.error);
    // Regression: the subscription was cancelled before the queued lines
    // were delivered, so this one never arrived.
    expect(controller.logLines.last, S.current.logImageSaved);
  });
}
