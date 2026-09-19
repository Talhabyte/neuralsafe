import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/app_lifecycle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLifecycleService', () {
    test('resumed generates an appForeground event', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
      );

      service.start();
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(savedEvents.length, 1);
      expect(savedEvents.first.type, BehavioralEventType.appForeground);

      await service.stop();
    });

    test('paused generates an appBackground event', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
      );

      service.start();
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(
          Duration.zero); // let async _handlePaused finish

      expect(savedEvents.length, 1);
      expect(savedEvents.first.type, BehavioralEventType.appBackground);

      await service.stop();
    });

    test('inactive/detached/hidden states do not generate events', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
      );

      service.start();
      service.didChangeAppLifecycleState(AppLifecycleState.inactive);
      service.didChangeAppLifecycleState(AppLifecycleState.detached);
      service.didChangeAppLifecycleState(AppLifecycleState.hidden);

      expect(savedEvents, isEmpty);

      await service.stop();
    });

    test('start() is idempotent', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
      );

      service.start();
      service.start();
      service.start();
      expect(service.isRunning, true);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(savedEvents.length, 1);

      await service.stop();
    });

    test(
        'stop() stops monitoring: isRunning is false and no further '
        'events are forwarded, even if the OS calls back once more', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
      );

      service.start();
      await service.stop();

      expect(service.isRunning, false);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(savedEvents, isEmpty);
    });

    test('isRunning reflects state correctly across start/stop', () async {
      final service = AppLifecycleService(onEvent: (event) async {});

      expect(service.isRunning, false);
      service.start();
      expect(service.isRunning, true);
      await service.stop();
      expect(service.isRunning, false);
    });
  });

  group('AppLifecycleService appSession (Step 3.4)', () {
    late DateTime current;
    DateTime fakeClock() => current;

    setUp(() {
      current = DateTime(2026, 1, 1, 10, 0, 0);
    });

    test(
        'resumed starts a session; a subsequent paused creates exactly '
        'one appSession event with the expected positive duration', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);

      current = current.add(const Duration(milliseconds: 1500));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.appSession)
          .toList();
      expect(sessionEvents.length, 1);
      expect(sessionEvents.first.durationMs, 1500);
      expect(sessionEvents.first.durationMs! > 0, true);

      await service.stop();
    });

    test('paused without an active session creates no appSession event',
        () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.appSession)
          .toList();
      expect(sessionEvents, isEmpty);

      await service.stop();
    });

    test('duplicate paused does not create duplicate session events', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      current = current.add(const Duration(milliseconds: 1000));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.appSession)
          .toList();
      expect(sessionEvents.length, 1);

      await service.stop();
    });

    test('duplicate resumed does not reset the session start time', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);

      current = current.add(const Duration(milliseconds: 400));
      service
          .didChangeAppLifecycleState(AppLifecycleState.resumed); // duplicate

      current = current.add(const Duration(milliseconds: 600));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.appSession)
          .toList();
      expect(sessionEvents.length, 1);
      expect(sessionEvents.first.durationMs, 1000);

      await service.stop();
    });

    test(
        'a second resumed-paused cycle creates a second independent '
        'appSession event', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = AppLifecycleService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      current = current.add(const Duration(milliseconds: 300));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      current = current.add(const Duration(milliseconds: 50));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      current = current.add(const Duration(milliseconds: 700));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.appSession)
          .toList();
      expect(sessionEvents.length, 2);
      expect(sessionEvents[0].durationMs, 300);
      expect(sessionEvents[1].durationMs, 700);

      await service.stop();
    });

    // Directly proves the (revised) ordering: appSession must be
    // emitted and its save fully completed BEFORE appBackground's
    // save begins — the opposite order from the first fix, changed
    // after physical Android testing showed the second of two
    // sequential saves was reliably lost during the paused transition.
    test(
        'on paused, appSession is emitted and awaited before '
        'appBackground begins (priority-ordering fix for physical '
        'Android lifecycle transition)', () async {
      final callOrder = <String>[];
      final service = AppLifecycleService(
        onEvent: (event) async {
          callOrder.add('${event.type.name}:start');
          // Simulate a non-trivial async save (like the real
          // repository's read-modify-write) to make a would-be race
          // observable: if the two saves were not properly sequenced,
          // this delay would let the other event's call interleave here.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          callOrder.add('${event.type.name}:end');
        },
        clock: fakeClock,
      );

      service.start();
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      current = current.add(const Duration(milliseconds: 100));
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Filtered to appSession/appBackground only: the preceding
      // resumed call also emits appForeground (Step 3.3 behavior,
      // unchanged and un-awaited by design), which would otherwise
      // appear earliest in callOrder and isn't what this test is
      // verifying. The sequencing under test — appSession's save
      // fully completing before appBackground's save begins — is
      // still strictly checked below, not merely "both exist
      // eventually".
      final relevantCalls = callOrder
          .where((entry) =>
              entry.startsWith('appSession') ||
              entry.startsWith('appBackground'))
          .toList();

      expect(relevantCalls, [
        'appSession:start',
        'appSession:end',
        'appBackground:start',
        'appBackground:end',
      ]);

      await service.stop();
    });
  });
}
