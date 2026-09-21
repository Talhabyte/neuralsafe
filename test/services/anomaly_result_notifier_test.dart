import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/services/anomaly_evaluator.dart';
import 'package:neuralsafe/services/anomaly_result_notifier.dart';

void main() {
  group('AnomalyResultNotifier', () {
    const evaluatedResult = AnomalyResult(
      status: AnomalyStatus.evaluated,
      featureZScores: {'meanScreenSessionMs': 1.2},
      aggregateScore: 40.0,
      sampleCountUsed: 12,
    );

    test('record() calls the injected saveEntry with correct arguments',
        () async {
      AnomalyResult? savedResult;
      DateTime? savedEvaluatedAt;
      String? savedWindowKey;

      final fixedNow = DateTime(2026, 3, 1, 12, 0, 0);
      final notifier = AnomalyResultNotifier(
        saveEntry: (result, {required evaluatedAt, required windowKey}) async {
          savedResult = result;
          savedEvaluatedAt = evaluatedAt;
          savedWindowKey = windowKey;
        },
        clock: () => fixedNow,
      );

      await notifier.record(evaluatedResult, windowKey: '1h');

      expect(savedResult, evaluatedResult);
      expect(savedEvaluatedAt, fixedNow);
      expect(savedWindowKey, '1h');

      await notifier.dispose();
    });

    test('latest reflects the most recently recorded entry', () async {
      final notifier = AnomalyResultNotifier(
        saveEntry: (result,
            {required evaluatedAt, required windowKey}) async {},
        clock: () => DateTime(2026, 3, 1, 12, 0, 0),
      );

      expect(notifier.latest, isNull);

      await notifier.record(evaluatedResult, windowKey: '1h');

      expect(notifier.latest, isNotNull);
      expect(notifier.latest!.result.aggregateScore, 40.0);
      expect(notifier.latest!.windowKey, '1h');

      await notifier.dispose();
    });

    test('history stream emits every recorded entry in order', () async {
      final received = <String>[];
      final notifier = AnomalyResultNotifier(
        saveEntry: (result,
            {required evaluatedAt, required windowKey}) async {},
        clock: () => DateTime(2026, 3, 1, 12, 0, 0),
      );

      final sub = notifier.history.listen((entry) {
        received.add(entry.windowKey);
      });

      await notifier.record(evaluatedResult, windowKey: '1h');
      await notifier.record(evaluatedResult, windowKey: '24h');
      await Future<void>.microtask(() {}); // let broadcast delivery flush

      expect(received, ['1h', '24h']);

      await sub.cancel();
      await notifier.dispose();
    });

    test(
        'record() performs NO threshold comparison or alert action: a '
        'high aggregateScore is recorded identically to a low one', () async {
      final savedResults = <AnomalyResult>[];
      final notifier = AnomalyResultNotifier(
        saveEntry: (result, {required evaluatedAt, required windowKey}) async {
          savedResults.add(result);
        },
        clock: () => DateTime(2026, 3, 1, 12, 0, 0),
      );

      const lowScoreResult = AnomalyResult(
        status: AnomalyStatus.evaluated,
        featureZScores: {},
        aggregateScore: 1.0,
        sampleCountUsed: 20,
      );
      const highScoreResult = AnomalyResult(
        status: AnomalyStatus.evaluated,
        featureZScores: {},
        aggregateScore: 99.9,
        sampleCountUsed: 20,
      );

      await notifier.record(lowScoreResult, windowKey: '1h');
      await notifier.record(highScoreResult, windowKey: '1h');

      // Both recorded identically — no special handling, no thrown
      // event, no different code path based on score magnitude.
      expect(savedResults.length, 2);
      expect(notifier.latest!.result.aggregateScore, 99.9);

      await notifier.dispose();
    });

    test(
        'coldStart results are recorded exactly like evaluated results '
        '— no status-based branching', () async {
      const coldStartResult = AnomalyResult(
        status: AnomalyStatus.coldStart,
        featureZScores: {},
        aggregateScore: 0.0,
        sampleCountUsed: 2,
      );

      final savedResults = <AnomalyResult>[];
      final notifier = AnomalyResultNotifier(
        saveEntry: (result, {required evaluatedAt, required windowKey}) async {
          savedResults.add(result);
        },
        clock: () => DateTime(2026, 3, 1, 12, 0, 0),
      );

      await notifier.record(coldStartResult, windowKey: '1h');

      expect(savedResults.length, 1);
      expect(notifier.latest!.result.status, AnomalyStatus.coldStart);

      await notifier.dispose();
    });
  });
}
