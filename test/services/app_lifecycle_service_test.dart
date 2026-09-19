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

      // Simulates a stray callback arriving after stop() (e.g. a race
      // during teardown) — the internal isRunning guard should drop it.
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
}
