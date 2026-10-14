/// Asking a 4x-only network for `-s 2` does not fail — the tool mis-stitches
/// its tiles and leaves a seam every 400 output pixels. Measured on a real
/// 736x1040 source: seam strength 39.6 at x=400 with `-s 2`, versus 9.1 when
/// the model runs at 4x and FFmpeg resizes down.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/esrgan_runner.dart';
import 'package:labscale/models/process_options.dart';

void main() {
  test('every AI model ships 4x weights only', () {
    for (final m in UpscaleModel.values.where((m) => m.isAi)) {
      expect(m.nativeScales, {4}, reason: m.id);
    }
  });

  test('Lanczos claims no ncnn weights at all', () {
    // It never reaches the tool, so answering "{4}" would be a lie that a
    // future caller could act on.
    expect(UpscaleModel.lanczos.nativeScales, isEmpty);
    expect(EsrganRunner.ncnnScaleFor(UpscaleModel.lanczos, 2), 2);
  });

  test('a 4x-only model is always run at 4x, whatever was asked', () {
    for (final scale in [1, 2, 3, 4]) {
      expect(EsrganRunner.ncnnScaleFor(UpscaleModel.ultramix, scale), 4,
          reason: 'skala $scale');
      expect(EsrganRunner.ncnnScaleFor(UpscaleModel.realesrganX4Plus, scale), 4,
          reason: 'skala $scale');
    }
  });

  test('the -s that reaches the process is the model scale, not the request',
      () {
    // The output of a wrong -s comes back at exactly the requested size, so
    // asserting on the result cannot catch this. Only the argv can.
    String scaleArg(UpscaleModel m, int requested) {
      final args = EsrganRunner.buildArgs(
        inputPath: 'in',
        outputPath: 'out',
        model: m,
        requestedScale: requested,
      );
      return args[args.indexOf('-s') + 1];
    }

    expect(scaleArg(UpscaleModel.ultramix, 2), '4');
    expect(scaleArg(UpscaleModel.upscaylLite, 3), '4');
    expect(scaleArg(UpscaleModel.realesrganX4Plus, 1), '4');
  });

  test('the models directory is only passed when there is one', () {
    final without = EsrganRunner.buildArgs(
      inputPath: 'in',
      outputPath: 'out',
      model: UpscaleModel.ultramix,
      requestedScale: 4,
    );
    expect(without.contains('-m'), isFalse);

    final with_ = EsrganRunner.buildArgs(
      inputPath: 'in',
      outputPath: 'out',
      model: UpscaleModel.ultramix,
      requestedScale: 4,
      modelsDir: '/bin/models',
    );
    expect(with_[with_.indexOf('-m') + 1], '/bin/models');
  });

  test('a model that topped out below 4x would be asked for its own maximum',
      () {
    // Guards the fallback: it must come off the model, not a literal 4.
    final withWeights =
        UpscaleModel.values.where((m) => m.nativeScales.isNotEmpty);
    for (final m in withWeights) {
      final widest = m.nativeScales.reduce((a, b) => a > b ? a : b);
      expect(EsrganRunner.ncnnScaleFor(m, 99), widest, reason: m.id);
    }
  });

  test('post-resize is required exactly when the model ran at a wider scale',
      () {
    expect(EsrganRunner.needsPostResize(UpscaleModel.ultramix, 2), isTrue);
    expect(EsrganRunner.needsPostResize(UpscaleModel.ultramix, 4), isFalse);
    expect(EsrganRunner.needsPostResize(UpscaleModel.realesrganX4Plus, 1),
        isTrue);
  });

  test('needsPostResize never disagrees with ncnnScaleFor', () {
    // The invariant the two are written to share; a future edit to one must
    // not be able to desynchronise them.
    for (final m in UpscaleModel.values) {
      for (final s in [1, 2, 3, 4]) {
        expect(
          EsrganRunner.needsPostResize(m, s),
          EsrganRunner.ncnnScaleFor(m, s) != s,
          reason: '${m.id} @ ${s}x',
        );
      }
    }
  });
}
