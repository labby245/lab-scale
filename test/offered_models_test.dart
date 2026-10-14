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

  setUp(() {
    models = Directory.systemTemp.createTempSync('offered_models_');
    for (final ext in ['param', 'bin']) {
      File(p.join(models.path, 'upscayl-lite-4x.$ext')).writeAsStringSync('');
    }
    Binaries.userModelsDir = models.path;
  });

  tearDown(() {
    Binaries.userModelsDir = null;
    models.deleteSync(recursive: true);
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

  test('without a usable GPU, Lanczos is offered next to the greyed AI', () {
    // The AI entries stay visible so the Vulkan hint has something to explain.
    final controller = AppController.inState(
      capabilities: const Capabilities(ffmpeg: true),
    );
    expect(controller.offeredModels, contains(UpscaleModel.lanczos));
    expect(controller.offeredModels, contains(UpscaleModel.realesrganX4Plus));
  });
}
