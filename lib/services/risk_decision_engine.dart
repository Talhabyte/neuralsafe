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
/// notification, no persistence of its own.
///
/// Only the 'behavior' module is currently fed a real score (from
/// AnomalyResult.aggregateScore). 'voice' and 'text' are always passed
/// as null to the fusion engine, since no such modules exist yet in
/// this codebase — DangerScoreFusionEngine's renormalization means
/// this is equivalent to a pure behavior-only score today, while the
/// architecture is already correct for when voice/text are added.
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

  void _handleAnomalyEntry(AnomalyResultLogEntry entry) {
    final behaviorScore = entry.result.status == AnomalyStatus.evaluated
        ? entry.result.aggregateScore
        : null;

    final fusionResult = _fusionEngine.fuse({
      'voice': null,
      'text': null,
      'behavior': behaviorScore,
    });

    final decision = RiskDecision(
      riskTier: fusionResult.riskTier,
      fusionResult: fusionResult,
      evaluatedAt: entry.evaluatedAt,
      windowKey: entry.windowKey,
    );

    _latest = decision;
    if (!_controller.isClosed) {
      _controller.add(decision);
    }
  }
}
