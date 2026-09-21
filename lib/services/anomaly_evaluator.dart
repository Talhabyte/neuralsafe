import '../models/behavioral_baseline.dart';
import '../models/behavioral_feature_vector.dart';

enum AnomalyStatus { coldStart, evaluated }

/// Result of comparing a target BehavioralFeatureVector against a
/// BehavioralBaseline. Contains only computed numbers — no
/// interpretation, no threshold-based classification, no alerting.
class AnomalyResult {
  final AnomalyStatus status;

  /// Empty when [status] is coldStart. Otherwise one entry per key in
  /// trackedFeatureKeys.
  final Map<String, double> featureZScores;

  /// 0.0 when [status] is coldStart (a safe "no signal" default for
  /// callers that read this without checking status first). Otherwise
  /// in [0, 100].
  final double aggregateScore;

  /// The baseline's sampleCount at the moment of evaluation.
  final int sampleCountUsed;

  const AnomalyResult({
    required this.status,
    required this.featureZScores,
    required this.aggregateScore,
    required this.sampleCountUsed,
  });

  @override
  String toString() {
    return 'AnomalyResult(status: $status, aggregateScore: $aggregateScore, '
        'sampleCountUsed: $sampleCountUsed, featureZScores: $featureZScores)';
  }
}

/// Pure, deterministic, stateless comparison engine. Computes per-
/// feature z-scores and a single aggregated anomaly score in [0, 100].
/// Performs NO scoring-tier classification, thresholding, or alerting
/// — that interpretation layer is explicitly out of scope here.
class AnomalyEvaluator {
  const AnomalyEvaluator({
    this.minSampleCount = 10,
    this.zScoreCapForZeroVariance = 5.0,
    this.zScoreCapForAggregate = 3.0,
  });

  /// Nmin: baselines with fewer samples than this return
  /// AnomalyStatus.coldStart rather than a computed score, to avoid
  /// spurious anomaly signals during early onboarding. Evaluated at
  /// sampleCount == minSampleCount is treated as warm (not cold) —
  /// the check is strictly "<", not "<=".
  final int minSampleCount;

  /// When a feature's baseline standard deviation is exactly 0 (never
  /// varied) but the target value differs from the baseline mean, the
  /// mathematically-undefined z-score is clamped to this magnitude
  /// (sign preserved) rather than propagating Infinity/NaN.
  final double zScoreCapForZeroVariance;

  /// The mean-absolute-z-score value that maps to a full 100 on the
  /// aggregate scale. E.g. with the default of 3.0, a mean deviation
  /// of 3 standard deviations across tracked features scores 100.
  final double zScoreCapForAggregate;

  AnomalyResult evaluate(
    BehavioralFeatureVector target,
    BehavioralBaseline baseline,
  ) {
    final sampleCount = baseline.sampleCount;

    if (sampleCount < minSampleCount) {
      return AnomalyResult(
        status: AnomalyStatus.coldStart,
        featureZScores: const {},
        aggregateScore: 0.0,
        sampleCountUsed: sampleCount,
      );
    }

    final zScores = <String, double>{};
    for (final key in trackedFeatureKeys) {
      final stat = baseline.featureStats[key];
      final value = featureValueFor(target, key);

      if (stat == null) {
        // Should not normally happen (BehavioralBaseline.initial()
        // seeds every tracked key), but handled defensively rather
        // than throwing mid-evaluation.
        zScores[key] = 0.0;
        continue;
      }

      zScores[key] = _zScoreFor(value, stat);
    }

    final absZScores = zScores.values.map((z) => z.abs()).toList();
    final meanAbsZ = absZScores.isEmpty
        ? 0.0
        : absZScores.reduce((a, b) => a + b) / absZScores.length;

    final aggregateScore =
        (meanAbsZ / zScoreCapForAggregate * 100).clamp(0.0, 100.0);

    return AnomalyResult(
      status: AnomalyStatus.evaluated,
      featureZScores: zScores,
      aggregateScore: aggregateScore,
      sampleCountUsed: sampleCount,
    );
  }

  double _zScoreFor(double value, FeatureStat stat) {
    if (stat.stdDev == 0) {
      if (value == stat.mean) return 0.0;
      return value > stat.mean
          ? zScoreCapForZeroVariance
          : -zScoreCapForZeroVariance;
    }
    return (value - stat.mean) / stat.stdDev;
  }
}
