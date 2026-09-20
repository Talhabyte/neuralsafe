import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/app_usage_service.dart';

void main() {
  group('AppUsageService', () {
    late DateTime current;
    DateTime fakeClock() => current;

    const ownPackage = 'com.example.neuralsafe';
    const packageA = 'com.example.some_app_a';
    const packageB = 'com.example.some_app_b';

    setUp(() {
      current = DateTime(2026, 1, 1, 9, 0, 0);
    });

    test(
        'foreground then background produces exactly one appUsageSession '
        'with the correct duration and packageName', () async {
      final savedEvents = <BehavioralEvent>[];
      DateTime queriedSince = current;
      DateTime queriedUntil = current;

      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async {
          queriedSince = since;
          queriedUntil = until;
          return [
            AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.foreground,
              timestamp: DateTime(2026, 1, 1, 9, 0, 1),
            ),
            AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.background,
              timestamp: DateTime(2026, 1, 1, 9, 0, 6),
            ),
          ];
        },
      );

      service.start();
      current = current.add(const Duration(seconds: 10));
      await service.poll();

      expect(savedEvents.length, 1);
      final event = savedEvents.single;
      expect(event.type, BehavioralEventType.appUsageSession);
      expect(event.packageName, packageA);
      expect(event.durationMs, 5000);
      expect(queriedSince,
          DateTime(2026, 1, 1, 9, 0, 0).add(const Duration(milliseconds: 1)));
      expect(queriedUntil, current);

      await service.stop();
    });

    test('required packageName is always present on emitted events', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async => [
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.foreground,
              timestamp: current),
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.background,
              timestamp: current.add(const Duration(seconds: 2))),
        ],
      );

      service.start();
      current = current.add(const Duration(seconds: 5));
      await service.poll();

      expect(savedEvents.single.packageName, isNotNull);
      expect(savedEvents.single.packageName, isNotEmpty);

      await service.stop();
    });

    test(
        'duplicate foreground (no intervening background) does not '
        'reset the session start time', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async => [
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.foreground,
              timestamp: DateTime(2026, 1, 1, 9, 0, 0)),
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.foreground, // duplicate
              timestamp: DateTime(2026, 1, 1, 9, 0, 3)),
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.background,
              timestamp: DateTime(2026, 1, 1, 9, 0, 10)),
        ],
      );

      service.start();
      current = current.add(const Duration(seconds: 15));
      await service.poll();

      expect(savedEvents.length, 1);
      // Duration measured from the FIRST foreground (10s), not the
      // duplicate (which would be 7s).
      expect(savedEvents.single.durationMs, 10000);

      await service.stop();
    });

    test(
        'duplicate background (no active session) does not create a '
        'second appUsageSession', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async => [
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.foreground,
              timestamp: DateTime(2026, 1, 1, 9, 0, 0)),
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.background,
              timestamp: DateTime(2026, 1, 1, 9, 0, 5)),
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.background, // duplicate
              timestamp: DateTime(2026, 1, 1, 9, 0, 6)),
        ],
      );

      service.start();
      current = current.add(const Duration(seconds: 10));
      await service.poll();

      expect(savedEvents.length, 1);

      await service.stop();
    });

    test("NeuralSafe's own package is excluded from all events", () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async => [
          AppUsageRawEvent(
              packageName: ownPackage,
              type: AppUsageEventType.foreground,
              timestamp: DateTime(2026, 1, 1, 9, 0, 0)),
          AppUsageRawEvent(
              packageName: ownPackage,
              type: AppUsageEventType.background,
              timestamp: DateTime(2026, 1, 1, 9, 0, 5)),
        ],
      );

      service.start();
      current = current.add(const Duration(seconds: 10));
      await service.poll();

      expect(savedEvents, isEmpty);

      await service.stop();
    });

    test(
        'foreground(B) while A is still open does NOT close A — no '
        'inferred background transition', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async => [
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.foreground,
              timestamp: DateTime(2026, 1, 1, 9, 0, 0)),
          // No explicit background for A.
          AppUsageRawEvent(
              packageName: packageB,
              type: AppUsageEventType.foreground,
              timestamp: DateTime(2026, 1, 1, 9, 0, 3)),
        ],
      );

      service.start();
      current = current.add(const Duration(seconds: 5));
      await service.poll();

      // Neither A nor B has closed — no events yet.
      expect(savedEvents, isEmpty);

      await service.stop();
    });

    test(
        'a later explicit background for A, after B foregrounded, '
        'correctly closes A with its own duration', () async {
      final savedEvents = <BehavioralEvent>[];
      var pollCount = 0;
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async {
          pollCount++;
          if (pollCount == 1) {
            return [
              AppUsageRawEvent(
                  packageName: packageA,
                  type: AppUsageEventType.foreground,
                  timestamp: DateTime(2026, 1, 1, 9, 0, 0)),
              AppUsageRawEvent(
                  packageName: packageB,
                  type: AppUsageEventType.foreground,
                  timestamp: DateTime(2026, 1, 1, 9, 0, 3)),
            ];
          }
          return [
            AppUsageRawEvent(
                packageName: packageA,
                type: AppUsageEventType.background,
                timestamp: DateTime(2026, 1, 1, 9, 0, 20)),
          ];
        },
      );

      service.start();
      current = current.add(const Duration(seconds: 5));
      await service.poll(); // first poll: no closures yet
      expect(savedEvents, isEmpty);

      current = current.add(const Duration(seconds: 20));
      await service.poll(); // second poll: A's background finally arrives

      expect(savedEvents.length, 1);
      expect(savedEvents.single.packageName, packageA);
      expect(savedEvents.single.durationMs, 20000); // 9:00:00 -> 9:00:20

      await service.stop();
    });

    test(
        'start() does not import historical data: cursor begins at '
        '"now", not at some earlier time', () async {
      DateTime? queriedSince;
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async {},
        clock: fakeClock,
        fetchEvents: (since, until) async {
          queriedSince = since;
          return [];
        },
      );

      service.start(); // cursor initialized to `current` here
      current = current.add(const Duration(seconds: 1));
      await service.poll();

      expect(
        queriedSince,
        DateTime(2026, 1, 1, 9, 0, 0).add(const Duration(milliseconds: 1)),
      ); // one ms after start() time, per the half-open query window

      await service.stop();
    });

    test(
        'cursor never moves backwards and advances only after a '
        'successful poll', () async {
      final queriedWindows = <List<DateTime>>[];
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async {},
        clock: fakeClock,
        fetchEvents: (since, until) async {
          queriedWindows.add([since, until]);
          return [];
        },
      );

      service.start();
      current = current.add(const Duration(seconds: 5));
      await service.poll();
      current = current.add(const Duration(seconds: 5));
      await service.poll();

      expect(queriedWindows.length, 2);
      expect(
        queriedWindows[1][0],
        queriedWindows[0][1].add(const Duration(milliseconds: 1)),
      );
      expect(queriedWindows[1][0].isBefore(queriedWindows[0][0]), false);

      await service.stop();
    });

    test(
        'a fetch failure does not advance the cursor; the next poll '
        're-queries the same start point', () async {
      final queriedSinceValues = <DateTime>[];
      var shouldThrow = true;

      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async {},
        clock: fakeClock,
        fetchEvents: (since, until) async {
          queriedSinceValues.add(since);
          if (shouldThrow) {
            shouldThrow = false;
            throw Exception('simulated platform channel failure');
          }
          return [];
        },
      );

      service.start();
      current = current.add(const Duration(seconds: 5));
      await service.poll(); // fails, cursor not advanced

      current = current.add(const Duration(seconds: 5));
      await service.poll(); // succeeds

      expect(queriedSinceValues.length, 2);
      expect(queriedSinceValues[0], queriedSinceValues[1]);

      await service.stop();
    });

    test(
        'stop() clears any open (unclosed) sessions without persisting '
        'them', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async => [
          AppUsageRawEvent(
              packageName: packageA,
              type: AppUsageEventType.foreground,
              timestamp: current),
        ],
      );

      service.start();
      current = current.add(const Duration(seconds: 3));
      await service.poll();

      expect(savedEvents, isEmpty); // never closed

      await service.stop();

      expect(savedEvents, isEmpty); // still nothing persisted for it
    });

    test('isRunning reflects state correctly across start/stop', () async {
      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async {},
        clock: fakeClock,
        fetchEvents: (since, until) async => [],
      );

      expect(service.isRunning, false);
      service.start();
      expect(service.isRunning, true);
      await service.stop();
      expect(service.isRunning, false);
    });
    test('overlapping poll() calls are prevented by the in-progress guard',
        () async {
      var fetchCallCount = 0;
      final completer = Completer<void>();

      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async {},
        clock: fakeClock,
        fetchEvents: (since, until) async {
          fetchCallCount++;
          await completer.future; // hang until explicitly released below
          return [];
        },
      );

      service.start();
      current = current.add(const Duration(seconds: 5));

      final firstPoll = service.poll(); // enters, hangs inside fetchEvents
      await Future<void>.delayed(Duration.zero); // let it reach fetchEvents
      final secondPoll =
          service.poll(); // should be a no-op, return immediately

      await secondPoll;
      expect(fetchCallCount, 1); // the guarded second call never fetched

      completer.complete();
      await firstPoll;

      await service.stop();
    });

    test(
        'an event exactly at the previous poll boundary is not '
        'reprocessed on the next poll (half-open query window)', () async {
      final savedEvents = <BehavioralEvent>[];
      final boundary = DateTime(2026, 1, 1, 9, 0, 10);
      var pollCount = 0;

      final service = AppUsageService(
        ownPackageName: ownPackage,
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
        fetchEvents: (since, until) async {
          pollCount++;
          if (pollCount == 1) {
            return [
              AppUsageRawEvent(
                  packageName: packageA,
                  type: AppUsageEventType.foreground,
                  timestamp: DateTime(2026, 1, 1, 9, 0, 5)),
              AppUsageRawEvent(
                  packageName: packageA,
                  type: AppUsageEventType.background,
                  timestamp: boundary),
            ];
          }
          // Simulates an OS/API that treats `since` as inclusive: if
          // the service queried starting exactly at the previous
          // cursor (the bug this fix prevents), this branch would
          // hand back the same boundary event a second time.
          if (!since.isAfter(boundary)) {
            return [
              AppUsageRawEvent(
                  packageName: packageA,
                  type: AppUsageEventType.background,
                  timestamp: boundary),
            ];
          }
          return [];
        },
      );

      service.start();
      current = current.add(const Duration(seconds: 10)); // pollEnd == boundary
      await service.poll(); // closes the session at the boundary

      current = current.add(const Duration(seconds: 5));
      await service.poll(); // since is now boundary + 1ms, excludes the dup

      expect(savedEvents.length, 1);

      await service.stop();
    });
  });
}
