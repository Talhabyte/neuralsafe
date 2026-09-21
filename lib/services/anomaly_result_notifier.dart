import 'dart:async';

import '../models/anomaly_result_log_entry.dart';
import '../services/anomaly_evaluator.dart';
import 'anomaly_result_repository.dart';

/// Consumes AnomalyResult outputs, persists them, and exposes the
/// latest result and a stream of history — WITHOUT any threshold
/// comparison or alert-triggering logic. This is deliberately neutral
/// plumbing: "here is what was evaluated and when," not "here is
/// whether something is wrong." Threshold/alert decision logic is
/// explicitly out of scope for this step and is reserved for a later,
/// separately-approved Phase 5 fusion/alerting layer.
///
/// [saveEntry] is injectable (defaults to
/// AnomalyResultRepository().save) so this can be unit tested without
/// the encrypted vault.
class AnomalyResultNotifier {
  AnomalyResultNotifier({
    Future<void> Function(
      AnomalyResult result, {
      required DateTime evaluatedAt,
      required String windowKey,
    })? saveEntry,
    DateTime Function()? clock,
  })  : _saveEntry = saveEntry ?? AnomalyResultRepository().save,
        _clock = clock ?? DateTime.now,
        _controller = StreamController<AnomalyResultLogEntry>.broadcast();

  final Future<void> Function(
    AnomalyResult result, {
    required DateTime evaluatedAt,
    required String windowKey,
  }) _saveEntry;
  final DateTime Function() _clock;
  final StreamController<AnomalyResultLogEntry> _controller;

  AnomalyResultLogEntry? _latest;

  /// The most recent entry recorded via [record], or null if none yet.
  AnomalyResultLogEntry? get latest => _latest;

  /// Broadcast stream of every recorded entry, in the order recorded.
  Stream<AnomalyResultLogEntry> get history => _controller.stream;

  /// Records a new AnomalyResult: persists it via [saveEntry], updates
  /// [latest], and emits it on [history]. Performs NO comparison
  /// against any threshold and takes NO action based on the result's
  /// status or score beyond storing and exposing it as-is.
  Future<void> record(AnomalyResult result, {required String windowKey}) async {
    final evaluatedAt = _clock();

    await _saveEntry(result, evaluatedAt: evaluatedAt, windowKey: windowKey);

    final entry = AnomalyResultLogEntry(
      evaluatedAt: evaluatedAt,
      windowKey: windowKey,
      result: result,
    );

    _latest = entry;
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
  }

  /// Permanently closes the history stream.
  Future<void> dispose() async {
    await _controller.close();
  }
}
