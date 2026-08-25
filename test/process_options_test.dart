import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/models/process_options.dart';

void main() {
  group('ProcessOptions.hasAnyOp', () {
    test('is false when nothing is enabled', () {
      const options = ProcessOptions();
      expect(options.hasAnyOp, isFalse);
    });

    test('is true for upscale alone', () {
      const options = ProcessOptions(upscale: true);
      expect(options.hasAnyOp, isTrue);
    });

    test('is true for fps boost alone', () {
      const options = ProcessOptions(fpsBoost: true);
      expect(options.hasAnyOp, isTrue);
    });
  });

  group('routing decisions', () {
    test('lanczos upscale stays on the direct FFmpeg path', () {
      const options = ProcessOptions(
        upscale: true,
        upscaleModel: UpscaleModel.lanczos,
        upscaleScale: 2,
      );
      expect(options.useEsrgan, isFalse);
      expect(options.needsFrames, isFalse);
      expect(options.lanczosScale, 2);
    });

    test('AI upscale forces the frame path and drops the lanczos filter', () {
      const options = ProcessOptions(
        upscale: true,
        upscaleModel: UpscaleModel.realesrganX4Plus,
        upscaleScale: 2,
      );
      expect(options.useEsrgan, isTrue);
      expect(options.needsFrames, isTrue);
      expect(options.lanczosScale, isNull);
    });

    test('scale 1 produces no lanczos filter', () {
      const options = ProcessOptions(upscale: true, upscaleScale: 1);
      expect(options.lanczosScale, isNull);
    });

    test('RIFE forces the frame path, FFmpeg interpolation does not', () {
      const rife = ProcessOptions(
        fpsBoost: true,
        interpEngine: InterpEngine.rife,
      );
      expect(rife.useRife, isTrue);
      expect(rife.needsFrames, isTrue);

      const ffmpeg = ProcessOptions(
        fpsBoost: true,
        interpEngine: InterpEngine.ffmpeg,
      );
      expect(ffmpeg.useRife, isFalse);
      expect(ffmpeg.needsFrames, isFalse);
    });

    test('RIFE only engages when the fps boost is actually on', () {
      const options = ProcessOptions(interpEngine: InterpEngine.rife);
      expect(options.useRife, isFalse);
      expect(options.needsFrames, isFalse);
    });
  });

  group('effectiveSharpness', () {
    test('is zero when upscale is off, however the slider is set', () {
      // Regression: the slider only exists under the Upscale section and the
      // filename only records sharpness when upscale is on, so an
      // FPS-boost-only job used to get an invisible, unrecorded unsharp mask.
      const options = ProcessOptions(fpsBoost: true, sharpness: 0.8);
      expect(options.effectiveSharpness, 0.0);
      expect(options.outputSuffix(), '_60fps');
    });

    test('passes the slider through when upscale is on', () {
      const options = ProcessOptions(upscale: true, sharpness: 0.8);
      expect(options.effectiveSharpness, 0.8);
      expect(options.outputSuffix(), contains('sharp80'));
    });
  });

  group('outputSuffix', () {
    test('falls back to _processed when no op is selected', () {
      expect(const ProcessOptions().outputSuffix(), '_processed');
    });

    test('describes model, scale, sharpness and fps', () {
      const options = ProcessOptions(
        upscale: true,
        upscaleModel: UpscaleModel.realesrganX4Plus,
        upscaleScale: 2,
        sharpness: 0.3,
        fpsBoost: true,
      );
      expect(options.outputSuffix(), '_esrgan-real-2x_sharp30_60fps');
    });

    test('omits sharpness when it is zero', () {
      const options = ProcessOptions(
        upscale: true,
        upscaleScale: 4,
        sharpness: 0,
      );
      expect(options.outputSuffix(), '_lanczos-4x');
    });
  });

  group('copyWith', () {
    test('returns a new instance and leaves the original untouched', () {
      const original = ProcessOptions();
      final updated = original.copyWith(upscale: true, upscaleScale: 4);

      expect(original.upscale, isFalse);
      expect(original.upscaleScale, 2);
      expect(updated.upscale, isTrue);
      expect(updated.upscaleScale, 4);
    });
  });

  group('enum id round-tripping', () {
    test('unknown ids fall back to safe defaults', () {
      expect(UpscaleModel.fromId('nope'), UpscaleModel.lanczos);
      expect(InterpEngine.fromId(null), InterpEngine.ffmpeg);
      expect(Quality.fromId('nope'), Quality.ultra);
      expect(VideoCodec.fromId(null), VideoCodec.h264);
    });

    test('known ids resolve back to their enum value', () {
      for (final model in UpscaleModel.values) {
        expect(UpscaleModel.fromId(model.id), model);
      }
      for (final quality in Quality.values) {
        expect(Quality.fromId(quality.id), quality);
      }
      for (final codec in VideoCodec.values) {
        expect(VideoCodec.fromId(codec.id), codec);
      }
    });
  });
}
