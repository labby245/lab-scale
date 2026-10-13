/// A plain-text log file kept across sessions, for bug reports.
///
/// The in-app log panel empties with every new batch, which is right for
/// watching a job and useless for answering "what went wrong yesterday". This
/// keeps the same lines, plus the environment they ran in, in one file the
/// user can attach to an issue.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class AppLog {
  AppLog(this.dir);

  final String dir;

  /// Past this the file is rotated to `.1`, keeping two files at most.
  static const int maxBytes = 2 * 1024 * 1024;

  String get path => p.join(dir, 'labscale.log');

  IOSink? _sink;

  /// Opens the file for appending, rotating it first when it has grown large.
  /// Failure leaves logging disabled; it never stops the app.
  void open() {
    try {
      Directory(dir).createSync(recursive: true);
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        file.renameSync('$path.1');
      }
      _sink = File(path).openWrite(mode: FileMode.append);
    } on FileSystemException {
      _sink = null;
    }
  }

  void write(String line) {
    final stamp = DateTime.now().toIso8601String().substring(0, 19);
    _sink?.writeln('$stamp  $line');
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
