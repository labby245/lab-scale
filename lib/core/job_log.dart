/// Progress + log plumbing shared by every pipeline stage.
library;

import 'dart:async';
import 'dart:io';

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

  /// Tools running on this job's behalf, so [cancel] can stop them.
  final Set<Process> _processes = {};
  bool _cancelled = false;

  /// True once the user has asked for this job to stop.
  bool get isCancelled => _cancelled;

  /// Registers a running tool so [cancel] can kill it. Returns [process].
  ///
  /// A process started after [cancel] — a stage that was already between
  /// awaits when the request landed — is killed on the spot rather than left
  /// to run to completion unwatched.
  Process track(Process process) {
    if (_cancelled) {
      process.kill(ProcessSignal.sigkill);
      return process;
    }
    _processes.add(process);
    unawaited(process.exitCode.whenComplete(() => _processes.remove(process)));
    return process;
  }

  /// Stops the job: every tracked tool is killed, and the stage waiting on it
  /// turns the resulting non-zero exit into [JobCancelled] via
  /// [throwIfCancelled].
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final process in _processes.toList()) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// Throws [JobCancelled] when [cancel] has been called. Stages call this
  /// right after a tool exits, before reading its exit code — a killed tool
  /// exits non-zero, and reporting that as a failure would be wrong.
  void throwIfCancelled() {
    if (_cancelled) throw const JobCancelled();
  }

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

/// Raised inside the pipeline when the user cancelled the job.
class JobCancelled implements Exception {
  const JobCancelled();

  @override
  String toString() => 'cancelled';
}
