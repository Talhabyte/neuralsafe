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
    });
  });
}
