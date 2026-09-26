import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/risk_tier.dart';

void main() {
  group('classify — default thresholds (mediumRiskMin: 45, highDangerMin: 75)',
      () {
    test('score 0 is normal', () {
      expect(classify(0.0), RiskTier.normal);
    });

    test('score just below mediumRiskMin is normal', () {
      expect(classify(44.999), RiskTier.normal);
    });

    test(
        'score exactly at mediumRiskMin is mediumRisk (inclusive lower '
        'bound)', () {
      expect(classify(45.0), RiskTier.mediumRisk);
    });

    test('score just below highDangerMin is mediumRisk', () {
      expect(classify(74.999), RiskTier.mediumRisk);
    });

    test(
        'score exactly at highDangerMin is highDanger (inclusive lower '
        'bound)', () {
      expect(classify(75.0), RiskTier.highDanger);
    });

    test('score 100 is highDanger', () {
      expect(classify(100.0), RiskTier.highDanger);
    });
  });

  group('classify — custom thresholds', () {
    test('respects custom mediumRiskMin/highDangerMin boundaries', () {
      const thresholds =
          RiskThresholds(mediumRiskMin: 30.0, highDangerMin: 60.0);

      expect(classify(29.0, thresholds: thresholds), RiskTier.normal);
      expect(classify(30.0, thresholds: thresholds), RiskTier.mediumRisk);
      expect(classify(59.0, thresholds: thresholds), RiskTier.mediumRisk);
      expect(classify(60.0, thresholds: thresholds), RiskTier.highDanger);
    });
  });

  group('RiskThresholds validation', () {
    test('highDangerMin below mediumRiskMin fails an assert', () {
      // NOT const: a const constructor call has its asserts evaluated
      // at COMPILE time, so the exception would fail the whole file's
      // compilation rather than being catchable by expect() at
      // runtime. Removing const defers construction (and its assert)
      // to when the closure actually runs.
      expect(
        () => RiskThresholds(mediumRiskMin: 80.0, highDangerMin: 50.0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a threshold outside [0, 100] fails an assert', () {
      expect(
        () => RiskThresholds(mediumRiskMin: -5.0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RiskThresholds(highDangerMin: 150.0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
