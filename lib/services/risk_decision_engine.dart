import 'dart:async';

import '../models/anomaly_result_log_entry.dart';
import '../models/risk_decision.dart';
import 'anomaly_evaluator.dart';
import 'behavioral_anomaly_pipeline.dart';
import 'danger_score_fusion_engine.dart';

class RiskDecisionEngine {
  RiskDecisionEngine({
    required Stream<AnomalyResultLogEntry> anomalyStream,
    DangerScoreFusionEngine? fusionEngine,
  })  : _anomalyStream = anomalyStream,
        _fusionEngine = fusionEngine ?? const DangerScoreFusionEngine(),
        _controller = StreamController<RiskDecision>.broadcast();

  static RiskDecisionEngine? _instance;

  /// Application-level singleton, wired to the real, persistent
  /// BehavioralAnomalyPipeline (rather than any test-only or
  /// dashboard-local stream). Constructed and started lazily on first
  /// access — main.dart accesses this once at startup specifically to
  /// trigger that construction, and every other part of the app
  /// (dashboard, future MessageInterceptor, etc.) should reference
  /// this same instance rather than constructing its own.
  static RiskDecisionEngine get instance {
    if (_instance != null) return _instance!;
    _instance = RiskDecisionEngine(
      anomalyStream: BehavioralAnomalyPipeline.instance.anomalyResults,
    )..start();
    return _instance!;
  }

  final Stream<AnomalyResultLogEntry> _anomalyStream;
  final DangerScoreFusionEngine _fusionEngine;
  final StreamController<RiskDecision> _controller;

  StreamSubscription<AnomalyResultLogEntry>? _subscription;

  bool get isRunning => _subscription != null;

  RiskDecision? _latest;
  RiskDecision? get latest => _latest;

  double? _latestBehaviorScore;
  double? _latestTextScore;
  double? _latestVoiceScore;

  Stream<RiskDecision> get decisions => _controller.stream;

  void start() {
    if (_subscription != null) return;
    _subscription = _anomalyStream.listen(_handleAnomalyEntry);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await _controller.close();
  }

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

  void submitVoiceScore(
    double score, {
    DateTime? evaluatedAt,
    String windowKey = 'voice-event',
  }) {
    _latestVoiceScore = score;
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
      'voice': _latestVoiceScore,
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
