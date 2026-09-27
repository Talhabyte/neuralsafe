import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/anomaly_result_log_entry.dart';
import 'package:neuralsafe/models/risk_tier.dart';
import 'package:neuralsafe/services/anomaly_evaluator.dart';
import 'package:neuralsafe/services/danger_score_fusion_engine.dart';
import 'package:neuralsafe/services/risk_decision_engine.dart';

AnomalyResultLogEntry _evaluatedEntry({
  required double aggregateScore,
  String windowKey = '1h',
  DateTime? evaluatedAt,
}) {
  return AnomalyResultLogEntry(
    evaluatedAt: evaluatedAt ?? DateTime(2026, 3, 1, 12, 0, 0),
    windowKey: windowKey,
    result: AnomalyResult(
      status: AnomalyStatus.evaluated,
      featureZScores: const {},
      aggregateScore: aggregateScore,
      sampleCountUsed: 20,
    ),
  );
}

AnomalyResultLogEntry _coldStartEntry({
  String windowKey = '1h',
  DateTime? evaluatedAt,
}) {
  return AnomalyResultLogEntry(
    evaluatedAt: evaluatedAt ?? DateTime(2026, 3, 1, 12, 0, 0),
    windowKey: windowKey,
    result: const AnomalyResult(
      status: AnomalyStatus.coldStart,
      featureZScores: {},
      aggregateScore: 0.0,
      sampleCountUsed: 2,
    ),
  );
}

void main() {
  group('RiskDecisionEngine', () {
    test(
        'an evaluated entry produces a RiskDecision whose finalScore '
        'equals the behavior aggregateScore (only module present)', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);

      engine.start();
      controller.add(_evaluatedEntry(aggregateScore: 62.0));
      await Future<void>.delayed(Duration.zero);

      expect(engine.latest, isNotNull);
      expect(engine.latest!.fusionResult.finalScore, closeTo(62.0, 1e-9));
      expect(engine.latest!.riskTier, RiskTier.mediumRisk); // 45<=62<75
      expect(
        engine.latest!.fusionResult.contributingModules,
        {'behavior': closeTo(1.0, 1e-9)},
      );

      await engine.stop();
      await controller.close();
      await engine.dispose();
    });

    test(
        'a coldStart entry produces a neutral RiskDecision (normal '
        'tier, score 0, no contributing modules) — cold start is NOT '
        'silently read as "definitely normal behavior" via a fake 0 '
        'score; behavior is excluded from fusion entirely', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);

      engine.start();
      controller.add(_coldStartEntry());
      await Future<void>.delayed(Duration.zero);

      expect(engine.latest, isNotNull);
      expect(engine.latest!.fusionResult.finalScore, 0.0);
      expect(engine.latest!.riskTier, RiskTier.normal);
      expect(engine.latest!.fusionResult.contributingModules, isEmpty);

      await engine.stop();
      await controller.close();
      await engine.dispose();
    });

    test(
        'windowKey and evaluatedAt on the RiskDecision match the '
        'source AnomalyResultLogEntry', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);
      final timestamp = DateTime(2026, 5, 5, 9, 30, 0);

      engine.start();
      controller.add(_evaluatedEntry(
        aggregateScore: 10.0,
        windowKey: '24h',
        evaluatedAt: timestamp,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(engine.latest!.windowKey, '24h');
      expect(engine.latest!.evaluatedAt, timestamp);

      await engine.stop();
      await controller.close();
      await engine.dispose();
    });

    test('decisions stream emits every RiskDecision in order', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);
      final received = <double>[];

      final sub = engine.decisions.listen((d) {
        received.add(d.fusionResult.finalScore);
      });

      engine.start();
      controller.add(_evaluatedEntry(aggregateScore: 10.0));
      controller.add(_evaluatedEntry(aggregateScore: 90.0));
      await Future<void>.delayed(Duration.zero);

      expect(received, [10.0, 90.0]);

      await sub.cancel();
      await engine.stop();
      await controller.close();
      await engine.dispose();
    });

    test(
        'start() is idempotent: a second call does not create a '
        'duplicate subscription (no duplicate decisions per upstream '
        'event)', () async {
      final controller = StreamController<AnomalyResultLogEntry>.broadcast();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);
      final received = <double>[];

      engine.decisions.listen((d) => received.add(d.fusionResult.finalScore));

      engine.start();
      engine.start();
      engine.start();

      controller.add(_evaluatedEntry(aggregateScore: 33.0));
      await Future<void>.delayed(Duration.zero);

      expect(received, [33.0]); // not duplicated

      await engine.stop();
      await controller.close();
      await engine.dispose();
    });

    test('stop() halts further decisions even if new entries arrive', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);

      engine.start();
      controller.add(_evaluatedEntry(aggregateScore: 20.0));
      await Future<void>.delayed(Duration.zero);
      expect(engine.latest!.fusionResult.finalScore, 20.0);

      await engine.stop();
      expect(engine.isRunning, false);

      controller.add(_evaluatedEntry(aggregateScore: 95.0));
      await Future<void>.delayed(Duration.zero);

      // latest unchanged — the second entry was never processed.
      expect(engine.latest!.fusionResult.finalScore, 20.0);

      await controller.close();
      await engine.dispose();
    });

    test(
        'a custom DangerScoreFusionEngine (custom thresholds) is '
        'respected when classifying decisions', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(
        anomalyStream: controller.stream,
        fusionEngine: const DangerScoreFusionEngine(
          thresholds: RiskThresholds(mediumRiskMin: 10.0, highDangerMin: 20.0),
        ),
      );

      engine.start();
      controller.add(_evaluatedEntry(aggregateScore: 15.0));
      await Future<void>.delayed(Duration.zero);

      expect(engine.latest!.riskTier, RiskTier.mediumRisk); // 10<=15<20

      await engine.stop();
      await controller.close();
      await engine.dispose();
    });

    test('isRunning reflects state correctly across start/stop', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);

      expect(engine.isRunning, false);
      engine.start();
      expect(engine.isRunning, true);
      await engine.stop();
      expect(engine.isRunning, false);

      await controller.close();
      await engine.dispose();
    });

    test(
        'produces NO side effects: RiskDecisionEngine never calls any '
        'external API — verified by using only in-memory fakes for the '
        'entire test and confirming no exception/unexpected call occurs',
        () async {
      // This test's very construction is the proof: RiskDecisionEngine
      // is given nothing but a plain StreamController and a pure
      // DangerScoreFusionEngine — there is no SMS service, no GPS
      // service, no notification channel anywhere in its dependency
      // graph for it to possibly call.
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);

      engine.start();
      controller.add(_evaluatedEntry(aggregateScore: 99.0)); // highDanger-tier
      await Future<void>.delayed(Duration.zero);

      expect(engine.latest!.riskTier, RiskTier.highDanger);
      // Reaching this line without any external call having been
      // possible (none were injected) confirms the "state only, no
      // action" contract.

      await engine.stop();
      await controller.close();
      await engine.dispose();
    });
    test(
        'submitTextScore fuses the text score with the most recent '
        'behavior score, not in isolation', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);

      engine.start();
      controller.add(_evaluatedEntry(aggregateScore: 40.0)); // behavior=40
      await Future<void>.delayed(Duration.zero);

      engine.submitTextScore(80.0); // now fuse behavior=40 + text=80

      // weights: text 0.35, behavior 0.20 -> total active 0.55
      // renormalized: text = 0.35/0.55, behavior = 0.20/0.55
      final expected = (0.35 / 0.55) * 80.0 + (0.20 / 0.55) * 40.0;
      expect(engine.latest!.fusionResult.finalScore, closeTo(expected, 1e-6));
      expect(
          engine.latest!.fusionResult.contributingModules.containsKey('text'),
          true);
      expect(
          engine.latest!.fusionResult.contributingModules
              .containsKey('behavior'),
          true);

      await engine.stop();
      await controller.close();
      await engine.dispose();
    });

    test(
        'a later behavior update re-fuses using the cached text score, '
        'not discarding it', () async {
      final controller = StreamController<AnomalyResultLogEntry>();
      final engine = RiskDecisionEngine(anomalyStream: controller.stream);

      engine.start();
      engine.submitTextScore(90.0); // text=90, no behavior yet

      expect(
          engine.latest!.fusionResult.contributingModules.containsKey('text'),
          true);
      expect(
          engine.latest!.fusionResult.contributingModules
              .containsKey('behavior'),
          false);

      controller.add(_evaluatedEntry(aggregateScore: 10.0)); // behavior=10
      await Future<void>.delayed(Duration.zero);

      // text score of 90 should still be contributing here
      final expected = (0.35 / 0.55) * 90.0 + (0.20 / 0.55) * 10.0;
      expect(engine.latest!.fusionResult.finalScore, closeTo(expected, 1e-6));

      await engine.stop();
      await controller.close();
      await engine.dispose();
    });
  });
}
