import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/behavioral_event_collector.dart';

void main() {
  group('BehavioralEventCollector', () {
    test('forwards received events to the provided onEvent callback', () async {
      final controller = StreamController<BehavioralEvent>();
      final savedEvents = <BehavioralEvent>[];

      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async {
          savedEvents.add(event);
        },
      );

      collector.start();

      final event = BehavioralEvent(
        type: BehavioralEventType.screenOn,
        timestamp: DateTime(2026, 1, 1, 9, 0, 0),
      );
      controller.add(event);
      await Future<void>.delayed(Duration.zero);

      expect(savedEvents.length, 1);
      expect(savedEvents.first.type, BehavioralEventType.screenOn);
      expect(savedEvents.first.timestamp, event.timestamp);

      await collector.stop();
      await controller.close();
    });

    test('start() is idempotent and does not create duplicate subscriptions',
        () async {
      final controller = StreamController<BehavioralEvent>.broadcast();
      final savedEvents = <BehavioralEvent>[];

      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async => savedEvents.add(event),
      );

      collector.start();
      collector.start();
      collector.start();

      controller.add(BehavioralEvent(
        type: BehavioralEventType.screenOff,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(savedEvents.length, 1);

      await collector.stop();
      await controller.close();
    });

    test('stop() cancels the subscription so further events are not forwarded',
        () async {
      final controller = StreamController<BehavioralEvent>();
      final savedEvents = <BehavioralEvent>[];

      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async => savedEvents.add(event),
      );

      collector.start();
      await collector.stop();

      expect(collector.isRunning, false);

      controller.add(BehavioralEvent(
        type: BehavioralEventType.userPresent,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(savedEvents, isEmpty);

      await controller.close();
    });
  });
}
