/// Invariants of the model list. It is presented as a fixed menu, so the
/// entries have to stay distinguishable and honest about what is installed.
library;

import 'package:flutter_test/flutter_test.dart';
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

  test('labels say what the model is for, not just its name', () {
    // The point of the rewrite: someone scanning the dropdown should be able
    // to pick without knowing what "ultramix" means.
    const purposes = ['Foto', 'Desain', 'Anime', 'Video', 'Cepat', 'Draf'];
    for (final m in UpscaleModel.values) {
      expect(purposes.any((p) => m.label.contains(p)), isTrue,
          reason: '${m.id}: "${m.label}" tidak menyebut peruntukannya');
    }
  });
}
