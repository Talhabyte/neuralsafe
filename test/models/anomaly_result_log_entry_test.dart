import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/anomaly_result_log_entry.dart';
import 'package:neuralsafe/services/anomaly_evaluator.dart';

void main() {
  group('AnomalyResultLogEntry serialization', () {
    test(
        'an evaluated result survives round-trip with all fields '
        'preserved', () {
      final original = AnomalyResultLogEntry(
        evaluatedAt: DateTime(2026, 3, 1, 12, 0, 0),
        windowKey: '1h',
        result: const AnomalyResult(
          status: AnomalyStatus.evaluated,
          featureZScores: {
            'screenSessionsPerHour': 1.5,
            'meanScreenSessionMs': -0.75,
          },
          aggregateScore: 42.5,
          sampleCountUsed: 15,
        ),
      );

      final reconstructed = AnomalyResultLogEntry.fromMap(original.toMap());

      expect(reconstructed.evaluatedAt, original.evaluatedAt);
      expect(reconstructed.windowKey, '1h');
      expect(reconstructed.result.status, AnomalyStatus.evaluated);
      expect(reconstructed.result.aggregateScore, 42.5);
      expect(reconstructed.result.sampleCountUsed, 15);
      expect(reconstructed.result.featureZScores['screenSessionsPerHour'], 1.5);
      expect(reconstructed.result.featureZScores['meanScreenSessionMs'], -0.75);
    });

    test(
        'a coldStart result survives round-trip with an empty '
        'featureZScores map', () {
      final original = AnomalyResultLogEntry(
        evaluatedAt: DateTime(2026, 3, 1, 9, 0, 0),
        windowKey: '24h',
        result: const AnomalyResult(
          status: AnomalyStatus.coldStart,
          featureZScores: {},
          aggregateScore: 0.0,
          sampleCountUsed: 3,
        ),
      );

      final reconstructed = AnomalyResultLogEntry.fromMap(original.toMap());

      expect(reconstructed.result.status, AnomalyStatus.coldStart);
      expect(reconstructed.result.featureZScores, isEmpty);
      expect(reconstructed.result.aggregateScore, 0.0);
    });

    test('fromMap() throws ArgumentError for an unknown status string', () {
      final badMap = {
        'evaluatedAt': DateTime.now().millisecondsSinceEpoch,
        'windowKey': '1h',
        'status': 'not_a_real_status',
        'aggregateScore': 0.0,
        'sampleCountUsed': 0,
        'featureZScores': <String, double>{},
      };

      expect(
        () => AnomalyResultLogEntry.fromMap(badMap),
        throwsArgumentError,
      );
    });
  });
}
