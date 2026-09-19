import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/app_lifecycle_service.dart';
import 'package:neuralsafe/services/behavioral_event_collector.dart';
import 'package:neuralsafe/services/behavioral_monitoring_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'screen events and app lifecycle events are both forwarded '
    'independently, with neither source interfering with the other',
    () async {
      final controller = StreamController<BehavioralEvent>();
      final screenEvents = <BehavioralEvent>[];
      final lifecycleEvents = <BehavioralEvent>[];

      final collector = BehavioralEventCollector(
        eventsStream: controller.stream,
        onEvent: (event) async => screenEvents.add(event),
      );
      final lifecycleService = AppLifecycleService(
        onEvent: (event) async => lifecycleEvents.add(event),
      );

      final service = BehavioralMonitoringService.test(
        collector: collector,
        lifecycleService: lifecycleService,
      );

      service.start();
      expect(service.isRunning, true);

      controller.add(BehavioralEvent(
        type: BehavioralEventType.screenOn,
        timestamp: DateTime.now(),
      ));
      lifecycleService.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(screenEvents.length, 1);
      expect(screenEvents.first.type, BehavioralEventType.screenOn);
      expect(lifecycleEvents.length, 1);
      expect(lifecycleEvents.first.type, BehavioralEventType.appForeground);

      await service.stop();
      expect(service.isRunning, false);

      await controller.close();
    },
  );
}
