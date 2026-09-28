import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/anomaly_result_log_entry.dart';
import '../models/behavioral_baseline.dart';
import 'anomaly_evaluator.dart';
import 'anomaly_result_notifier.dart';
import 'behavioral_baseline_repository.dart';
import 'feature_extractor.dart';

/// Closes the gap BehavioralMonitoringService's own aggregator comment
/// flags ("nothing acts on the batches yet"): on a fixed period, this
/// computes a BehavioralFeatureVector over a trailing window ending
/// now, evaluates it against the persisted running baseline for
/// [windowKey] via AnomalyEvaluator, records the result via
/// AnomalyResultNotifier (persist + emit on [anomalyResults]), and
/// finally updates+persists the baseline with the new sample.
///
/// Evaluation happens BEFORE the baseline is updated with the new
/// sample, so a baseline with sampleCount == N is what the (N+1)th
/// tick evaluates against — the Nth tick is the one that pushes
/// sampleCount to N. With AnomalyEvaluator's default minSampleCount
/// of 10, the 11th tick is the first to produce AnomalyStatus.evaluated
/// rather than coldStart.
///
/// One pipeline instance = one window size/key. Every dependency is
/// injected as a plain function (not a whole repository object),
/// matching this codebase's existing pattern (FeatureExtractor's
/// loadEvents, AnomalyResultNotifier's saveEntry, etc.) so this is
/// fully unit-testable without touching the encrypted vault.
class BehavioralAnomalyPipeline {
  BehavioralAnomalyPipeline._({
    required this.windowKey,
    required this.windowSize,
    required FeatureExtractor featureExtractor,
    required BehavioralBaseline? Function(String windowKey) loadBaseline,
    required Future<void> Function(BehavioralBaseline baseline) saveBaseline,
    required AnomalyEvaluator evaluator,
    required AnomalyResultNotifier notifier,
    required DateTime Function() clock,
  })  : _featureExtractor = featureExtractor,
        _loadBaseline = loadBaseline,
        _saveBaseline = saveBaseline,
        _evaluator = evaluator,
        _notifier = notifier,
        _clock = clock;

  static BehavioralAnomalyPipeline? _instance;

  /// Deliberately short (2 minutes) so a live demo can accumulate
  /// AnomalyEvaluator's default minSampleCount (10) worth of samples
  /// in ~22 minutes rather than multiple hours. Trade-off: a 2-minute
  /// behavioral window is noisier/less statistically meaningful than
  /// the "15m"/"1h"/"6h"/"24h" windows BehavioralBaseline's own doc
  /// comment uses as examples. Revisit both constants together for a
  /// real longer-horizon deployment once demo timing isn't a
  /// constraint.
  static const String _defaultWindowKey = '2m';
  static const Duration _defaultWindowSize = Duration(minutes: 2);

  /// Application-level singleton, using the real encrypted-vault-backed
  /// BehavioralBaselineRepository and a real AnomalyResultNotifier.
  static BehavioralAnomalyPipeline get instance {
    if (_instance != null) return _instance!;
    final repository = BehavioralBaselineRepository();
    _instance = BehavioralAnomalyPipeline._(
      windowKey: _defaultWindowKey,
      windowSize: _defaultWindowSize,
      featureExtractor: FeatureExtractor(),
      loadBaseline: repository.load,
      saveBaseline: repository.save,
      evaluator: const AnomalyEvaluator(),
      notifier: AnomalyResultNotifier(),
      clock: DateTime.now,
    );
    return _instance!;
  }

  /// Test-only construction path. Every optional parameter defaults to
  /// a lightweight in-memory stand-in (no vault, no real clock),
  /// mirroring BehavioralMonitoringService.test()'s pattern.
  @visibleForTesting
  factory BehavioralAnomalyPipeline.test({
    required String windowKey,
    required Duration windowSize,
    FeatureExtractor? featureExtractor,
    BehavioralBaseline? Function(String windowKey)? loadBaseline,
    Future<void> Function(BehavioralBaseline baseline)? saveBaseline,
    AnomalyEvaluator? evaluator,
    AnomalyResultNotifier? notifier,
    DateTime Function()? clock,
  }) {
    return BehavioralAnomalyPipeline._(
      windowKey: windowKey,
      windowSize: windowSize,
      featureExtractor: featureExtractor ?? FeatureExtractor(),
      loadBaseline: loadBaseline ?? (_) => null,
      saveBaseline: saveBaseline ?? (_) async {},
      evaluator: evaluator ?? const AnomalyEvaluator(),
      notifier: notifier ?? AnomalyResultNotifier(),
      clock: clock ?? DateTime.now,
    );
  }

  final String windowKey;
  final Duration windowSize;
  final FeatureExtractor _featureExtractor;
  final BehavioralBaseline? Function(String windowKey) _loadBaseline;
  final Future<void> Function(BehavioralBaseline baseline) _saveBaseline;
  final AnomalyEvaluator _evaluator;
  final AnomalyResultNotifier _notifier;
  final DateTime Function() _clock;

  Timer? _timer;
  bool get isRunning => _timer != null;

  /// Feed this directly into RiskDecisionEngine as its anomalyStream.
  Stream<AnomalyResultLogEntry> get anomalyResults => _notifier.history;
  AnomalyResultLogEntry? get latest => _notifier.latest;

  /// Starts periodic evaluation. Idempotent.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(windowSize, (_) => tick());
  }

  /// Stops periodic evaluation. Safe to call even if not running.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Runs a single evaluate-and-update cycle. Exposed publicly (not
  /// just via the internal Timer) so tests can drive it
  /// deterministically, and so a manual "evaluate now" trigger is
  /// possible later if wanted (e.g. a demo button).
  Future<void> tick() async {
    final end = _clock();
    final start = end.subtract(windowSize);
    final vector = _featureExtractor.extractWindow(start, end);

    final baseline =
        _loadBaseline(windowKey) ?? BehavioralBaseline.initial(windowKey);

    final result = _evaluator.evaluate(vector, baseline);
    await _notifier.record(result, windowKey: windowKey);

    final updatedBaseline = baseline.updateWith(vector);
    await _saveBaseline(updatedBaseline);
  }
}
