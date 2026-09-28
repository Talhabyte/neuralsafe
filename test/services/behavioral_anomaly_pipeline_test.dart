import 'package:flutter_test/flutter_test.dart';
import 'package:neuralsafe/models/anomaly_result_log_entry.dart';
import 'package:neuralsafe/models/behavioral_baseline.dart';
import 'package:neuralsafe/services/anomaly_evaluator.dart';
import 'package:neuralsafe/services/anomaly_result_notifier.dart';
import 'package:neuralsafe/services/behavioral_anomaly_pipeline.dart';
import 'package:neuralsafe/services/feature_extractor.dart';

void main() {
  group('BehavioralAnomalyPipeline.tick', () {
    late Map<String, BehavioralBaseline> store;
    late AnomalyResultNotifier notifier;
    late List<AnomalyResultLogEntry> recorded;

    setUp(() {
      store = {};
      recorded = [];
      notifier = AnomalyResultNotifier(
        saveEntry: (result,
            {required evaluatedAt, required windowKey}) async {},
      );
      notifier.history.listen(recorded.add);
    });

    BehavioralAnomalyPipeline buildPipeline({int minSampleCount = 3}) {
      return BehavioralAnomalyPipeline.test(
        windowKey: 'test-window',
        windowSize: const Duration(minutes: 1),
        featureExtractor:
            FeatureExtractor(loadEvents: (start, end) => const []),
        loadBaseline: (key) => store[key],
        saveBaseline: (baseline) async {
          store[baseline.windowKey] = baseline;
        },
        evaluator: AnomalyEvaluator(minSampleCount: minSampleCount),
        notifier: notifier,
        clock: () => DateTime(2026, 1, 1),
      );
    }

    test(
        'first tick evaluates against an empty baseline and reports '
        'coldStart, then persists a baseline with sampleCount 1', () async {
      final pipeline = buildPipeline();
      await pipeline.tick();
      await Future<void>.delayed(Duration.zero);

      expect(recorded, hasLength(1));
      expect(recorded.first.result.status, AnomalyStatus.coldStart);
      expect(recorded.first.windowKey, 'test-window');
      expect(store['test-window']?.sampleCount, 1);
    });

    test(
        'baseline accumulates across ticks; the (minSampleCount+1)th '
        'tick is the first to evaluate for real', () async {
      final pipeline = buildPipeline(minSampleCount: 3);

      // Ticks 1-3 evaluate against baselines with 0/1/2 prior samples
      // (all coldStart, since evaluation happens before that tick's
      // own update). Tick 4 evaluates against a baseline with 3 prior
      // samples, meeting minSampleCount.
      for (var i = 0; i < 3; i++) {
        await pipeline.tick();
      }
      await pipeline.tick();
      await Future<void>.delayed(Duration.zero);

      expect(recorded, hasLength(4));
      expect(recorded[0].result.status, AnomalyStatus.coldStart);
      expect(recorded[1].result.status, AnomalyStatus.coldStart);
      expect(recorded[2].result.status, AnomalyStatus.coldStart);
      expect(recorded[3].result.status, AnomalyStatus.evaluated);
      expect(store['test-window']?.sampleCount, 4);
    });

    test('start/stop controls the periodic timer', () {
      final pipeline = buildPipeline();
      expect(pipeline.isRunning, isFalse);
      pipeline.start();
      expect(pipeline.isRunning, isTrue);
      pipeline.stop();
      expect(pipeline.isRunning, isFalse);
    });
  });
}
