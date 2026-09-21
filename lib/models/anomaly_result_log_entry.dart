import '../services/anomaly_evaluator.dart';

/// Persistence-layer wrapper around a pure AnomalyResult. AnomalyResult
/// itself carries no timestamp or window-key context (it's a pure
/// computation output, deliberately kept that way) — this class adds
/// exactly the metadata a stored log entry needs, without modifying
/// AnomalyResult itself.
class AnomalyResultLogEntry {
  final DateTime evaluatedAt;
  final String windowKey;
  final AnomalyResult result;

  const AnomalyResultLogEntry({
    required this.evaluatedAt,
    required this.windowKey,
    required this.result,
  });

  Map<String, dynamic> toMap() {
    return {
      'evaluatedAt': evaluatedAt.millisecondsSinceEpoch,
      'windowKey': windowKey,
      'status': result.status.name,
      'aggregateScore': result.aggregateScore,
      'sampleCountUsed': result.sampleCountUsed,
      'featureZScores': result.featureZScores,
    };
  }

  factory AnomalyResultLogEntry.fromMap(Map<dynamic, dynamic> map) {
    final rawEvaluatedAt = map['evaluatedAt'] as int?;
    final rawStatus = map['status'] as String?;
    final rawFeatureZScores = map['featureZScores'];

    final status = switch (rawStatus) {
      'coldStart' => AnomalyStatus.coldStart,
      'evaluated' => AnomalyStatus.evaluated,
      _ => throw ArgumentError('Unknown AnomalyStatus: $rawStatus'),
    };

    final featureZScores = <String, double>{};
    if (rawFeatureZScores is Map) {
      rawFeatureZScores.forEach((key, value) {
        featureZScores[key as String] = (value as num).toDouble();
      });
    }

    return AnomalyResultLogEntry(
      evaluatedAt: rawEvaluatedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(rawEvaluatedAt)
          : DateTime.now(),
      windowKey: map['windowKey'] as String,
      result: AnomalyResult(
        status: status,
        featureZScores: featureZScores,
        aggregateScore: (map['aggregateScore'] as num).toDouble(),
        sampleCountUsed: map['sampleCountUsed'] as int,
      ),
    );
  }

  @override
  String toString() {
    return 'AnomalyResultLogEntry(evaluatedAt: $evaluatedAt, '
        'windowKey: $windowKey, result: $result)';
  }
}
