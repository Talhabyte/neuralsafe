import 'risk_tier.dart';
import '../services/danger_score_fusion_engine.dart';

/// An immutable snapshot of a risk classification computed at one
/// point in time, from one behavioral evaluation window. Pure state —
/// carries no side-effect behavior of its own.
class RiskDecision {
  final RiskTier riskTier;
  final FusionResult fusionResult;
  final DateTime evaluatedAt;
  final String windowKey;

  const RiskDecision({
    required this.riskTier,
    required this.fusionResult,
    required this.evaluatedAt,
    required this.windowKey,
  });

  @override
  String toString() {
    return 'RiskDecision(riskTier: $riskTier, '
        'finalScore: ${fusionResult.finalScore}, '
        'evaluatedAt: $evaluatedAt, windowKey: $windowKey)';
  }
}
