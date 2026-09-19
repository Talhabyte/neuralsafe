import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/screen_session_service.dart';

/// Mirrors BehavioralMonitoringService.instance's ACTUAL production
/// onEvent wiring (Step 3.5, revised): for screenOff, the derived
/// screenSession is persisted BEFORE the raw event; for every other
/// type, the raw event is persisted first, exactly as it does today.
Future<void> productionStyleOnEvent({
  required BehavioralEvent event,
  required Future<void> Function(BehavioralEvent) rawSave,
  required ScreenSessionService screenSessionService,
}) async {
  if (event.type == BehavioralEventType.screenOff) {
    await screenSessionService.handleEvent(event);
    await rawSave(event);
  } else {
    await rawSave(event);
    await screenSessionService.handleEvent(event);
  }
}

void main() {
  test(
    'production wiring persists screenSession BEFORE the raw screenOff '
    'event, with no overlapping saves',
    () async {
      final callOrder = <String>[];

      Future<void> fakeRawSave(BehavioralEvent event) async {
        callOrder.add('raw(${event.type.name}):start');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        callOrder.add('raw(${event.type.name}):end');
      }

      var current = DateTime(2026, 1, 1, 9, 0, 0);
      final screenSessionService = ScreenSessionService(
        onEvent: (event) async {
          callOrder.add('screenSession:start');
          await Future<void>.delayed(const Duration(milliseconds: 5));
          callOrder.add('screenSession:end');
        },
        clock: () => current,
      );
      screenSessionService.start();

      // screen_on: raw save first (no session-persistence side effect
      // to race against), matching Step 3.1–3.4 unchanged behavior.
      await productionStyleOnEvent(
        event: BehavioralEvent(
            type: BehavioralEventType.screenOn, timestamp: current),
        rawSave: fakeRawSave,
        screenSessionService: screenSessionService,
      );

      current = current.add(const Duration(milliseconds: 1200));

      // screen_off: screenSession must be fully persisted BEFORE the
      // raw screenOff save begins.
      await productionStyleOnEvent(
        event: BehavioralEvent(
            type: BehavioralEventType.screenOff, timestamp: current),
        rawSave: fakeRawSave,
        screenSessionService: screenSessionService,
      );

      expect(callOrder, [
        'raw(screenOn):start',
        'raw(screenOn):end',
        'screenSession:start',
        'screenSession:end',
        'raw(screenOff):start',
        'raw(screenOff):end',
      ]);

      await screenSessionService.stop();
    },
  );

  test(
    'production wiring persists the raw event first for non-screenOff '
    'types (screenOn, userPresent), preserving Step 3.1–3.4 order',
    () async {
      final callOrder = <String>[];

      Future<void> fakeRawSave(BehavioralEvent event) async {
        callOrder.add('raw(${event.type.name}):start');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        callOrder.add('raw(${event.type.name}):end');
      }

      final current = DateTime(2026, 1, 1, 9, 0, 0);
      final screenSessionService = ScreenSessionService(
        onEvent: (event) async {
          callOrder.add('screenSession:start');
          await Future<void>.delayed(const Duration(milliseconds: 5));
          callOrder.add('screenSession:end');
        },
        clock: () => current,
      );
      screenSessionService.start();

      await productionStyleOnEvent(
        event: BehavioralEvent(
            type: BehavioralEventType.userPresent, timestamp: current),
        rawSave: fakeRawSave,
        screenSessionService: screenSessionService,
      );

      // userPresent triggers no screenSession side effect at all
      // (ScreenSessionService ignores it), so only the raw save
      // should appear.
      expect(callOrder, [
        'raw(userPresent):start',
        'raw(userPresent):end',
      ]);

      await screenSessionService.stop();
    },
  );

  test(
    'a full screen_on -> screen_off cycle through the production wiring '
    'still produces exactly one screenSession with the correct duration',
    () async {
      var current = DateTime(2026, 1, 1, 9, 0, 0);
      final savedSessions = <BehavioralEvent>[];
      final rawSaved = <BehavioralEvent>[];

      final screenSessionService = ScreenSessionService(
        onEvent: (event) async => savedSessions.add(event),
        clock: () => current,
      );
      screenSessionService.start();

      Future<void> rawSave(BehavioralEvent event) async {
        rawSaved.add(event);
      }

      await productionStyleOnEvent(
        event: BehavioralEvent(
            type: BehavioralEventType.screenOn, timestamp: current),
        rawSave: rawSave,
        screenSessionService: screenSessionService,
      );

      current = current.add(const Duration(milliseconds: 2000));

      await productionStyleOnEvent(
        event: BehavioralEvent(
            type: BehavioralEventType.screenOff, timestamp: current),
        rawSave: rawSave,
        screenSessionService: screenSessionService,
      );

      expect(savedSessions.length, 1);
      expect(savedSessions.first.type, BehavioralEventType.screenSession);
      expect(savedSessions.first.durationMs, 2000);
      expect(rawSaved.map((e) => e.type), [
        BehavioralEventType.screenOn,
        BehavioralEventType.screenOff,
      ]);

      await screenSessionService.stop();
    },
  );
}
