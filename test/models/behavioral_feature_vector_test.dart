import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/models/behavioral_feature_vector.dart';

void main() {
  final windowStart = DateTime(2026, 1, 1, 10, 0, 0);
  final windowEnd = DateTime(2026, 1, 1, 11, 0, 0); // 1-hour window

  group('BehavioralFeatureVector.fromEvents — empty window', () {
    test('all counts are 0, all rates/means/medians are 0.0, no NaN', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.eventCount, 0);
      expect(vector.screenSessionsCount, 0);
      expect(vector.screenSessionsPerHour, 0.0);
      expect(vector.meanScreenSessionMs, 0.0);
      expect(vector.medianScreenSessionMs, 0.0);
      expect(vector.shortSessionRatio, 0.0);
      expect(vector.userPresentCount, 0);
      expect(vector.appSessionsCount, 0);
      expect(vector.meanAppSessionMs, 0.0);
      expect(vector.medianAppSessionMs, 0.0);
      expect(vector.appSessionsPerHour, 0.0);
      expect(vector.distinctPackagesCount, 0);
      expect(vector.totalAppUsageMs, 0);
      expect(vector.topPackageUsageRatio, 0.0);
      expect(vector.perPackageUsageMs, isEmpty);

      // Explicitly confirm no field is NaN (a 0/0 division bug would
      // produce this silently rather than throwing).
      expect(vector.screenSessionsPerHour.isNaN, false);
      expect(vector.meanScreenSessionMs.isNaN, false);
      expect(vector.medianScreenSessionMs.isNaN, false);
      expect(vector.shortSessionRatio.isNaN, false);
      expect(vector.topPackageUsageRatio.isNaN, false);
    });
  });

  group('BehavioralFeatureVector.fromEvents — single event', () {
    test('single screenSession: mean == median == that duration', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
            type: BehavioralEventType.screenSession,
            timestamp: windowStart.add(const Duration(minutes: 5)),
            durationMs: 3000,
          ),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.screenSessionsCount, 1);
      expect(vector.meanScreenSessionMs, 3000.0);
      expect(vector.medianScreenSessionMs, 3000.0);
      expect(vector.screenSessionsPerHour, 1.0); // 1 event / 1 hour window
    });

    test('single appUsageSession: topPackageUsageRatio == 1.0', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
            type: BehavioralEventType.appUsageSession,
            timestamp: windowStart.add(const Duration(minutes: 10)),
            durationMs: 4000,
            packageName: 'com.example.some_app',
          ),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.distinctPackagesCount, 1);
      expect(vector.totalAppUsageMs, 4000);
      expect(vector.topPackageUsageRatio, 1.0);
      expect(vector.perPackageUsageMs, {'com.example.some_app': 4000});
    });
  });

  group('BehavioralFeatureVector.fromEvents — mixed event types', () {
    test(
        'cross-type contamination does not occur: each feature only '
        'counts its own event type', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
            type: BehavioralEventType.screenOn,
            timestamp: windowStart.add(const Duration(minutes: 1)),
          ),
          BehavioralEvent(
            type: BehavioralEventType.screenOff,
            timestamp: windowStart.add(const Duration(minutes: 2)),
          ),
          BehavioralEvent(
            type: BehavioralEventType.userPresent,
            timestamp: windowStart.add(const Duration(minutes: 3)),
          ),
          BehavioralEvent(
            type: BehavioralEventType.screenSession,
            timestamp: windowStart.add(const Duration(minutes: 4)),
            durationMs: 2000,
          ),
          BehavioralEvent(
            type: BehavioralEventType.appForeground,
            timestamp: windowStart.add(const Duration(minutes: 5)),
          ),
          BehavioralEvent(
            type: BehavioralEventType.appBackground,
            timestamp: windowStart.add(const Duration(minutes: 6)),
          ),
          BehavioralEvent(
            type: BehavioralEventType.appSession,
            timestamp: windowStart.add(const Duration(minutes: 7)),
            durationMs: 6000,
          ),
          BehavioralEvent(
            type: BehavioralEventType.appUsageSession,
            timestamp: windowStart.add(const Duration(minutes: 8)),
            durationMs: 1000,
            packageName: 'com.example.app_a',
          ),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.eventCount, 8);
      expect(vector.screenSessionsCount, 1);
      expect(vector.appSessionsCount, 1);
      expect(vector.userPresentCount, 1);
      expect(vector.distinctPackagesCount, 1);
      // screenOn/screenOff/appForeground/appBackground contribute only
      // to eventCount — they have no dedicated feature of their own in
      // this vector, so none of the typed counts above should be
      // inflated by them.
      expect(vector.meanScreenSessionMs, 2000.0);
      expect(vector.meanAppSessionMs, 6000.0);
    });
  });

  group('BehavioralFeatureVector.fromEvents — shortSessionRatio', () {
    test('mixed short and long sessions computes the correct ratio', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
            type: BehavioralEventType.screenSession,
            timestamp: windowStart,
            durationMs: 2000, // short (< 5000 default threshold)
          ),
          BehavioralEvent(
            type: BehavioralEventType.screenSession,
            timestamp: windowStart.add(const Duration(minutes: 1)),
            durationMs: 4000, // short
          ),
          BehavioralEvent(
            type: BehavioralEventType.screenSession,
            timestamp: windowStart.add(const Duration(minutes: 2)),
            durationMs: 10000, // long
          ),
          BehavioralEvent(
            type: BehavioralEventType.screenSession,
            timestamp: windowStart.add(const Duration(minutes: 3)),
            durationMs: 15000, // long
          ),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.shortSessionRatio, 0.5); // 2 of 4 sessions are short
    });

    test('custom shortSessionThresholdMs is respected', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
            type: BehavioralEventType.screenSession,
            timestamp: windowStart,
            durationMs: 8000,
          ),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
        shortSessionThresholdMs: 10000,
      );

      expect(vector.shortSessionRatio, 1.0); // 8000 < 10000 threshold
    });
  });

  group('BehavioralFeatureVector.fromEvents — topPackageUsageRatio', () {
    test('even split across two packages produces ratio 0.5', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
            type: BehavioralEventType.appUsageSession,
            timestamp: windowStart,
            durationMs: 5000,
            packageName: 'com.example.app_a',
          ),
          BehavioralEvent(
            type: BehavioralEventType.appUsageSession,
            timestamp: windowStart.add(const Duration(minutes: 1)),
            durationMs: 5000,
            packageName: 'com.example.app_b',
          ),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.distinctPackagesCount, 2);
      expect(vector.totalAppUsageMs, 10000);
      expect(vector.topPackageUsageRatio, 0.5);
    });

    test(
        'multiple sessions for the same package sum correctly in '
        'perPackageUsageMs', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
            type: BehavioralEventType.appUsageSession,
            timestamp: windowStart,
            durationMs: 3000,
            packageName: 'com.example.app_a',
          ),
          BehavioralEvent(
            type: BehavioralEventType.appUsageSession,
            timestamp: windowStart.add(const Duration(minutes: 5)),
            durationMs: 4000,
            packageName: 'com.example.app_a',
          ),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.perPackageUsageMs, {'com.example.app_a': 7000});
      expect(vector.totalAppUsageMs, 7000);
      expect(vector.topPackageUsageRatio, 1.0);
    });
  });

  group('BehavioralFeatureVector — median computation', () {
    test('odd number of durations picks the true middle value', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: windowStart,
              durationMs: 1000),
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: windowStart,
              durationMs: 5000),
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: windowStart,
              durationMs: 3000),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.medianScreenSessionMs, 3000.0);
    });

    test('even number of durations averages the two middle values', () {
      final vector = BehavioralFeatureVector.fromEvents(
        events: [
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: windowStart,
              durationMs: 1000),
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: windowStart,
              durationMs: 2000),
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: windowStart,
              durationMs: 3000),
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: windowStart,
              durationMs: 4000),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      expect(vector.medianScreenSessionMs, 2500.0);
    });
  });

  group('BehavioralFeatureVector — construction validation', () {
    test('windowEnd before windowStart fails an assert', () {
      expect(
        () => BehavioralFeatureVector(
          windowStart: windowEnd,
          windowEnd: windowStart, // reversed
          eventCount: 0,
          screenSessionsCount: 0,
          screenSessionsPerHour: 0,
          meanScreenSessionMs: 0,
          medianScreenSessionMs: 0,
          shortSessionRatio: 0,
          userPresentCount: 0,
          appSessionsCount: 0,
          meanAppSessionMs: 0,
          medianAppSessionMs: 0,
          appSessionsPerHour: 0,
          distinctPackagesCount: 0,
          totalAppUsageMs: 0,
          topPackageUsageRatio: 0,
          perPackageUsageMs: const {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a ratio field outside [0, 1] fails an assert', () {
      expect(
        () => BehavioralFeatureVector(
          windowStart: windowStart,
          windowEnd: windowEnd,
          eventCount: 0,
          screenSessionsCount: 0,
          screenSessionsPerHour: 0,
          meanScreenSessionMs: 0,
          medianScreenSessionMs: 0,
          shortSessionRatio: 1.5, // invalid
          userPresentCount: 0,
          appSessionsCount: 0,
          meanAppSessionMs: 0,
          medianAppSessionMs: 0,
          appSessionsPerHour: 0,
          distinctPackagesCount: 0,
          totalAppUsageMs: 0,
          topPackageUsageRatio: 0,
          perPackageUsageMs: const {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a negative count field fails an assert', () {
      expect(
        () => BehavioralFeatureVector(
          windowStart: windowStart,
          windowEnd: windowEnd,
          eventCount: -1, // invalid
          screenSessionsCount: 0,
          screenSessionsPerHour: 0,
          meanScreenSessionMs: 0,
          medianScreenSessionMs: 0,
          shortSessionRatio: 0,
          userPresentCount: 0,
          appSessionsCount: 0,
          meanAppSessionMs: 0,
          medianAppSessionMs: 0,
          appSessionsPerHour: 0,
          distinctPackagesCount: 0,
          totalAppUsageMs: 0,
          topPackageUsageRatio: 0,
          perPackageUsageMs: const {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
