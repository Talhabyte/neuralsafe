import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/behavioral_event_aggregator.dart';
import 'package:neuralsafe/services/behavioral_event_collector.dart';
import 'package:neuralsafe/services/behavioral_monitoring_service.dart';

void main() {
  group('BehavioralMonitoringService + BehavioralEventAggregator wiring', () {
    test('start() starts the injected aggregator', () async {
      final controller = StreamController<BehavioralEvent>();
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async {},
      );
      final aggregator = BehavioralEventAggregator(
        loadEvents: () => [],
        clock: DateTime.now,
      );

      final service = BehavioralMonitoringService.test(
        collector: collector,
        aggregator: aggregator,
      );

      expect(aggregator.isRunning, false);

      service.start();

      expect(aggregator.isRunning, true);

      await service.stop();
      await controller.close();
      await aggregator.dispose();
    });

    test(
        'start() is idempotent for the aggregator: calling start() '
        'multiple times does not error or restart it unnecessarily', () async {
      final controller = StreamController<BehavioralEvent>();
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async {},
      );
      final aggregator = BehavioralEventAggregator(
        loadEvents: () => [],
        clock: DateTime.now,
      );

      final service = BehavioralMonitoringService.test(
        collector: collector,
        aggregator: aggregator,
      );

      service.start();
      service.start();
      service.start();

      expect(aggregator.isRunning, true);

      await service.stop();
      await controller.close();
      await aggregator.dispose();
    });

    test('stop() stops the injected aggregator', () async {
      final controller = StreamController<BehavioralEvent>();
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async {},
      );
      final aggregator = BehavioralEventAggregator(
        loadEvents: () => [],
        clock: DateTime.now,
      );

      final service = BehavioralMonitoringService.test(
        collector: collector,
        aggregator: aggregator,
      );

      service.start();
      expect(aggregator.isRunning, true);

      await service.stop();

      expect(aggregator.isRunning, false);

      await controller.close();
      await aggregator.dispose();
    });

    test(
        'isRunning is false overall if the aggregator is stopped while '
        'other sources remain running', () async {
      final controller = StreamController<BehavioralEvent>();
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async {},
      );
      final aggregator = BehavioralEventAggregator(
        loadEvents: () => [],
        clock: DateTime.now,
      );

      final service = BehavioralMonitoringService.test(
        collector: collector,
        aggregator: aggregator,
      );

      service.start();
      expect(service.isRunning, true);

      // Stop only the aggregator directly, bypassing
      // BehavioralMonitoringService.stop(), to isolate its
      // contribution to the combined isRunning getter.
      aggregator.stop();

      expect(service.isRunning, false);
      expect(collector.isRunning, true); // other sources unaffected

      await service.stop();
      await controller.close();
      await aggregator.dispose();
    });

    test(
        'isRunning treats a null aggregator as vacuously true '
        '(pre-existing behavior for tests that omit it, unaffected by '
        'this wiring)', () async {
      final controller = StreamController<BehavioralEvent>();
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async {},
      );

      final service = BehavioralMonitoringService.test(collector: collector);

      service.start();

      expect(service.isRunning, true);

      await service.stop();
      await controller.close();
    });

    test(
        'when the aggregator is running, it correctly picks up an '
        'event saved through the collector, proving the wiring reaches '
        'a real shared repository-style path end to end', () async {
      final controller = StreamController<BehavioralEvent>();
      final savedEvents = <BehavioralEvent>[];
      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async => savedEvents.add(event),
      );

      // The aggregator's loadEvents() here reads directly from the
      // same in-memory list the collector's onEvent populates —
      // standing in for "the shared repository both sides converge
      // on" without needing the real encrypted vault in this test.
      final aggregatorBatches = <List<BehavioralEvent>>[];
      final aggregator = BehavioralEventAggregator(
        loadEvents: () => List.of(savedEvents),
        clock: DateTime.now,
        onBatch: aggregatorBatches.add,
        window: const Duration(milliseconds: 20),
      );

      final service = BehavioralMonitoringService.test(
        collector: collector,
        aggregator: aggregator,
      );

      service.start();

      controller.add(BehavioralEvent(
        type: BehavioralEventType.screenOn,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(savedEvents.length, 1);
      expect(aggregatorBatches, isNotEmpty);
      expect(aggregatorBatches.first.first.type, BehavioralEventType.screenOn);

      await service.stop();
      await controller.close();
      await aggregator.dispose();
    });
  });
}
