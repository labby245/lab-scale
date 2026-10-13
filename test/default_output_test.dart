/// Results must not land in a folder the OS syncs to the cloud by default.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/state/app_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Windows uses the profile folder, not OneDrive Documents', () {
    final dir = defaultOutputDirFor(
      {'USERPROFILE': r'C:\Users\budi', 'HOME': '/ignored'},
      isWindows: true,
      documentsFallback: r'C:\Users\budi\OneDrive\Documents',
    );
    expect(dir, p.join(r'C:\Users\budi', 'LabScale'));
  });

  test('macOS uses the home folder, not iCloud-synced Documents', () {
    final dir = defaultOutputDirFor(
      {'HOME': '/Users/budi'},
      isWindows: false,
      documentsFallback: '/Users/budi/Documents',
    );
    expect(dir, p.join('/Users/budi', 'LabScale'));
  });

  test('falls back to Documents when no home is known', () {
    final dir = defaultOutputDirFor(
      const {},
      isWindows: true,
      documentsFallback: r'D:\Docs',
    );
    expect(dir, p.join(r'D:\Docs', 'LabScale'));
  });
}
