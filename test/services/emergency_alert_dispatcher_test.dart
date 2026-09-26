import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:neuralsafe/models/dispatch_result.dart';
import 'package:neuralsafe/services/alert_cooldown_manager.dart';
import 'package:neuralsafe/services/emergency_alert_dispatcher.dart';
import 'package:neuralsafe/services/location_service.dart';
import 'package:neuralsafe/services/sms_dispatch_service.dart';

/// Minimal fake standing in for EmergencyContact, matching only the
/// fields EmergencyAlertDispatcher actually reads (id, phoneNumber).
class _FakeContact {
  final String id;
  final String phoneNumber;
  const _FakeContact({required this.id, required this.phoneNumber});
}

void main() {
  final fixedNow = DateTime(2026, 9, 24, 12, 0, 0);

  Position samplePosition() {
    return Position(
      latitude: 33.721,
      longitude: 73.065,
      timestamp: fixedNow,
      accuracy: 5.0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  LocationService successfulLocationService() {
    return LocationService(
      isLocationServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async => LocationPermission.whileInUse,
      getPosition: () async => samplePosition(),
      clock: () => fixedNow,
    );
  }

  LocationService failingLocationService() {
    return LocationService(
      isLocationServiceEnabled: () async => false, // fails at the first check
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async => LocationPermission.whileInUse,
      getPosition: () async => samplePosition(),
      clock: () => fixedNow,
    );
  }

  SmsDispatchService smsServiceWithSend(
    Future<bool> Function(String phoneNumber, String message) sendSms,
  ) {
    return SmsDispatchService(
      checkPermission: () async => PermissionStatus.granted,
      requestPermission: () async => PermissionStatus.granted,
      sendSms: sendSms,
    );
  }

  group('EmergencyAlertDispatcher.dispatch — cooldown', () {
    test(
        'returns suppressedByCooldown and makes no send attempts when '
        'the cooldown has not elapsed', () async {
      var smsCallCount = 0;
      final cooldown = AlertCooldownManager(clock: () => fixedNow);
      cooldown.recordAlertSent(); // simulate a recent prior alert

      final dispatcher = EmergencyAlertDispatcher(
        locationService: successfulLocationService(),
        smsDispatchService: smsServiceWithSend((p, m) async {
          smsCallCount++;
          return true;
        }),
        cooldownManager: cooldown,
        loadContacts: () => [const _FakeContact(id: 'c1', phoneNumber: '+1')],
        clock: () => fixedNow,
      );

      final result = await dispatcher.dispatch();

      expect(result.outcome, DispatchOutcome.suppressedByCooldown);
      expect(result.perContactSuccess, isEmpty);
      expect(smsCallCount, 0);
    });
  });

  group('EmergencyAlertDispatcher.dispatch — no contacts', () {
    test('returns noContactsConfigured when the contact list is empty',
        () async {
      final dispatcher = EmergencyAlertDispatcher(
        locationService: successfulLocationService(),
        smsDispatchService: smsServiceWithSend((p, m) async => true),
        cooldownManager: AlertCooldownManager(clock: () => fixedNow),
        loadContacts: () => [],
        clock: () => fixedNow,
      );

      final result = await dispatcher.dispatch();

      expect(result.outcome, DispatchOutcome.noContactsConfigured);
      expect(result.perContactSuccess, isEmpty);
    });
  });

  group('EmergencyAlertDispatcher.dispatch — successful sends', () {
    test('sends to ALL stored contacts, not just one', () async {
      final sentMessages = <String, String>{};

      final dispatcher = EmergencyAlertDispatcher(
        locationService: successfulLocationService(),
        smsDispatchService: smsServiceWithSend((p, m) async {
          sentMessages[p] = m;
          return true;
        }),
        cooldownManager: AlertCooldownManager(clock: () => fixedNow),
        loadContacts: () => [
          const _FakeContact(id: 'c1', phoneNumber: '+10001'),
          const _FakeContact(id: 'c2', phoneNumber: '+10002'),
          const _FakeContact(id: 'c3', phoneNumber: '+10003'),
        ],
        clock: () => fixedNow,
      );

      final result = await dispatcher.dispatch();

      expect(result.outcome, DispatchOutcome.sent);
      expect(result.perContactSuccess.length, 3);
      expect(result.perContactSuccess['c1'], true);
      expect(result.perContactSuccess['c2'], true);
      expect(result.perContactSuccess['c3'], true);
      expect(sentMessages.length, 3);
    });

    test('message includes the Google Maps link when GPS succeeds', () async {
      String? capturedMessage;

      final dispatcher = EmergencyAlertDispatcher(
        locationService: successfulLocationService(),
        smsDispatchService: smsServiceWithSend((p, m) async {
          capturedMessage = m;
          return true;
        }),
        cooldownManager: AlertCooldownManager(clock: () => fixedNow),
        loadContacts: () => [const _FakeContact(id: 'c1', phoneNumber: '+1')],
        clock: () => fixedNow,
      );

      await dispatcher.dispatch();

      expect(
        capturedMessage,
        contains('https://maps.google.com/?q=33.721,73.065'),
      );
      expect(capturedMessage, startsWith('EMERGENCY ALERT:'));
      expect(capturedMessage, contains('(Automated alert sent by NeuralSafe)'));
    });

    test('message uses "Unavailable" when location acquisition fails',
        () async {
      String? capturedMessage;

      final dispatcher = EmergencyAlertDispatcher(
        locationService: failingLocationService(),
        smsDispatchService: smsServiceWithSend((p, m) async {
          capturedMessage = m;
          return true;
        }),
        cooldownManager: AlertCooldownManager(clock: () => fixedNow),
        loadContacts: () => [const _FakeContact(id: 'c1', phoneNumber: '+1')],
        clock: () => fixedNow,
      );

      final result = await dispatcher.dispatch();

      // Dispatch proceeds even though location failed — per the
      // approved fallback behavior.
      expect(result.outcome, DispatchOutcome.sent);
      expect(capturedMessage, contains('Location: Unavailable'));
      expect(capturedMessage, startsWith('EMERGENCY ALERT:'));
      expect(capturedMessage, contains('(Automated alert sent by NeuralSafe)'));
    });
  });

  group('EmergencyAlertDispatcher.dispatch — partial failure', () {
    test(
        'returns partialFailure when at least one contact fails to '
        'receive the SMS', () async {
      final dispatcher = EmergencyAlertDispatcher(
        locationService: failingLocationService(),
        smsDispatchService: smsServiceWithSend(
          (p, m) async => p == '+success', // only this one succeeds
        ),
        cooldownManager: AlertCooldownManager(clock: () => fixedNow),
        loadContacts: () => [
          const _FakeContact(id: 'c1', phoneNumber: '+success'),
          const _FakeContact(id: 'c2', phoneNumber: '+fail'),
        ],
        clock: () => fixedNow,
      );

      final result = await dispatcher.dispatch();

      expect(result.outcome, DispatchOutcome.partialFailure);
      expect(result.perContactSuccess['c1'], true);
      expect(result.perContactSuccess['c2'], false);
    });
  });

  group('EmergencyAlertDispatcher.dispatch — cooldown recording', () {
    test(
        'recordAlertSent() is called after a real dispatch attempt, '
        'so a second immediate call is suppressed', () async {
      final cooldown = AlertCooldownManager(clock: () => fixedNow);

      final dispatcher = EmergencyAlertDispatcher(
        locationService: failingLocationService(),
        smsDispatchService: smsServiceWithSend((p, m) async => true),
        cooldownManager: cooldown,
        loadContacts: () => [const _FakeContact(id: 'c1', phoneNumber: '+1')],
        clock: () => fixedNow,
      );

      final firstResult = await dispatcher.dispatch();
      expect(firstResult.outcome, DispatchOutcome.sent);

      final secondResult = await dispatcher.dispatch();
      expect(secondResult.outcome, DispatchOutcome.suppressedByCooldown);
    });
  });

  group('EmergencyAlertDispatcher.dispatch — dry run', () {
    test(
        'dryRun: true never calls the real sendSms function, but still '
        'reports success and records the cooldown', () async {
      var realSendCallCount = 0;

      final dispatcher = EmergencyAlertDispatcher(
        locationService: failingLocationService(),
        smsDispatchService: smsServiceWithSend((p, m) async {
          realSendCallCount++;
          return true;
        }),
        cooldownManager: AlertCooldownManager(clock: () => fixedNow),
        loadContacts: () => [
          const _FakeContact(id: 'c1', phoneNumber: '+1'),
          const _FakeContact(id: 'c2', phoneNumber: '+2'),
        ],
        clock: () => fixedNow,
        dryRun: true,
      );

      final result = await dispatcher.dispatch();

      expect(realSendCallCount, 0); // SmsDispatchService.send() was never
      // reached in dry-run mode
      expect(result.outcome, DispatchOutcome.sent);
      expect(result.perContactSuccess['c1'], true);
      expect(result.perContactSuccess['c2'], true);

      // Cooldown was still recorded even in dry-run mode.
      final second = await dispatcher.dispatch();
      expect(second.outcome, DispatchOutcome.suppressedByCooldown);
    });
  });
}
