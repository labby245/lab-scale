/// Invariants of the model list. It is presented as a fixed menu, so the
/// entries have to stay distinguishable and honest about what is installed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/model_store.dart';
import 'package:labscale/l10n/strings.dart';
import 'package:labscale/models/process_options.dart';

void main() {
  test('ids are unique — preferences are stored by id', () {
    final ids = UpscaleModel.values.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('suffixes are unique — two models must not collide in a filename', () {
    final suffixes = UpscaleModel.values.map((m) => m.suffix).toList();
    expect(suffixes.toSet().length, suffixes.length);
  });

  test('every AI entry names an ncnn model, Lanczos names none', () {
    for (final m in UpscaleModel.values) {
      expect(m.isAi, m != UpscaleModel.lanczos, reason: m.id);
      if (m.isAi) expect(m.ncnnName, isNotEmpty, reason: m.id);
    }
  });

  test('an unknown stored id falls back to Lanczos rather than throwing', () {
    // Downgrading the app, or a hand-edited preference, must not wedge it.
    expect(UpscaleModel.fromId('model-yang-sudah-tidak-ada'),
        UpscaleModel.lanczos);
    expect(UpscaleModel.fromId(null), UpscaleModel.lanczos);
  });

  test('a model retired in 2.2.0 maps to the entry doing its job', () {
    // Otherwise a stored choice would fall back to Lanczos, which is hidden
    // wherever AI runs.
    expect(UpscaleModel.fromId('ultrasharp-4x'), UpscaleModel.ultramix);
    expect(
        UpscaleModel.fromId('realesrgan-x4plus-anime'), UpscaleModel.ultramix);
    expect(UpscaleModel.fromId('remacri-4x'), UpscaleModel.realesrganX4Plus);
    expect(
        UpscaleModel.fromId('realesr-animevideov3'), UpscaleModel.upscaylLite);
  });

  test('labels say what the model is for, not just its name', () {
    // The point of the rewrite: someone scanning the dropdown should be able
    // to pick without knowing what "ultramix" means — in either language.
    const purposes = {
      S.id: ['Foto', 'Desain', 'Video', 'Tanpa AI'],
      S.en: ['Photo', 'Design', 'Video', 'No AI'],
    };
    purposes.forEach((s, words) {
      for (final m in UpscaleModel.values) {
        final label = s.modelLabel(m);
        expect(words.any(label.contains), isTrue,
            reason: '${s.code} ${m.id}: "$label" tidak menyebut peruntukannya');
      }
    });
  });

  test('a superseding model replaces an AI model and is never a download', () {
    // It is listed only where its weights already are; a download offer
    // would put it on a machine whose binary cannot run it.
    for (final m in UpscaleModel.values) {
      final old = m.supersedes;
      if (old == null) continue;
      expect(m.isAi && old.isAi, isTrue, reason: m.id);
      expect(old.supersedes, isNull, reason: 'no chains: ${m.id}');
      expect(downloadableFor(m), isNull, reason: m.id);
    }
  });

  test('superseding weights ship in the macOS installer, the old ones in all',
      () {
    final entries = File('tools/bundled_models.txt')
        .readAsLinesSync()
        .map((l) => l.split('#').first.trim())
        .where((l) => l.isNotEmpty)
        .toSet();
    for (final m in UpscaleModel.values) {
      if (m.supersedes == null) continue;
      expect(entries, contains('macos:${m.ncnnName}'), reason: m.id);
      expect(entries, contains(m.supersedes!.ncnnName), reason: m.id);
    }
  });

  test('every downloadable model is pinned and credited', () {
    for (final entry in kDownloadableModels) {
      expect(entry.model.isAi, isTrue, reason: entry.model.id);
      expect(entry.author, isNotEmpty);
      expect(entry.licenseUrl, startsWith('https://'));
      final names = entry.files.map((f) => f.name).toSet();
      // The upscaler needs the pair; one without the other is unusable.
      expect(names, {
        '${entry.model.ncnnName}.param',
        '${entry.model.ncnnName}.bin',
      });
      for (final file in entry.files) {
        expect(file.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        // Pinned to a commit, never a branch that can move under the hash.
        expect(file.url, isNot(contains('/main/')));
        expect(file.sizeBytes, greaterThan(0));
      }
    }
  });
}
