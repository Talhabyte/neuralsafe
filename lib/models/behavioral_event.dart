/// A single raw screen-state event received from the native platform
/// channel. Step 1 scope only — no aggregation, no interpretation, no
/// persistence logic here. That comes later (Step 2 persists these,
/// Step 6 aggregates them into daily features).
enum BehavioralEventType { screenOn, screenOff, userPresent }

class BehavioralEvent {
  final BehavioralEventType type;
  final DateTime timestamp;

  const BehavioralEvent({required this.type, required this.timestamp});

  factory BehavioralEvent.fromChannelMap(Map<dynamic, dynamic> map) {
    final rawTimestamp = map['timestamp'] as int?;
    return BehavioralEvent(
      type: _typeFromString(map['type'] as String?),
      timestamp: rawTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp)
          : DateTime.now(),
    );
  }

  static BehavioralEventType _typeFromString(String? raw) {
    switch (raw) {
      case 'screen_on':
        return BehavioralEventType.screenOn;
      case 'screen_off':
        return BehavioralEventType.screenOff;
      case 'user_present':
        return BehavioralEventType.userPresent;
      default:
        throw ArgumentError('Unknown behavioral event type: $raw');
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// STEP 2 ADDITION: the true inverse of toMap() — for deserializing
  /// events already persisted in the encrypted vault. Distinct from
  /// fromChannelMap(), which parses the native EventChannel's own
  /// snake_case payload format instead. Do not use these two
  /// interchangeably; they read different string formats.
  factory BehavioralEvent.fromMap(Map<dynamic, dynamic> map) {
    final rawTimestamp = map['timestamp'] as int?;
    final rawType = map['type'] as String?;

    final type = switch (rawType) {
      'screenOn' => BehavioralEventType.screenOn,
      'screenOff' => BehavioralEventType.screenOff,
      'userPresent' => BehavioralEventType.userPresent,
      _ => throw ArgumentError('Unknown behavioral event type: $rawType'),
    };

    return BehavioralEvent(
      type: type,
      timestamp: rawTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp)
          : DateTime.now(),
    );
  }

  @override
  String toString() =>
      'BehavioralEvent(type: ${type.name}, timestamp: $timestamp)';
}
