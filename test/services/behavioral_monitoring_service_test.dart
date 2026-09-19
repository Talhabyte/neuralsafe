import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/behavioral_event_collector.dart';
import 'package:neuralsafe/services/behavioral_monitoring_service.dart';

void main() {
  group('BehavioralMonitoringService', () {
    test('start() starts monitoring and events are forwarded', () async {
      final controller = StreamController<BehavioralEvent>();
      final savedEvents = <BehavioralEvent>[];
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async => savedEvents.add(event),
      );
      final service = BehavioralMonitoringService.test(collector: collector);

      service.start();
      expect(service.isRunning, true);

      controller.add(BehavioralEvent(
        type: BehavioralEventType.screenOn,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(savedEvents.length, 1);
      expect(savedEvents.first.type, BehavioralEventType.screenOn);

      await service.stop();
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
      final service = BehavioralMonitoringService.test(collector: collector);

      service.start();
      service.start();
      service.start();

      controller.add(BehavioralEvent(
        type: BehavioralEventType.screenOff,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(savedEvents.length, 1);

      await service.stop();
      await controller.close();
    });

    test('stop() stops monitoring so further events are not forwarded',
        () async {
      final controller = StreamController<BehavioralEvent>();
      final savedEvents = <BehavioralEvent>[];
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async => savedEvents.add(event),
      );
      final service = BehavioralMonitoringService.test(collector: collector);

      service.start();
      await service.stop();

      expect(service.isRunning, false);

      controller.add(BehavioralEvent(
        type: BehavioralEventType.userPresent,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(savedEvents, isEmpty);

      await controller.close();
    });

    test('isRunning reflects state correctly across start/stop', () async {
      final controller = StreamController<BehavioralEvent>();
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async {},
      );
      final service = BehavioralMonitoringService.test(collector: collector);

      expect(service.isRunning, false);

      service.start();
      expect(service.isRunning, true);

      await service.stop();
      expect(service.isRunning, false);

      await controller.close();
    });
  });
}
