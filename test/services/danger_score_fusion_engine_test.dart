import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/risk_tier.dart';
import 'package:neuralsafe/services/danger_score_fusion_engine.dart';

void main() {
  group('DangerScoreFusionEngine — default weights', () {
    test('matches Chapter 6.4: voice 0.45, text 0.35, behavior 0.20', () {
      expect(defaultModuleWeights['voice'], 0.45);
      expect(defaultModuleWeights['text'], 0.35);
      expect(defaultModuleWeights['behavior'], 0.20);
    });
  });

  group('DangerScoreFusionEngine.fuse — all modules present', () {
    test('computes the weighted sum exactly per the default weights', () {
      const engine = DangerScoreFusionEngine();

      final result = engine.fuse({
        'voice': 100.0,
        'text': 100.0,
        'behavior': 100.0,
      });

      // All present, all equal -> weighted sum = 100 regardless of split.
      expect(result.finalScore, closeTo(100.0, 1e-9));
      expect(result.contributingModules['voice'], closeTo(0.45, 1e-9));
      expect(result.contributingModules['text'], closeTo(0.35, 1e-9));
      expect(result.contributingModules['behavior'], closeTo(0.20, 1e-9));
    });

    test('a specific known mix matches hand-computed expected value', () {
      const engine = DangerScoreFusionEngine();

      // voice=80 (*0.45=36), text=20 (*0.35=7), behavior=50 (*0.20=10)
      // sum = 53
      final result = engine.fuse({
        'voice': 80.0,
        'text': 20.0,
        'behavior': 50.0,
      });

      expect(result.finalScore, closeTo(53.0, 1e-9));
    });
  });

  group('DangerScoreFusionEngine.fuse — missing module renormalization', () {
    test(
        'only behavior present: behavior gets full renormalized weight '
        'of 1.0, finalScore equals its raw score', () {
      const engine = DangerScoreFusionEngine();

      final result = engine.fuse({
        'voice': null,
        'text': null,
        'behavior': 60.0,
      });

      expect(result.contributingModules.length, 1);
      expect(result.contributingModules['behavior'], closeTo(1.0, 1e-9));
      expect(result.finalScore, closeTo(60.0, 1e-9));
    });

    test(
        'voice + behavior present (text missing): weights renormalize '
        'proportionally between the two present modules', () {
      const engine = DangerScoreFusionEngine();

      // present weights: voice 0.45, behavior 0.20 -> total 0.65
      // renormalized: voice = 0.45/0.65, behavior = 0.20/0.65
      final result = engine.fuse({
        'voice': 100.0,
        'text': null,
        'behavior': 0.0,
      });

      expect(result.contributingModules.containsKey('text'), false);
      expect(result.contributingModules['voice'], closeTo(0.45 / 0.65, 1e-9));
      expect(
          result.contributingModules['behavior'], closeTo(0.20 / 0.65, 1e-9));
      // finalScore = (0.45/0.65)*100 + (0.20/0.65)*0 = 69.230769...
      expect(result.finalScore, closeTo(0.45 / 0.65 * 100, 1e-6));
    });

    test('renormalized weights for present modules always sum to 1.0', () {
      const engine = DangerScoreFusionEngine();

      final result = engine.fuse({'voice': 10.0, 'behavior': 20.0});

      final totalWeight = result.contributingModules.values
          .fold<double>(0.0, (sum, w) => sum + w);
      expect(totalWeight, closeTo(1.0, 1e-9));
    });
  });

  group('DangerScoreFusionEngine.fuse — all modules missing', () {
    test(
        'returns a neutral zero FusionResult with an empty '
        'contributingModules map', () {
      const engine = DangerScoreFusionEngine();

      final result =
          engine.fuse({'voice': null, 'text': null, 'behavior': null});

      expect(result.finalScore, 0.0);
      expect(result.riskTier, RiskTier.normal);
      expect(result.contributingModules, isEmpty);
    });

    test('an empty input map (no keys at all) also returns neutral zero', () {
      const engine = DangerScoreFusionEngine();

      final result = engine.fuse({});

      expect(result.finalScore, 0.0);
      expect(result.contributingModules, isEmpty);
    });
  });

  group('DangerScoreFusionEngine.fuse — clamping and tier assignment', () {
    test(
        'finalScore is clamped to a maximum of 100 even if an input '
        'score somehow exceeds 100 (defensive clamp)', () {
      const engine = DangerScoreFusionEngine();

      final result = engine.fuse({'behavior': 500.0});

      expect(result.finalScore, 100.0);
    });

    test(
        'finalScore is clamped to a minimum of 0 even if an input '
        'score is negative (defensive clamp)', () {
      const engine = DangerScoreFusionEngine();

      final result = engine.fuse({'behavior': -50.0});

      expect(result.finalScore, 0.0);
    });

    test(
        'riskTier on the result matches classify() for the same score '
        'and thresholds', () {
      const thresholds =
          RiskThresholds(mediumRiskMin: 40.0, highDangerMin: 70.0);
      const engine = DangerScoreFusionEngine(thresholds: thresholds);

      final result = engine.fuse({'behavior': 80.0});

      expect(result.riskTier, RiskTier.highDanger);
      expect(
          result.riskTier, classify(result.finalScore, thresholds: thresholds));
    });
  });

  group('DangerScoreFusionEngine — custom weights', () {
    test('a custom weights map overrides the default split', () {
      const engine = DangerScoreFusionEngine(
        weights: {'behavior': 1.0},
      );

      final result = engine.fuse({'behavior': 42.0, 'voice': 999.0});

      // 'voice' is ignored entirely since it's not in this engine's
      // weights map, even though a score was provided for it.
      expect(result.contributingModules.containsKey('voice'), false);
      expect(result.finalScore, closeTo(42.0, 1e-9));
    });
  });

  group('DangerScoreFusionEngine — determinism', () {
    test('fusing the same inputs twice produces identical results', () {
      const engine = DangerScoreFusionEngine();
      final scores = {'voice': 30.0, 'text': 40.0, 'behavior': 50.0};

      final result1 = engine.fuse(scores);
      final result2 = engine.fuse(scores);

      expect(result1.finalScore, result2.finalScore);
      expect(result1.riskTier, result2.riskTier);
      expect(result1.contributingModules, result2.contributingModules);
    });
  });
}
