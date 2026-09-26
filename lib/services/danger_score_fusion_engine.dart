import '../models/risk_tier.dart';

/// Default per-module weights, matching Chapter 6.4's original Danger
/// Score formula: voice 0.45, text 0.35, behavior 0.20. Only 'behavior'
/// currently has a real data source (AnomalyEvaluator, via
/// RiskDecisionEngine) — 'voice' and 'text' keys exist here so the
/// engine is ready for those modules once they're built, but nothing
/// in this codebase currently supplies scores for them.
const Map<String, double> defaultModuleWeights = {
  'voice': 0.45,
  'text': 0.35,
  'behavior': 0.20,
};

/// Result of fusing one or more module scores into a single value.
/// [contributingModules] maps each module key that was actually
/// included (had a non-null score) to its RENORMALIZED weight — i.e.
/// the weight it was actually given in this specific fusion, after
/// redistributing the weight of any missing modules. These values sum
/// to 1.0 whenever at least one module contributed.
class FusionResult {
  final double finalScore;
  final RiskTier riskTier;
  final Map<String, double> contributingModules;

  const FusionResult({
    required this.finalScore,
    required this.riskTier,
    required this.contributingModules,
  });

  @override
  String toString() {
    return 'FusionResult(finalScore: $finalScore, riskTier: $riskTier, '
        'contributingModules: $contributingModules)';
  }
}

/// Pure, deterministic, stateless fusion engine. Combines per-module
/// scores (each expected in [0, 100]) into one final score using
/// [weights], with missing (null) modules handled by proportionally
/// renormalizing the remaining active modules' weights — a missing
/// module is NEVER treated as contributing a score of 0, which would
/// incorrectly pull the final score down rather than honestly
/// reflecting "this module has no data."
///
/// Performs NO side effects: no persistence, no alerting, no SMS, no
/// GPS. Produces a `FusionResult` only.
class DangerScoreFusionEngine {
  const DangerScoreFusionEngine({
    this.weights = defaultModuleWeights,
    this.thresholds = const RiskThresholds(),
  });

  final Map<String, double> weights;
  final RiskThresholds thresholds;

  /// [moduleScores] maps module key (e.g. 'voice', 'text', 'behavior')
  /// to its current score, or null if that module has no data right
  /// now. Only keys also present in [weights] are considered; unknown
  /// keys in [moduleScores] are ignored.
  FusionResult fuse(Map<String, double?> moduleScores) {
    final activeScores = <String, double>{};
    for (final key in weights.keys) {
      final score = moduleScores[key];
      if (score != null) {
        activeScores[key] = score.clamp(0.0, 100.0);
      }
    }

    final totalActiveWeight =
        activeScores.keys.fold<double>(0.0, (sum, key) => sum + weights[key]!);

    if (totalActiveWeight == 0) {
      return FusionResult(
        finalScore: 0.0,
        riskTier: classify(0.0, thresholds: thresholds),
        contributingModules: const {},
      );
    }

    final contributingModules = <String, double>{};
    var weightedSum = 0.0;
    for (final entry in activeScores.entries) {
      final renormalizedWeight = weights[entry.key]! / totalActiveWeight;
      contributingModules[entry.key] = renormalizedWeight;
      weightedSum += renormalizedWeight * entry.value;
    }

    final finalScore = weightedSum.clamp(0.0, 100.0);

    return FusionResult(
      finalScore: finalScore,
      riskTier: classify(finalScore, thresholds: thresholds),
      contributingModules: contributingModules,
    );
  }
}
