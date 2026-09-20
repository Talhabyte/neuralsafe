import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/behavioral_event_aggregator.dart';

void main() {
  group('BehavioralEventAggregator', () {
    late DateTime current;
    DateTime fakeClock() => current;
    late List<BehavioralEvent> repositoryEvents;
    List<BehavioralEvent> fakeLoadEvents() => List.of(repositoryEvents);

    setUp(() {
      current = DateTime(2026, 1, 1, 10, 0, 0);
      repositoryEvents = [];
    });

    test('start() with no events yet produces no batches', () async {
      final batches = <List<BehavioralEvent>>[];
      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
        onBatch: batches.add,
      );

      aggregator.start();
      await aggregator.poll();

      expect(batches, isEmpty);

      aggregator.stop();
      await aggregator.dispose();
    });

    test(
        'events persisted after start() are delivered as a batch via '
        'onBatch and the stream', () async {
      final batches = <List<BehavioralEvent>>[];
      final streamBatches = <List<BehavioralEvent>>[];

      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
        onBatch: batches.add,
      );

      // Subscribe BEFORE start(): the batches stream is a broadcast
      // stream, which only delivers to listeners subscribed at the
      // moment of emission.
      final sub = aggregator.batches.listen(streamBatches.add);

      aggregator.start();

      current = current.add(const Duration(seconds: 1));
      repositoryEvents = [
        BehavioralEvent(type: BehavioralEventType.screenOn, timestamp: current),
      ];

      await aggregator.poll();
      // StreamController.broadcast().add() schedules delivery to
      // listeners on the microtask queue rather than delivering
      // synchronously. poll()'s Future completes as soon as add() is
      // called, not after listeners have actually run, so an extra
      // microtask pump is needed here for streamBatches to be
      // populated before the assertions below run.
      await Future<void>.microtask(() {});

      expect(batches.length, 1);
      expect(batches.first.length, 1);
      expect(batches.first.first.type, BehavioralEventType.screenOn);
      expect(streamBatches.length, 1);

      await sub.cancel();
      aggregator.stop();
      await aggregator.dispose();
    });

    test('does not re-deliver events already included in a prior batch',
        () async {
      final batches = <List<BehavioralEvent>>[];
      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
        onBatch: batches.add,
      );

      aggregator.start();

      current = current.add(const Duration(seconds: 1));
      repositoryEvents = [
        BehavioralEvent(type: BehavioralEventType.screenOn, timestamp: current),
      ];
      await aggregator.poll();
      expect(batches.length, 1);

      // No new events added to the repository; a second poll should
      // not re-deliver the same event.
      await aggregator.poll();
      expect(batches.length, 1);

      aggregator.stop();
      await aggregator.dispose();
    });

    test(
        'a full new batch is delivered on the next poll after new '
        'events accumulate', () async {
      final batches = <List<BehavioralEvent>>[];
      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
        onBatch: batches.add,
      );

      aggregator.start();

      current = current.add(const Duration(seconds: 1));
      repositoryEvents = [
        BehavioralEvent(type: BehavioralEventType.screenOn, timestamp: current),
      ];
      await aggregator.poll();
      expect(batches.length, 1);

      current = current.add(const Duration(seconds: 1));
      repositoryEvents = [
        ...repositoryEvents,
        BehavioralEvent(
            type: BehavioralEventType.screenOff, timestamp: current),
      ];
      await aggregator.poll();

      expect(batches.length, 2);
      expect(batches[1].length, 1);
      expect(batches[1].first.type, BehavioralEventType.screenOff);

      aggregator.stop();
      await aggregator.dispose();
    });

    test(
        'events tied exactly at the previous cursor boundary are not '
        'duplicated across polls', () async {
      final batches = <List<BehavioralEvent>>[];
      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
        onBatch: batches.add,
      );

      aggregator.start();

      current = current.add(const Duration(seconds: 1));
      final boundaryTimestamp = current;
      repositoryEvents = [
        BehavioralEvent(
            type: BehavioralEventType.screenOn, timestamp: boundaryTimestamp),
        BehavioralEvent(
            type: BehavioralEventType.userPresent,
            timestamp: boundaryTimestamp),
      ];
      await aggregator.poll();
      expect(batches.single.length, 2);

      // Repository still returns the same two boundary-timestamped
      // events (as loadAll() naturally would, since nothing new has
      // been appended) — they must not be redelivered.
      await aggregator.poll();
      expect(batches.length, 1);

      aggregator.stop();
      await aggregator.dispose();
    });

    test('overlapping poll() calls are prevented by the concurrency guard',
        () async {
      var loadCallCount = 0;
      final aggregator = BehavioralEventAggregator(
        loadEvents: () {
          loadCallCount++;
          return repositoryEvents;
        },
        clock: fakeClock,
      );

      // start() itself calls loadEvents() once, to seed boundary keys —
      // baseline the count from here so the assertion below is scoped
      // strictly to the two poll() calls under test.
      aggregator.start();
      final countAfterStart = loadCallCount;

      current = current.add(const Duration(seconds: 1));
      repositoryEvents = [
        BehavioralEvent(type: BehavioralEventType.screenOn, timestamp: current),
      ];

      // poll() now genuinely yields (via the internal microtask await)
      // before doing any real work, so calling it twice back-to-back
      // is a real overlap: the first call synchronously acquires the
      // guard and suspends; the second call, invoked before the first
      // resumes, must observe the guard already held and return
      // immediately without loading anything.
      final firstPoll = aggregator.poll();
      final secondPoll = aggregator.poll();

      await Future.wait([firstPoll, secondPoll]);

      expect(loadCallCount, countAfterStart + 1);

      aggregator.stop();
      await aggregator.dispose();
    });

    test(
        'start() does not import historical backlog: only events '
        'after start() time are ever considered', () async {
      // An event already "persisted" before start() is called, timed
      // exactly at what will become the start() cursor.
      repositoryEvents = [
        BehavioralEvent(type: BehavioralEventType.screenOn, timestamp: current),
      ];

      final batches = <List<BehavioralEvent>>[];
      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
        onBatch: batches.add,
      );

      aggregator.start(); // cursor = current, and this pre-existing
      // event is seeded into _recentBoundaryKeys since it is tied
      // exactly at the cursor timestamp.
      await aggregator.poll();

      expect(batches, isEmpty);

      aggregator.stop();
      await aggregator.dispose();
    });

    test('stop() halts further batches even if new events appear', () async {
      final batches = <List<BehavioralEvent>>[];
      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
        onBatch: batches.add,
      );

      aggregator.start();
      aggregator.stop();

      current = current.add(const Duration(seconds: 5));
      repositoryEvents = [
        BehavioralEvent(type: BehavioralEventType.screenOn, timestamp: current),
      ];
      await aggregator
          .poll(); // poll() itself checks isRunning and returns early

      expect(batches, isEmpty);

      await aggregator.dispose();
    });

    test('updateWindow() changes the reported window', () async {
      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
        window: const Duration(seconds: 60),
      );

      expect(aggregator.window, const Duration(seconds: 60));

      aggregator.start();
      aggregator.updateWindow(const Duration(seconds: 15));

      expect(aggregator.window, const Duration(seconds: 15));
      expect(aggregator.isRunning, true);

      aggregator.stop();
      await aggregator.dispose();
    });

    test('isRunning reflects state correctly across start/stop', () async {
      final aggregator = BehavioralEventAggregator(
        loadEvents: fakeLoadEvents,
        clock: fakeClock,
      );

      expect(aggregator.isRunning, false);
      aggregator.start();
      expect(aggregator.isRunning, true);
      aggregator.stop();
      expect(aggregator.isRunning, false);

      await aggregator.dispose();
    });
  });
}
