import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:neuralsafe/models/dispatch_result.dart';
import 'package:neuralsafe/models/risk_decision.dart';
import 'package:neuralsafe/models/risk_tier.dart';
import 'package:neuralsafe/services/alert_cooldown_manager.dart';
import 'package:neuralsafe/services/danger_score_fusion_engine.dart';
import 'package:neuralsafe/services/emergency_alert_dispatcher.dart';
import 'package:neuralsafe/services/emergency_response_orchestrator.dart';
import 'package:neuralsafe/services/location_service.dart';
import 'package:neuralsafe/services/sms_dispatch_service.dart';

class _FakeContact {
  final String id;
  final String phoneNumber;
  const _FakeContact({required this.id, required this.phoneNumber});
}

void main() {
  final fixedNow = DateTime(2026, 9, 24, 12, 0, 0);

  RiskDecision decisionWithTier(RiskTier tier) {
    final score = switch (tier) {
      RiskTier.highDanger => 90.0,
      RiskTier.mediumRisk => 55.0,
      RiskTier.normal => 10.0,
    };
    return RiskDecision(
      riskTier: tier,
      fusionResult: FusionResult(
        finalScore: score,
        riskTier: tier,
        contributingModules: const {'behavior': 1.0},
      ),
      evaluatedAt: fixedNow,
      windowKey: '1h',
    );
  }

  EmergencyAlertDispatcher buildDispatcher({
    required Future<bool> Function(String phoneNumber, String message) sendSms,
    AlertCooldownManager? cooldownManager,
    bool dryRun = false,
  }) {
    return EmergencyAlertDispatcher(
      locationService: LocationService(
        isLocationServiceEnabled: () async =>
            false, // keep location simple/failing
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async => LocationPermission.whileInUse,
        getPosition: () async => Position(
          latitude: 0,
          longitude: 0,
          timestamp: fixedNow,
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
        clock: () => fixedNow,
      ),
      smsDispatchService: SmsDispatchService(
        checkPermission: () async => PermissionStatus.granted,
        requestPermission: () async => PermissionStatus.granted,
        sendSms: sendSms,
      ),
      cooldownManager:
          cooldownManager ?? AlertCooldownManager(clock: () => fixedNow),
      loadContacts: () => [const _FakeContact(id: 'c1', phoneNumber: '+1')],
      clock: () => fixedNow,
      dryRun: dryRun,
    );
  }

  group('EmergencyResponseOrchestrator — transition triggering', () {
    test('transitioning into highDanger triggers dispatch() exactly once',
        () async {
      var sendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.normal));
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(sendCount, 1);
      expect(orchestrator.lastDispatchResult?.outcome, DispatchOutcome.sent);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });

    test(
        'the very first decision received, if highDanger, counts as a '
        'transition and triggers dispatch', () async {
      var sendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(sendCount, 1);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });

    test(
        'remaining in highDanger across subsequent decisions does NOT '
        're-trigger dispatch', () async {
      var sendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.highDanger));
      controller.add(decisionWithTier(RiskTier.highDanger));
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(sendCount, 1);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });

    test('leaving highDanger and re-entering triggers dispatch() again',
        () async {
      var sendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
        cooldownManager: AlertCooldownManager(
          cooldownDuration:
              Duration.zero, // isolate transition logic from cooldown
          clock: () => fixedNow,
        ),
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);
      controller.add(decisionWithTier(RiskTier.mediumRisk));
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(sendCount, 2);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });

    test('normal and mediumRisk decisions never trigger dispatch()', () async {
      var sendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.normal));
      controller.add(decisionWithTier(RiskTier.mediumRisk));
      controller.add(decisionWithTier(RiskTier.normal));
      await Future<void>.delayed(Duration.zero);

      expect(sendCount, 0);
      expect(orchestrator.lastDispatchResult, isNull);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });
  });

  group('EmergencyResponseOrchestrator — lifecycle', () {
    test('start() is idempotent: no duplicate subscriptions/dispatches',
        () async {
      var sendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      orchestrator.start();
      orchestrator.start();

      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(sendCount, 1);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });

    test('stop() halts further dispatch triggering', () async {
      var sendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      await orchestrator.stop();

      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(sendCount, 0);

      await controller.close();
      await orchestrator.dispose();
    });

    test(
        'stop() resets tracked tier so a later start() treats the next '
        'highDanger decision as a fresh transition', () async {
      var sendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
        cooldownManager: AlertCooldownManager(
          cooldownDuration: Duration.zero,
          clock: () => fixedNow,
        ),
      );
      // broadcast(), not a plain StreamController: this test stops and
      // re-starts the orchestrator, which cancels and re-establishes a
      // subscription on the SAME stream. A single-subscription
      // StreamController can only ever be listened to once — a second
      // listen() after the first subscription is cancelled throws
      // "Bad state: Stream has already been listened to.", regardless
      // of anything EmergencyResponseOrchestrator itself does. This is
      // a test-construction fix only; production code is unaffected
      // and unchanged.
      final controller = StreamController<RiskDecision>.broadcast();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);
      expect(sendCount, 1);

      await orchestrator.stop();
      orchestrator.start();

      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(sendCount, 2);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });
    test('isRunning reflects state correctly across start/stop', () async {
      final dispatcher = buildDispatcher(sendSms: (p, m) async => true);
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      expect(orchestrator.isRunning, false);
      orchestrator.start();
      expect(orchestrator.isRunning, true);
      await orchestrator.stop();
      expect(orchestrator.isRunning, false);

      await controller.close();
      await orchestrator.dispose();
    });
  });

  group('EmergencyResponseOrchestrator — cooldown delegation', () {
    test(
        'when the dispatcher cooldown is already active, dispatch() is '
        'still invoked on transition, but its result reflects '
        'suppression — the orchestrator adds NO cooldown logic of its '
        'own', () async {
      var sendCount = 0;
      final cooldown = AlertCooldownManager(clock: () => fixedNow);
      cooldown
          .recordAlertSent(); // prime an active cooldown BEFORE the orchestrator ever runs

      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          sendCount++;
          return true;
        },
        cooldownManager: cooldown,
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(
          sendCount, 0); // sendSms never reached — cooldown check happens first
      expect(orchestrator.lastDispatchResult?.outcome,
          DispatchOutcome.suppressedByCooldown);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });
  });

  group('EmergencyResponseOrchestrator — dispatchResults stream', () {
    test('emits each triggered DispatchResult in order', () async {
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async => true,
        cooldownManager: AlertCooldownManager(
          cooldownDuration: Duration.zero,
          clock: () => fixedNow,
        ),
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );
      final received = <DispatchOutcome>[];
      final sub = orchestrator.dispatchResults
          .listen((result) => received.add(result.outcome));

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);
      controller.add(decisionWithTier(RiskTier.normal));
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(received, [DispatchOutcome.sent, DispatchOutcome.sent]);

      await sub.cancel();
      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });
  });

  group('EmergencyResponseOrchestrator — dryRun compatibility', () {
    test(
        'works transparently with a dryRun-configured dispatcher '
        '(swap-in compatibility, per loose-coupling requirement)', () async {
      var realSendCount = 0;
      final dispatcher = buildDispatcher(
        sendSms: (p, m) async {
          realSendCount++;
          return true;
        },
        dryRun: true,
      );
      final controller = StreamController<RiskDecision>();
      final orchestrator = EmergencyResponseOrchestrator(
        riskDecisions: controller.stream,
        dispatcher: dispatcher,
      );

      orchestrator.start();
      controller.add(decisionWithTier(RiskTier.highDanger));
      await Future<void>.delayed(Duration.zero);

      expect(
          realSendCount, 0); // dry run never reaches the real sendSms function
      expect(orchestrator.lastDispatchResult?.outcome, DispatchOutcome.sent);

      await orchestrator.stop();
      await controller.close();
      await orchestrator.dispose();
    });
  });
}
