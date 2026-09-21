import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_baseline.dart';
import 'package:neuralsafe/models/behavioral_feature_vector.dart';
import 'package:neuralsafe/services/anomaly_evaluator.dart';

/// Synthetic test fixture: every "unconstrained" numeric feature is
/// set to [value]. The two constructor-bounded ratio fields
/// (shortSessionRatio, topPackageUsageRatio) are set to
/// value.clamp(0.0, 1.0) rather than the raw value, so any [value]
/// (including > 1.0, as used by several tests below) always produces
/// a valid BehavioralFeatureVector. Because every call site in this
/// file that cares about a uniform z-score across ALL fields already
/// uses values within [0, 1] (see the "standard scoring" and
/// "zero-variance" groups, which call _vectorAllFeaturesAtMixed
/// directly with an explicit ratio instead of this helper), the clamp
/// here only matters for callers — like the cold-start tests below —
/// that use larger values but never inspect featureZScores, so the
/// ratio fields silently saturating at 1.0 has no effect on what
/// those tests actually assert.
BehavioralFeatureVector _vectorAllFeaturesAt(double value) {
  return _vectorAllFeaturesAtMixed(
    unconstrained: value,
    ratio: value.clamp(0.0, 1.0),
  );
}

BehavioralBaseline _baselineFromValues(String windowKey, List<double> values) {
  var baseline = BehavioralBaseline.initial(windowKey);
  for (final v in values) {
    baseline = baseline.updateWith(_vectorAllFeaturesAt(v));
  }
  return baseline;
}

void main() {
  group('AnomalyEvaluator — cold start', () {
    test('returns coldStart when sampleCount < minSampleCount', () {
      const evaluator = AnomalyEvaluator(minSampleCount: 10);
      final baseline = _baselineFromValues(
        '1h',
        List.generate(9, (i) => 5.0), // only 9 samples
      );

      final result = evaluator.evaluate(_vectorAllFeaturesAt(5.0), baseline);

      expect(result.status, AnomalyStatus.coldStart);
      expect(result.featureZScores, isEmpty);
      expect(result.aggregateScore, 0.0);
      expect(result.sampleCountUsed, 9);
    });

    test('evaluates normally (not cold) exactly AT minSampleCount', () {
      const evaluator = AnomalyEvaluator(minSampleCount: 10);
      final baseline = _baselineFromValues(
        '1h',
        List.generate(10, (i) => 5.0), // exactly 10 samples
      );

      final result = evaluator.evaluate(_vectorAllFeaturesAt(5.0), baseline);

      expect(result.status, AnomalyStatus.evaluated);
      expect(result.sampleCountUsed, 10);
    });

    test('a completely fresh baseline (0 samples) is cold start', () {
      const evaluator = AnomalyEvaluator();
      final baseline = BehavioralBaseline.initial('1h');

      final result = evaluator.evaluate(_vectorAllFeaturesAt(5.0), baseline);

      expect(result.status, AnomalyStatus.coldStart);
      expect(result.aggregateScore, 0.0);
    });
  });

  group('AnomalyEvaluator — standard scoring', () {
    test(
        'a target matching the baseline mean exactly scores 0 across '
        'all features', () {
      const evaluator = AnomalyEvaluator(minSampleCount: 3);
      final baseline = _vectorSafeBaseline([4.0, 5.0, 6.0]);

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 5.0, ratio: 0.5),
        baseline,
      );

      expect(result.status, AnomalyStatus.evaluated);
      for (final z in result.featureZScores.values) {
        expect(z, closeTo(0.0, 1e-9));
      }
      expect(result.aggregateScore, closeTo(0.0, 1e-9));
    });

    test(
        'a hand-computed z-score matches the formula for a known '
        'dataset', () {
      const evaluator = AnomalyEvaluator(minSampleCount: 3);
      final baseline = _vectorSafeBaseline([2.0, 4.0, 6.0]);

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 8.0, ratio: 0.5),
        baseline,
      );

      expect(result.status, AnomalyStatus.evaluated);
      for (final key in _unconstrainedFeatureKeys) {
        expect(result.featureZScores[key], closeTo(2.0, 1e-6));
      }
    });

    test(
        'aggregateScore reflects the configured zScoreCapForAggregate '
        'scaling', () {
      const evaluator = AnomalyEvaluator(
        minSampleCount: 3,
        zScoreCapForAggregate: 2.0,
      );
      final baseline = _vectorSafeBaselineFixedRatio(
        unconstrainedValues: [2.0, 4.0, 6.0],
        ratio: 0.5,
      );

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 8.0, ratio: 0.5),
        baseline,
      );

      expect(result.aggregateScore, closeTo(18 / 11 / 2.0 * 100, 1e-6));
    });

    test('aggregateScore never exceeds 100 even for extreme deviations', () {
      const evaluator = AnomalyEvaluator(minSampleCount: 3);
      final baseline = _vectorSafeBaseline([1.0, 2.0, 3.0]);

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 1000000.0, ratio: 1.0),
        baseline,
      );

      expect(result.status, AnomalyStatus.evaluated);
      expect(result.aggregateScore, 100.0);
      expect(result.aggregateScore <= 100.0, true);
    });

    test(
        'featureZScores contains an entry for every tracked feature '
        'key', () {
      const evaluator = AnomalyEvaluator(minSampleCount: 3);
      final baseline = _vectorSafeBaseline([1.0, 2.0, 3.0]);

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 2.5, ratio: 0.5),
        baseline,
      );

      for (final key in trackedFeatureKeys) {
        expect(result.featureZScores.containsKey(key), true);
      }
      expect(result.featureZScores.length, trackedFeatureKeys.length);
    });
  });

  group('AnomalyEvaluator — zero-variance edge cases', () {
    test('zero variance and matching value produces z = 0, not NaN', () {
      const evaluator = AnomalyEvaluator(minSampleCount: 3);
      final baseline = _vectorSafeBaseline([5.0, 5.0, 5.0]);

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 5.0, ratio: 0.5),
        baseline,
      );

      expect(result.status, AnomalyStatus.evaluated);
      for (final z in result.featureZScores.values) {
        expect(z, 0.0);
        expect(z.isNaN, false);
      }
      expect(result.aggregateScore, 0.0);
    });

    test(
        'zero variance and a higher target value clamps to the '
        'positive zScoreCapForZeroVariance, not Infinity', () {
      const evaluator =
          AnomalyEvaluator(minSampleCount: 3, zScoreCapForZeroVariance: 5.0);
      final baseline = _vectorSafeBaseline([3.0, 3.0, 3.0]);

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 9.0, ratio: 0.3),
        baseline,
      );

      expect(result.status, AnomalyStatus.evaluated);
      for (final key in _unconstrainedFeatureKeys) {
        expect(result.featureZScores[key], 5.0);
        expect(result.featureZScores[key]!.isInfinite, false);
      }
    });

    test(
        'zero variance and a lower target value clamps to the '
        'negative zScoreCapForZeroVariance', () {
      const evaluator =
          AnomalyEvaluator(minSampleCount: 3, zScoreCapForZeroVariance: 5.0);
      final baseline = _vectorSafeBaseline([5.0, 5.0, 5.0]);

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 1.0, ratio: 0.1),
        baseline,
      );

      expect(result.status, AnomalyStatus.evaluated);
      for (final key in _unconstrainedFeatureKeys) {
        expect(result.featureZScores[key], -5.0);
      }
    });

    test('a custom zScoreCapForZeroVariance is respected', () {
      const evaluator =
          AnomalyEvaluator(minSampleCount: 3, zScoreCapForZeroVariance: 8.0);
      final baseline = _vectorSafeBaseline([3.0, 3.0, 3.0]);

      final result = evaluator.evaluate(
        _vectorAllFeaturesAtMixed(unconstrained: 10.0, ratio: 1.0),
        baseline,
      );

      for (final key in _unconstrainedFeatureKeys) {
        expect(result.featureZScores[key], 8.0);
      }
    });
  });

  group('AnomalyEvaluator — determinism', () {
    test('evaluating the same inputs twice produces identical results', () {
      const evaluator = AnomalyEvaluator(minSampleCount: 3);
      final baseline = _vectorSafeBaseline([2.0, 4.0, 6.0]);
      final target = _vectorAllFeaturesAtMixed(unconstrained: 7.0, ratio: 0.5);

      final result1 = evaluator.evaluate(target, baseline);
      final result2 = evaluator.evaluate(target, baseline);

      expect(result1.aggregateScore, result2.aggregateScore);
      expect(result1.featureZScores, result2.featureZScores);
      expect(result1.status, result2.status);
    });
  });
}

const List<String> _unconstrainedFeatureKeys = [
  'screenSessionsPerHour',
  'meanScreenSessionMs',
  'medianScreenSessionMs',
  'userPresentCount',
  'appSessionsPerHour',
  'meanAppSessionMs',
  'medianAppSessionMs',
  'distinctPackagesCount',
  'totalAppUsageMs',
];

BehavioralBaseline _vectorSafeBaseline(List<double> values) {
  var baseline = BehavioralBaseline.initial('1h');
  for (final v in values) {
    baseline = baseline.updateWith(
      _vectorAllFeaturesAtMixed(unconstrained: v, ratio: v <= 1.0 ? v : 0.5),
    );
  }
  return baseline;
}

BehavioralBaseline _vectorSafeBaselineFixedRatio({
  required List<double> unconstrainedValues,
  required double ratio,
}) {
  var baseline = BehavioralBaseline.initial('1h');
  for (final v in unconstrainedValues) {
    baseline = baseline.updateWith(
      _vectorAllFeaturesAtMixed(unconstrained: v, ratio: ratio),
    );
  }
  return baseline;
}

BehavioralFeatureVector _vectorAllFeaturesAtMixed({
  required double unconstrained,
  required double ratio,
}) {
  return BehavioralFeatureVector(
    windowStart: DateTime(2026, 1, 1),
    windowEnd: DateTime(2026, 1, 1, 1),
    eventCount: 0,
    screenSessionsCount: 0,
    screenSessionsPerHour: unconstrained,
    meanScreenSessionMs: unconstrained,
    medianScreenSessionMs: unconstrained,
    shortSessionRatio: ratio,
    userPresentCount: unconstrained.round().clamp(0, 1 << 30),
    appSessionsCount: 0,
    meanAppSessionMs: unconstrained,
    medianAppSessionMs: unconstrained,
    appSessionsPerHour: unconstrained,
    distinctPackagesCount: unconstrained.round().clamp(0, 1 << 30),
    totalAppUsageMs: unconstrained.round().clamp(0, 1 << 30),
    topPackageUsageRatio: ratio,
    perPackageUsageMs: const {},
  );
}
