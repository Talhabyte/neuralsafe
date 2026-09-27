import 'dart:async';

import '../models/anomaly_result_log_entry.dart';
import '../models/risk_decision.dart';
import 'anomaly_evaluator.dart';
import 'danger_score_fusion_engine.dart';

/// Consumes an AnomalyResultLogEntry stream (normally
/// AnomalyResultNotifier.history), fuses each entry's behavioral score
/// through DangerScoreFusionEngine, and broadcasts the resulting
/// RiskDecision. Maintains state (latest decision) and exposes a
/// stream — performs NO side effects: no SMS, no GPS, no UI
/// notification, no persistence of its own, and no ML inference of
/// its own — text scores are computed elsewhere (TextAnalysisService)
/// and only handed in via submitTextScore().
///
/// 'voice' is always passed as null to the fusion engine, since no
/// such module exists yet in this codebase. 'behavior' is fed from
/// the anomaly stream, and 'text' is fed from submitTextScore(),
/// called by whatever owns the message-capture flow. Both are cached
/// so either input can trigger a fresh fused RiskDecision using the
/// other's most recent value.
///
/// A cold-start AnomalyResult (baseline not yet warm) is deliberately
/// passed to the fusion engine as a null behavior score, not as 0 —
/// this avoids a cold-start baseline (which has no real statistical
/// meaning yet) being misread as "definitely normal behavior" by
/// anything consuming RiskDecision later; instead it correctly
/// produces a neutral, zero-weight FusionResult.
class RiskDecisionEngine {
  RiskDecisionEngine({
    required Stream<AnomalyResultLogEntry> anomalyStream,
    DangerScoreFusionEngine? fusionEngine,
  })  : _anomalyStream = anomalyStream,
        _fusionEngine = fusionEngine ?? const DangerScoreFusionEngine(),
        _controller = StreamController<RiskDecision>.broadcast();

  final Stream<AnomalyResultLogEntry> _anomalyStream;
  final DangerScoreFusionEngine _fusionEngine;
  final StreamController<RiskDecision> _controller;

  StreamSubscription<AnomalyResultLogEntry>? _subscription;

  bool get isRunning => _subscription != null;

  RiskDecision? _latest;
  RiskDecision? get latest => _latest;

  double? _latestBehaviorScore;
  double? _latestTextScore;

  Stream<RiskDecision> get decisions => _controller.stream;

  /// Starts listening. Idempotent — a second call while already
  /// running is a no-op, so no duplicate subscriptions are created.
  void start() {
    if (_subscription != null) return;
    _subscription = _anomalyStream.listen(_handleAnomalyEntry);
  }

  /// Stops listening and releases the subscription. Safe to call even
  /// if not currently running.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Permanently closes the decisions stream. Call stop() first if
  /// currently running.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Records a fresh TextScore (0-100, from TextAnalysisService, via
  /// whatever owns the message-capture flow) and immediately emits a
  /// new RiskDecision fusing it with the most recent behavior score.
  /// This method performs no inference and no I/O itself — the caller
  /// is responsible for having already computed [score].
  void submitTextScore(
    double score, {
    DateTime? evaluatedAt,
    String windowKey = 'text-event',
  }) {
    _latestTextScore = score;
    _emitDecision(
      evaluatedAt: evaluatedAt ?? DateTime.now(),
      windowKey: windowKey,
    );
  }

  void _handleAnomalyEntry(AnomalyResultLogEntry entry) {
    _latestBehaviorScore = entry.result.status == AnomalyStatus.evaluated
        ? entry.result.aggregateScore
        : null;

    _emitDecision(
      evaluatedAt: entry.evaluatedAt,
      windowKey: entry.windowKey,
    );
  }

  void _emitDecision(
      {required DateTime evaluatedAt, required String windowKey}) {
    final fusionResult = _fusionEngine.fuse({
      'voice': null,
      'text': _latestTextScore,
      'behavior': _latestBehaviorScore,
    });

    final decision = RiskDecision(
      riskTier: fusionResult.riskTier,
      fusionResult: fusionResult,
      evaluatedAt: evaluatedAt,
      windowKey: windowKey,
    );

    _latest = decision;
    if (!_controller.isClosed) {
      _controller.add(decision);
    }
  }
}
