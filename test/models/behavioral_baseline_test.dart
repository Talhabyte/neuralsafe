import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_baseline.dart';
import 'package:neuralsafe/models/behavioral_feature_vector.dart';

BehavioralFeatureVector _vectorWith({
  required double screenSessionsPerHour,
  required double meanScreenSessionMs,
}) {
  return BehavioralFeatureVector(
    windowStart: DateTime(2026, 1, 1),
    windowEnd: DateTime(2026, 1, 1, 1),
    eventCount: 0,
    screenSessionsCount: 0,
    screenSessionsPerHour: screenSessionsPerHour,
    meanScreenSessionMs: meanScreenSessionMs,
    medianScreenSessionMs: 0,
    shortSessionRatio: 0,
    userPresentCount: 0,
    appSessionsCount: 0,
    meanAppSessionMs: 0,
    medianAppSessionMs: 0,
    appSessionsPerHour: 0,
    distinctPackagesCount: 0,
    totalAppUsageMs: 0,
    topPackageUsageRatio: 0,
    perPackageUsageMs: const {},
  );
}

void main() {
  group('FeatureStat — Welford online statistics', () {
    test(
        'matches hand-computed mean and sample variance for a known '
        'dataset', () {
      // Dataset: 2, 4, 4, 4, 5, 5, 7, 9
      // Mean = 5.0, sample variance (n-1) = 4.571428..., stdDev ≈ 2.1381
      final values = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0];

      var stat = FeatureStat.initial();
      for (final v in values) {
        stat = stat.updateWith(v);
      }

      expect(stat.count, 8);
      expect(stat.mean, closeTo(5.0, 1e-9));
      expect(stat.variance, closeTo(32.0 / 7.0, 1e-9)); // 4.571428...
      expect(stat.stdDev, closeTo(2.138089935, 1e-6));
    });

    test('min and max track correctly across updates', () {
      var stat = FeatureStat.initial();
      for (final v in [5.0, 1.0, 9.0, 3.0]) {
        stat = stat.updateWith(v);
      }

      expect(stat.min, 1.0);
      expect(stat.max, 9.0);
    });

    test(
        'a single value: variance is 0, stdDev is 0, mean equals that '
        'value', () {
      final stat = FeatureStat.initial().updateWith(42.0);

      expect(stat.count, 1);
      expect(stat.mean, 42.0);
      expect(stat.variance, 0.0);
      expect(stat.stdDev, 0.0);
      expect(stat.min, 42.0);
      expect(stat.max, 42.0);
    });

    test('updateWith returns a new instance; the original is unchanged', () {
      final original = FeatureStat.initial();
      final updated = original.updateWith(10.0);

      expect(original.count, 0);
      expect(updated.count, 1);
      expect(identical(original, updated), false);
    });

    test('serialization round-trip preserves all fields', () {
      var stat = FeatureStat.initial();
      for (final v in [1.0, 2.0, 3.0]) {
        stat = stat.updateWith(v);
      }

      final reconstructed = FeatureStat.fromMap(stat.toMap());

      expect(reconstructed.count, stat.count);
      expect(reconstructed.mean, stat.mean);
      expect(reconstructed.m2, stat.m2);
      expect(reconstructed.min, stat.min);
      expect(reconstructed.max, stat.max);
    });
  });

  group('BehavioralBaseline', () {
    test('initial() seeds every tracked feature key with an empty stat', () {
      final baseline = BehavioralBaseline.initial('1h');

      expect(baseline.windowKey, '1h');
      expect(baseline.sampleCount, 0);
      expect(baseline.lastUpdated, isNull);
      for (final key in trackedFeatureKeys) {
        expect(baseline.featureStats.containsKey(key), true);
        expect(baseline.featureStats[key]!.count, 0);
      }
    });

    test(
        'updateWith updates every tracked feature together, keeping '
        'sampleCount in lockstep', () {
      var baseline = BehavioralBaseline.initial('1h');

      baseline = baseline.updateWith(
        _vectorWith(screenSessionsPerHour: 2.0, meanScreenSessionMs: 3000),
      );
      baseline = baseline.updateWith(
        _vectorWith(screenSessionsPerHour: 4.0, meanScreenSessionMs: 5000),
      );

      expect(baseline.sampleCount, 2);
      expect(baseline.featureStats['screenSessionsPerHour']!.count, 2);
      expect(baseline.featureStats['meanScreenSessionMs']!.count, 2);
      expect(baseline.featureStats['screenSessionsPerHour']!.mean, 3.0);
      expect(baseline.featureStats['meanScreenSessionMs']!.mean, 4000.0);
    });

    test(
        'different feature keys accumulate independently of each '
        'other', () {
      var baseline = BehavioralBaseline.initial('1h');

      baseline = baseline.updateWith(
        _vectorWith(screenSessionsPerHour: 10.0, meanScreenSessionMs: 1.0),
      );

      expect(baseline.featureStats['screenSessionsPerHour']!.mean, 10.0);
      expect(baseline.featureStats['meanScreenSessionMs']!.mean, 1.0);
      // Untouched-by-this-vector keys remain at their initial state.
      expect(baseline.featureStats['shortSessionRatio']!.count, 1);
      expect(baseline.featureStats['shortSessionRatio']!.mean, 0.0);
    });

    test('updateWith returns a new instance; the original is unchanged', () {
      final original = BehavioralBaseline.initial('1h');
      final updated = original.updateWith(
        _vectorWith(screenSessionsPerHour: 1.0, meanScreenSessionMs: 1.0),
      );

      expect(original.sampleCount, 0);
      expect(updated.sampleCount, 1);
      expect(identical(original, updated), false);
    });

    test('lastUpdated is set to the vector\'s windowEnd', () {
      final baseline = BehavioralBaseline.initial('1h').updateWith(
        _vectorWith(screenSessionsPerHour: 1.0, meanScreenSessionMs: 1.0),
      );

      expect(baseline.lastUpdated, DateTime(2026, 1, 1, 1));
    });

    test(
        'windowKey supports arbitrary segmentation strings without any '
        'special-casing', () {
      final weekday = BehavioralBaseline.initial('1h_weekday');
      final weekend = BehavioralBaseline.initial('1h_weekend');

      expect(weekday.windowKey, '1h_weekday');
      expect(weekend.windowKey, '1h_weekend');
    });

    test(
        'serialization round-trip preserves windowKey, stats, and '
        'lastUpdated', () {
      var baseline = BehavioralBaseline.initial('24h');
      baseline = baseline.updateWith(
        _vectorWith(screenSessionsPerHour: 5.0, meanScreenSessionMs: 2500),
      );

      final reconstructed = BehavioralBaseline.fromMap(baseline.toMap());

      expect(reconstructed.windowKey, '24h');
      expect(reconstructed.sampleCount, 1);
      expect(reconstructed.lastUpdated, baseline.lastUpdated);
      expect(
        reconstructed.featureStats['screenSessionsPerHour']!.mean,
        5.0,
      );
    });
  });

  group('featureValueFor', () {
    test('throws ArgumentError for an unknown feature key', () {
      final vector = _vectorWith(
        screenSessionsPerHour: 1.0,
        meanScreenSessionMs: 1.0,
      );

      expect(
        () => featureValueFor(vector, 'not_a_real_feature'),
        throwsArgumentError,
      );
    });

    test('correctly extracts and converts every tracked feature key', () {
      final vector = BehavioralFeatureVector(
        windowStart: DateTime(2026, 1, 1),
        windowEnd: DateTime(2026, 1, 1, 1),
        eventCount: 0,
        screenSessionsCount: 0,
        screenSessionsPerHour: 1.0,
        meanScreenSessionMs: 2.0,
        medianScreenSessionMs: 3.0,
        shortSessionRatio: 0.4,
        userPresentCount: 5,
        appSessionsCount: 0,
        meanAppSessionMs: 6.0,
        medianAppSessionMs: 7.0,
        appSessionsPerHour: 8.0,
        distinctPackagesCount: 9,
        totalAppUsageMs: 10,
        topPackageUsageRatio: 0.5,
        perPackageUsageMs: const {},
      );

      expect(featureValueFor(vector, 'screenSessionsPerHour'), 1.0);
      expect(featureValueFor(vector, 'meanScreenSessionMs'), 2.0);
      expect(featureValueFor(vector, 'medianScreenSessionMs'), 3.0);
      expect(featureValueFor(vector, 'shortSessionRatio'), 0.4);
      expect(featureValueFor(vector, 'userPresentCount'), 5.0);
      expect(featureValueFor(vector, 'appSessionsPerHour'), 8.0);
      expect(featureValueFor(vector, 'meanAppSessionMs'), 6.0);
      expect(featureValueFor(vector, 'medianAppSessionMs'), 7.0);
      expect(featureValueFor(vector, 'distinctPackagesCount'), 9.0);
      expect(featureValueFor(vector, 'totalAppUsageMs'), 10.0);
      expect(featureValueFor(vector, 'topPackageUsageRatio'), 0.5);
    });
  });
}
