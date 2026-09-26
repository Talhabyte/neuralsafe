import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/services/alert_cooldown_manager.dart';

void main() {
  group('AlertCooldownManager', () {
    test('canSendAlert() is true before any alert has ever been sent', () {
      final manager = AlertCooldownManager(clock: () => DateTime(2026, 1, 1));

      expect(manager.canSendAlert(), true);
      expect(manager.remainingCooldown(), isNull);
    });

    test('canSendAlert() is false immediately after recordAlertSent()', () {
      var current = DateTime(2026, 1, 1, 10, 0, 0);
      final manager = AlertCooldownManager(clock: () => current);

      manager.recordAlertSent();

      expect(manager.canSendAlert(), false);
      expect(manager.remainingCooldown(), const Duration(minutes: 5));
    });

    test('canSendAlert() is false while still within the cooldown window', () {
      var current = DateTime(2026, 1, 1, 10, 0, 0);
      final manager = AlertCooldownManager(clock: () => current);

      manager.recordAlertSent();
      current = current.add(const Duration(minutes: 3));

      expect(manager.canSendAlert(), false);
      expect(manager.remainingCooldown(), const Duration(minutes: 2));
    });

    test(
        'canSendAlert() is true exactly AT the cooldown boundary '
        '(inclusive)', () {
      var current = DateTime(2026, 1, 1, 10, 0, 0);
      final manager = AlertCooldownManager(clock: () => current);

      manager.recordAlertSent();
      current = current.add(const Duration(minutes: 5)); // exactly at boundary

      expect(manager.canSendAlert(), true);
      expect(manager.remainingCooldown(), isNull);
    });

    test('canSendAlert() is true after the cooldown has fully elapsed', () {
      var current = DateTime(2026, 1, 1, 10, 0, 0);
      final manager = AlertCooldownManager(clock: () => current);

      manager.recordAlertSent();
      current = current.add(const Duration(minutes: 10));

      expect(manager.canSendAlert(), true);
    });

    test('a custom cooldownDuration is respected', () {
      var current = DateTime(2026, 1, 1, 10, 0, 0);
      final manager = AlertCooldownManager(
        cooldownDuration: const Duration(seconds: 30),
        clock: () => current,
      );

      manager.recordAlertSent();
      current = current.add(const Duration(seconds: 20));
      expect(manager.canSendAlert(), false);

      current = current.add(const Duration(seconds: 15));
      expect(manager.canSendAlert(), true);
    });

    test(
        'recordAlertSent() called multiple times uses the MOST RECENT '
        'timestamp for the cooldown window', () {
      var current = DateTime(2026, 1, 1, 10, 0, 0);
      final manager = AlertCooldownManager(clock: () => current);

      manager.recordAlertSent();
      current = current.add(const Duration(minutes: 4));
      manager.recordAlertSent(); // resets the window from here

      current = current.add(const Duration(minutes: 4));
      // 4 minutes since the SECOND recordAlertSent() -> still within cooldown
      expect(manager.canSendAlert(), false);
    });
  });
}
