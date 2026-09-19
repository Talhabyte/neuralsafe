import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/screen_session_service.dart';

void main() {
  group('ScreenSessionService', () {
    late DateTime current;
    DateTime fakeClock() => current;

    setUp(() {
      current = DateTime(2026, 1, 1, 12, 0, 0);
    });

    BehavioralEvent screenOnAt(DateTime t) =>
        BehavioralEvent(type: BehavioralEventType.screenOn, timestamp: t);
    BehavioralEvent screenOffAt(DateTime t) =>
        BehavioralEvent(type: BehavioralEventType.screenOff, timestamp: t);
    BehavioralEvent userPresentAt(DateTime t) =>
        BehavioralEvent(type: BehavioralEventType.userPresent, timestamp: t);

    test('screen_on starts a screen session (no event emitted yet)', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOnAt(current));

      expect(savedEvents, isEmpty);

      await service.stop();
    });

    test(
        'screen_on followed by screen_off creates exactly one '
        'screenSession', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOnAt(current));
      current = current.add(const Duration(milliseconds: 800));
      await service.handleEvent(screenOffAt(current));

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.screenSession)
          .toList();
      expect(sessionEvents.length, 1);

      await service.stop();
    });

    test('a 1500ms fake-clock interval produces durationMs = 1500', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOnAt(current));
      current = current.add(const Duration(milliseconds: 1500));
      await service.handleEvent(screenOffAt(current));

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.screenSession)
          .toList();
      expect(sessionEvents.single.durationMs, 1500);

      await service.stop();
    });

    test('duration 0 works (screen_off at the same instant as screen_on)',
        () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOnAt(current));
      await service.handleEvent(screenOffAt(current)); // no clock advance

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.screenSession)
          .toList();
      expect(sessionEvents.single.durationMs, 0);

      await service.stop();
    });

    test('a negative computed duration is clamped to 0', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOnAt(current));
      // Force a negative interval by moving the fake clock backwards
      // before screen_off — simulates a pathological clock scenario.
      current = current.subtract(const Duration(milliseconds: 500));
      await service.handleEvent(screenOffAt(current));

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.screenSession)
          .toList();
      expect(sessionEvents.single.durationMs, 0);

      await service.stop();
    });

    test(
        'screen_off without an active screen session creates no '
        'screenSession', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOffAt(current));

      expect(savedEvents, isEmpty);

      await service.stop();
    });

    test('duplicate screen_off does not create a second screenSession',
        () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOnAt(current));
      current = current.add(const Duration(milliseconds: 200));
      await service.handleEvent(screenOffAt(current));
      await service.handleEvent(screenOffAt(current)); // duplicate

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.screenSession)
          .toList();
      expect(sessionEvents.length, 1);

      await service.stop();
    });

    test('duplicate screen_on does not reset the original start time',
        () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOnAt(current));

      current = current.add(const Duration(milliseconds: 300));
      await service.handleEvent(screenOnAt(current)); // duplicate

      current = current.add(const Duration(milliseconds: 700));
      await service.handleEvent(screenOffAt(current));

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.screenSession)
          .toList();
      expect(sessionEvents.length, 1);
      // Duration should span from the FIRST screen_on (1000ms total),
      // not from the duplicate screen_on (which would be 700ms).
      expect(sessionEvents.first.durationMs, 1000);

      await service.stop();
    });

    test(
        'a second screen_on -> screen_off cycle creates a second '
        'independent screenSession with correct duration', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();

      await service.handleEvent(screenOnAt(current));
      current = current.add(const Duration(milliseconds: 400));
      await service.handleEvent(screenOffAt(current));

      current = current.add(const Duration(milliseconds: 100));
      await service.handleEvent(screenOnAt(current));
      current = current.add(const Duration(milliseconds: 900));
      await service.handleEvent(screenOffAt(current));

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.screenSession)
          .toList();
      expect(sessionEvents.length, 2);
      expect(sessionEvents[0].durationMs, 400);
      expect(sessionEvents[1].durationMs, 900);

      await service.stop();
    });

    test('userPresent does not affect session state', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      service.start();
      await service.handleEvent(screenOnAt(current));
      await service.handleEvent(userPresentAt(current));
      current = current.add(const Duration(milliseconds: 250));
      await service.handleEvent(screenOffAt(current));

      final sessionEvents = savedEvents
          .where((e) => e.type == BehavioralEventType.screenSession)
          .toList();
      expect(sessionEvents.single.durationMs, 250);

      await service.stop();
    });

    test('handleEvent() does nothing before start() / after stop()', () async {
      final savedEvents = <BehavioralEvent>[];
      final service = ScreenSessionService(
        onEvent: (event) async => savedEvents.add(event),
        clock: fakeClock,
      );

      // Not started yet.
      await service.handleEvent(screenOnAt(current));
      current = current.add(const Duration(milliseconds: 500));
      await service.handleEvent(screenOffAt(current));
      expect(savedEvents, isEmpty);

      service.start();
      await service.handleEvent(screenOnAt(current));
      await service.stop();

      current = current.add(const Duration(milliseconds: 500));
      await service.handleEvent(screenOffAt(current));
      expect(savedEvents, isEmpty); // stopped before screen_off arrived
    });
  });
}
