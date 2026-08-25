/// Progress + log plumbing shared by every pipeline stage.
library;

import 'dart:async';

/// A single line appended to the process log panel.
typedef LogSink = void Function(String message);

/// Fractional progress in `0.0..1.0`, or null when the stage is indeterminate.
typedef ProgressSink = void Function(double? fraction);

/// Collects log lines and progress for one processing job, and exposes them as
/// broadcast streams the UI can listen to.
class JobReporter {
  JobReporter();

  final _logController = StreamController<String>.broadcast();
  final _progressController = StreamController<double?>.broadcast();
  final List<String> _lines = [];

  Stream<String> get logs => _logController.stream;
  Stream<double?> get progress => _progressController.stream;

  /// Every line emitted so far, so late listeners can backfill the panel.
  List<String> get history => List.unmodifiable(_lines);

  bool _closed = false;

  void log(String message) {
    if (_closed) return;
    _lines.add(message);
    _logController.add(message);
  }

  void report(double? fraction) {
    if (_closed) return;
    _progressController.add(fraction);
  }

  /// Scales a stage's local `0..1` progress into an overall span, so a job made
  /// of several stages reports one continuous bar.
  ProgressSink stage(double start, double end) {
    return (fraction) {
      if (fraction == null) {
        report(null);
        return;
      }
      report(start + (end - start) * fraction.clamp(0.0, 1.0));
    };
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _logController.close();
    await _progressController.close();
  }
}

/// Raised when a stage fails; [detail] holds the tail of the tool's stderr.
class PipelineException implements Exception {
  PipelineException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message\n$detail';
}
