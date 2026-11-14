/// The upscale menu: three AI entries wherever AI runs, and Lanczos only
/// where it does not.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/binaries.dart';
import 'package:labscale/models/process_options.dart';
import 'package:labscale/state/app_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory models;
  late Directory cwd;
  late Directory originalCwd;

  setUp(() {
    models = Directory.systemTemp.createTempSync('offered_models_');
    for (final ext in ['param', 'bin']) {
      File(p.join(models.path, 'upscayl-lite-4x.$ext')).writeAsStringSync('');
    }
    Binaries.userModelsDir = models.path;
    // Only the weights written here may count: run away from the project's
    // bin/, whose contents depend on the machine (a Mac that ran
    // fetch_binaries.sh has realplksr there, a Windows checkout does not).
    originalCwd = Directory.current;
    cwd = Directory.systemTemp.createTempSync('offered_models_cwd_');
    Directory.current = cwd;
    Binaries.invalidate();
  });

  tearDown(() {
    Directory.current = originalCwd;
    Binaries.invalidate();
    Binaries.userModelsDir = null;
    models.deleteSync(recursive: true);
    cwd.deleteSync(recursive: true);
  });

  test('where AI runs, Lanczos is not offered', () {
    final controller = AppController.inState(
      capabilities: const Capabilities(ffmpeg: true, esrgan: true),
    );
    expect(controller.offeredModels, [
      UpscaleModel.ultramix,
      UpscaleModel.realesrganX4Plus,
      UpscaleModel.upscaylLite,
    ]);
  });

  test('a Lanczos selection moves to AI once AI becomes usable', () {
    // Refresh after fixing the driver: the dropdown stops listing Lanczos,
    // so it must not keep holding it as its value.
    final controller = AppController.inState(
      capabilities: const Capabilities(ffmpeg: true, esrgan: true),
      options: const ProcessOptions(upscaleModel: UpscaleModel.lanczos),
    );
    controller.reconcileModelAfterChange();
    expect(
        controller.offeredModels, contains(controller.options.upscaleModel));
    expect(controller.options.upscaleModel.isAi, isTrue);
  });

  test('a downloadable model stays selected until it is fetched', () {
    // A user mapped from a retired design model lands on Design with its
    // download button, not silently on Photo.
    final controller = AppController.inState(
      capabilities: const Capabilities(ffmpeg: true, esrgan: true),
      options: const ProcessOptions(upscaleModel: UpscaleModel.ultramix),
    );
    controller.reconcileModelAfterChange();
    expect(controller.options.upscaleModel, UpscaleModel.ultramix);
  });

  group('Photo: realplksr where its weights are, x4plus elsewhere', () {
    void installRealplksr() {
      for (final ext in ['param', 'bin']) {
        File(p.join(models.path, '4xBHI-realplksr-real.$ext'))
            .writeAsStringSync('');
      }
    }

    test('with realplksr installed (macOS), it stands in for x4plus', () {
      installRealplksr();
      final controller = AppController.inState(
        capabilities: const Capabilities(ffmpeg: true, esrgan: true),
      );
      expect(controller.offeredModels, [
        UpscaleModel.ultramix,
        UpscaleModel.realplksr,
        UpscaleModel.upscaylLite,
      ]);
    });

    test('without it (Windows), x4plus stays and realplksr is not listed', () {
      // It cannot be downloaded, so listing it would only show a dead entry.
      final controller = AppController.inState(
        capabilities: const Capabilities(ffmpeg: true, esrgan: true),
      );
      expect(controller.offeredModels, isNot(contains(UpscaleModel.realplksr)));
      expect(controller.offeredModels, contains(UpscaleModel.realesrganX4Plus));
    });

    test('a stored x4plus moves to realplksr once that is installed', () {
      // An upgrade from 2.2.x: the dropdown no longer lists x4plus there.
      installRealplksr();
      final controller = AppController.inState(
        capabilities: const Capabilities(ffmpeg: true, esrgan: true),
        options:
            const ProcessOptions(upscaleModel: UpscaleModel.realesrganX4Plus),
      );
      controller.reconcileModelAfterChange();
      expect(controller.options.upscaleModel, UpscaleModel.realplksr);
    });

    test('without a usable GPU the menu still has one Photo entry', () {
      installRealplksr();
      final controller = AppController.inState(
        capabilities: const Capabilities(ffmpeg: true),
      );
      final photo = controller.offeredModels.where((m) =>
          m == UpscaleModel.realplksr || m == UpscaleModel.realesrganX4Plus);
      expect(photo, hasLength(1));
    });
  });

  test('without a usable GPU, Lanczos is offered next to the greyed AI', () {
    // The AI entries stay visible so the Vulkan hint has something to explain.
    final controller = AppController.inState(
      capabilities: const Capabilities(ffmpeg: true),
    );
    expect(controller.offeredModels, contains(UpscaleModel.lanczos));
    expect(controller.offeredModels, contains(UpscaleModel.realesrganX4Plus));
  });
}
