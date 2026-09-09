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

  /// Included now for Step 2's benefit (persistence), even though
  /// nothing in Step 1 calls this yet.
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() =>
      'BehavioralEvent(type: ${type.name}, timestamp: $timestamp)';
}
