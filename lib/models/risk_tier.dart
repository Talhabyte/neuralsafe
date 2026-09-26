/// Coarse risk classification derived from a fused danger score.
/// Naming mirrors Chapter 6.4's original NORMAL / MEDIUM RISK / HIGH
/// DANGER response tiers, rescaled to fit the [0, 100] range that
/// `AnomalyEvaluator` and `DangerScoreFusionEngine` both output.
///
/// This enum and [classify] are pure classification only — no alert
/// dispatch, no SMS, no GPS, no UI. That remains out of scope until a
/// later, separately-approved phase.
enum RiskTier { normal, mediumRisk, highDanger }

/// Immutable score boundaries for [classify]. Both bounds are the
/// inclusive lower edge of their tier (e.g. a score exactly at
/// [mediumRiskMin] is mediumRisk, not normal).
class RiskThresholds {
  final double mediumRiskMin;
  final double highDangerMin;

  const RiskThresholds({
    this.mediumRiskMin = 45.0,
    this.highDangerMin = 75.0,
  })  : assert(mediumRiskMin >= 0 && mediumRiskMin <= 100,
            'mediumRiskMin must be within [0, 100]'),
        assert(highDangerMin >= 0 && highDangerMin <= 100,
            'highDangerMin must be within [0, 100]'),
        assert(highDangerMin >= mediumRiskMin,
            'highDangerMin must be >= mediumRiskMin');

  @override
  String toString() =>
      'RiskThresholds(mediumRiskMin: $mediumRiskMin, highDangerMin: $highDangerMin)';
}

/// Pure classification: maps a score to a tier using [thresholds].
/// Deterministic, stateless — no side effects.
RiskTier classify(double score,
    {RiskThresholds thresholds = const RiskThresholds()}) {
  if (score >= thresholds.highDangerMin) return RiskTier.highDanger;
  if (score >= thresholds.mediumRiskMin) return RiskTier.mediumRisk;
  return RiskTier.normal;
}
