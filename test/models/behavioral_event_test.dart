import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';

void main() {
  group('BehavioralEvent.toMap() / fromMap() round-trip', () {
    test('screenOn survives round-trip', () {
      final original = BehavioralEvent(
        type: BehavioralEventType.screenOn,
        timestamp: DateTime(2026, 3, 15, 9, 30, 0),
      );

      final reconstructed = BehavioralEvent.fromMap(original.toMap());

      expect(reconstructed.type, BehavioralEventType.screenOn);
      expect(reconstructed.timestamp, original.timestamp);
    });

    test('screenOff survives round-trip', () {
      final original = BehavioralEvent(
        type: BehavioralEventType.screenOff,
        timestamp: DateTime(2026, 3, 15, 22, 0, 0),
      );

      final reconstructed = BehavioralEvent.fromMap(original.toMap());

      expect(reconstructed.type, BehavioralEventType.screenOff);
      expect(reconstructed.timestamp, original.timestamp);
    });

    test('userPresent survives round-trip', () {
      final original = BehavioralEvent(
        type: BehavioralEventType.userPresent,
        timestamp: DateTime(2026, 3, 15, 9, 30, 5),
      );

      final reconstructed = BehavioralEvent.fromMap(original.toMap());

      expect(reconstructed.type, BehavioralEventType.userPresent);
      expect(reconstructed.timestamp, original.timestamp);
    });

    test('fromMap() throws ArgumentError for an unknown type string', () {
      final badMap = {
        'type': 'not_a_real_type',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      expect(() => BehavioralEvent.fromMap(badMap), throwsArgumentError);
    });

    test('fromMap() throws ArgumentError when type is missing entirely', () {
      final badMap = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      expect(() => BehavioralEvent.fromMap(badMap), throwsArgumentError);
    });

    test('toMap() produces the expected key shape', () {
      final event = BehavioralEvent(
        type: BehavioralEventType.screenOn,
        timestamp: DateTime(2026, 3, 15, 9, 30, 0),
      );

      final map = event.toMap();

      expect(map['type'], 'screenOn');
      expect(map['timestamp'],
          DateTime(2026, 3, 15, 9, 30, 0).millisecondsSinceEpoch);
      expect(map.containsKey('durationMs'), false);
    });

    test('appForeground toMap() does not include a durationMs key', () {
      final event = BehavioralEvent(
        type: BehavioralEventType.appForeground,
        timestamp: DateTime(2026, 3, 15, 9, 30, 0),
      );

      expect(event.toMap().containsKey('durationMs'), false);
    });
  });

  group('BehavioralEvent appSession (Step 3.4)', () {
    test('appSession survives round-trip with durationMs preserved', () {
      final original = BehavioralEvent(
        type: BehavioralEventType.appSession,
        timestamp: DateTime(2026, 3, 15, 9, 45, 0),
        durationMs: 12345,
      );

      final map = original.toMap();
      expect(map['durationMs'], 12345);

      final reconstructed = BehavioralEvent.fromMap(map);

      expect(reconstructed.type, BehavioralEventType.appSession);
      expect(reconstructed.timestamp, original.timestamp);
      expect(reconstructed.durationMs, 12345);
    });

    test('appSession with durationMs 0 survives round-trip', () {
      final original = BehavioralEvent(
        type: BehavioralEventType.appSession,
        timestamp: DateTime(2026, 3, 15, 9, 45, 0),
        durationMs: 0,
      );

      final reconstructed = BehavioralEvent.fromMap(original.toMap());

      expect(reconstructed.durationMs, 0);
    });

    test('constructing an appSession event without durationMs fails an assert',
        () {
      expect(
        () => BehavioralEvent(
          type: BehavioralEventType.appSession,
          timestamp: DateTime.now(),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('fromMap() throws ArgumentError for appSession missing durationMs',
        () {
      final badMap = {
        'type': 'appSession',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      expect(() => BehavioralEvent.fromMap(badMap), throwsArgumentError);
    });

    test(
        'fromMap() throws ArgumentError for appSession with negative durationMs',
        () {
      final badMap = {
        'type': 'appSession',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'durationMs': -5,
      };

      expect(() => BehavioralEvent.fromMap(badMap), throwsArgumentError);
    });

    test(
        'a pre-3.4 event map (no durationMs key) still deserializes '
        'correctly for non-appSession types', () {
      final legacyMap = {
        'type': 'appForeground',
        'timestamp': DateTime(2026, 1, 1, 8, 0, 0).millisecondsSinceEpoch,
      };

      final reconstructed = BehavioralEvent.fromMap(legacyMap);

      expect(reconstructed.type, BehavioralEventType.appForeground);
      expect(reconstructed.durationMs, isNull);
    });
  });
}
