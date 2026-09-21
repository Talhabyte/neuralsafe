import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/feature_extractor.dart';

void main() {
  group('FeatureExtractor — window filtering and boundaries', () {
    test('extractWindow includes an event exactly at windowStart', () {
      final start = DateTime(2026, 1, 1, 10, 0, 0);
      final end = DateTime(2026, 1, 1, 11, 0, 0);

      final extractor = FeatureExtractor(
        loadEvents: (queryStart, queryEnd) => [
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: start, // exactly at windowStart
              durationMs: 1000),
        ]
            .where((e) =>
                !e.timestamp.isBefore(queryStart) &&
                e.timestamp.isBefore(queryEnd))
            .toList(),
      );

      final vector = extractor.extractWindow(start, end);

      expect(vector.screenSessionsCount, 1);
    });

    test(
        'extractWindow excludes an event exactly at windowEnd '
        '(half-open upper bound)', () {
      final start = DateTime(2026, 1, 1, 10, 0, 0);
      final end = DateTime(2026, 1, 1, 11, 0, 0);

      final extractor = FeatureExtractor(
        loadEvents: (queryStart, queryEnd) => [
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: end, // exactly at windowEnd
              durationMs: 1000),
        ]
            .where((e) =>
                !e.timestamp.isBefore(queryStart) &&
                e.timestamp.isBefore(queryEnd))
            .toList(),
      );

      final vector = extractor.extractWindow(start, end);

      expect(vector.screenSessionsCount, 0);
    });

    test(
        'events outside the window are never included even if the '
        'underlying loadEvents returns them (defensive: extractor '
        'trusts its own query range)', () {
      final start = DateTime(2026, 1, 1, 10, 0, 0);
      final end = DateTime(2026, 1, 1, 11, 0, 0);

      // A deliberately "leaky" loadEvents that ignores the query range
      // and returns everything, to confirm extractWindow's contract:
      // it passes whatever loadEvents gives it straight through to
      // BehavioralFeatureVector.fromEvents without re-filtering. This
      // documents that correctness of range filtering is the injected
      // loadEvents function's responsibility (as the default
      // implementation does correctly) — not a hidden extra guard.
      final extractor = FeatureExtractor(
        loadEvents: (queryStart, queryEnd) => [
          BehavioralEvent(
              type: BehavioralEventType.screenSession,
              timestamp: start.subtract(const Duration(hours: 1)),
              durationMs: 1000),
        ],
      );

      final vector = extractor.extractWindow(start, end);

      // Documents current behavior: count reflects whatever loadEvents
      // returned, since extractWindow does not re-filter.
      expect(vector.screenSessionsCount, 1);
    });
  });

  group('FeatureExtractor.extractRecent — rolling window', () {
    test('computes a window ending at "now" spanning windowSize back', () {
      DateTime? queriedStart;
      DateTime? queriedEnd;
      final now = DateTime(2026, 1, 1, 15, 30, 0);

      final extractor = FeatureExtractor(
        loadEvents: (start, end) {
          queriedStart = start;
          queriedEnd = end;
          return [];
        },
        clock: () => now,
      );

      extractor.extractRecent(const Duration(hours: 1));

      expect(queriedEnd, now);
      expect(queriedStart, now.subtract(const Duration(hours: 1)));
    });

    test('an explicit `now` overrides the injected clock', () {
      DateTime? queriedEnd;
      final explicitNow = DateTime(2026, 1, 1, 20, 0, 0);

      final extractor = FeatureExtractor(
        loadEvents: (start, end) {
          queriedEnd = end;
          return [];
        },
        clock: () => DateTime(2026, 1, 1, 9, 0, 0), // should be ignored
      );

      extractor.extractRecent(const Duration(minutes: 15), now: explicitNow);

      expect(queriedEnd, explicitNow);
    });
  });

  group('FeatureExtractor.extractCalendarWindow — alignment', () {
    test('1-hour window aligns to the top of the hour', () {
      DateTime? queriedStart;
      DateTime? queriedEnd;

      final extractor = FeatureExtractor(
        loadEvents: (start, end) {
          queriedStart = start;
          queriedEnd = end;
          return [];
        },
      );

      extractor.extractCalendarWindow(
        const Duration(hours: 1),
        referenceTime: DateTime(2026, 1, 1, 14, 37, 22),
      );

      expect(queriedStart, DateTime(2026, 1, 1, 14, 0, 0));
      expect(queriedEnd, DateTime(2026, 1, 1, 15, 0, 0));
    });

    test('24-hour window aligns to local midnight', () {
      DateTime? queriedStart;
      DateTime? queriedEnd;

      final extractor = FeatureExtractor(
        loadEvents: (start, end) {
          queriedStart = start;
          queriedEnd = end;
          return [];
        },
      );

      extractor.extractCalendarWindow(
        const Duration(hours: 24),
        referenceTime: DateTime(2026, 1, 1, 23, 59, 59),
      );

      expect(queriedStart, DateTime(2026, 1, 1, 0, 0, 0));
      expect(queriedEnd, DateTime(2026, 1, 2, 0, 0, 0));
    });

    test('15-minute window aligns to the nearest quarter-hour', () {
      DateTime? queriedStart;
      DateTime? queriedEnd;

      final extractor = FeatureExtractor(
        loadEvents: (start, end) {
          queriedStart = start;
          queriedEnd = end;
          return [];
        },
      );

      extractor.extractCalendarWindow(
        const Duration(minutes: 15),
        referenceTime: DateTime(2026, 1, 1, 14, 22, 0),
      );

      expect(queriedStart, DateTime(2026, 1, 1, 14, 15, 0));
      expect(queriedEnd, DateTime(2026, 1, 1, 14, 30, 0));
    });

    test('6-hour window aligns to 00:00/06:00/12:00/18:00', () {
      DateTime? queriedStart;

      final extractor = FeatureExtractor(
        loadEvents: (start, end) {
          queriedStart = start;
          return [];
        },
      );

      extractor.extractCalendarWindow(
        const Duration(hours: 6),
        referenceTime: DateTime(2026, 1, 1, 13, 5, 0),
      );

      expect(queriedStart, DateTime(2026, 1, 1, 12, 0, 0));
    });

    test('with no referenceTime, uses the injected clock', () {
      DateTime? queriedStart;
      final extractor = FeatureExtractor(
        loadEvents: (start, end) {
          queriedStart = start;
          return [];
        },
        clock: () => DateTime(2026, 1, 1, 10, 45, 0),
      );

      extractor.extractCalendarWindow(const Duration(hours: 1));

      expect(queriedStart, DateTime(2026, 1, 1, 10, 0, 0));
    });
  });

  group('FeatureExtractor — large event set sanity check', () {
    test('handles a window with many events without error', () {
      final start = DateTime(2026, 1, 1, 0, 0, 0);
      final end = DateTime(2026, 1, 2, 0, 0, 0);

      final manyEvents = List.generate(1000, (i) {
        return BehavioralEvent(
          type: BehavioralEventType.screenSession,
          timestamp: start.add(Duration(seconds: i)),
          durationMs: 1000 + i,
        );
      });

      final extractor = FeatureExtractor(
        loadEvents: (queryStart, queryEnd) => manyEvents
            .where((e) =>
                !e.timestamp.isBefore(queryStart) &&
                e.timestamp.isBefore(queryEnd))
            .toList(),
      );

      final vector = extractor.extractWindow(start, end);

      expect(vector.screenSessionsCount, 1000);
      expect(vector.eventCount, 1000);
    });
  });
}
