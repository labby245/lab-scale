/// Where results land: a dropped folder keeps its own, and a file picked on
/// its own goes to the root.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/models/media_file.dart';

void main() {
  test('a file picked on its own lands in the output root', () {
    const file = MediaFile(path: '/in/a.png', sizeBytes: 1, isImage: true);
    expect(file.destinationDir('/out'), '/out');
  });

  test('a file from a dropped folder lands in <folder>_upscaled', () {
    const file = MediaFile(
      path: '/in/Foto Liburan/a.png',
      sizeBytes: 1,
      isImage: true,
      sourceRoot: '/in/Foto Liburan',
    );
    expect(file.destinationDir('/out'), '/out/Foto Liburan_upscaled');
  });

  test('nested folders flatten into the one destination', () {
    // "dalam 1 folder" — a folder's results stay together whatever its
    // internal structure, rather than rebuilding the tree.
    const deep = MediaFile(
      path: '/in/Trip/hari-2/sore/a.png',
      sizeBytes: 1,
      isImage: true,
      sourceRoot: '/in/Trip',
    );
    const shallow = MediaFile(
      path: '/in/Trip/b.png',
      sizeBytes: 1,
      isImage: true,
      sourceRoot: '/in/Trip',
    );
    expect(deep.destinationDir('/out'), shallow.destinationDir('/out'));
  });

  test('a trailing separator does not produce an empty folder name', () {
    const file = MediaFile(
      path: '/in/Trip/a.png',
      sizeBytes: 1,
      isImage: true,
      sourceRoot: '/in/Trip/',
    );
    expect(file.destinationDir('/out'), '/out/Trip_upscaled');
  });
}
