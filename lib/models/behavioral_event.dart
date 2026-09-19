/// A single raw behavioral event. Originally screen-state only (Step 1);
/// Step 3.3 adds the NeuralSafe app's own foreground/background
/// lifecycle as an additional signal source. No aggregation or
/// interpretation happens here — that's a later step's job.
enum BehavioralEventType {
  screenOn,
  screenOff,
  userPresent,
  appForeground,
  appBackground,
}

class BehavioralEvent {
  final BehavioralEventType type;
  final DateTime timestamp;

  const BehavioralEvent({required this.type, required this.timestamp});

  /// Parses the native 'neuralsafe/screen_state' EventChannel's payload.
  /// Screen-state events only — app lifecycle events never travel
  /// through this channel, so no appForeground/appBackground cases
  /// exist here by design.
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

  /// The true inverse of toMap() — for deserializing events already
  /// persisted in the encrypted vault. Distinct from fromChannelMap(),
  /// which parses the native EventChannel's own snake_case payload
  /// format instead.
  factory BehavioralEvent.fromMap(Map<dynamic, dynamic> map) {
    final rawTimestamp = map['timestamp'] as int?;
    final rawType = map['type'] as String?;

    final type = switch (rawType) {
      'screenOn' => BehavioralEventType.screenOn,
      'screenOff' => BehavioralEventType.screenOff,
      'userPresent' => BehavioralEventType.userPresent,
      'appForeground' => BehavioralEventType.appForeground,
      'appBackground' => BehavioralEventType.appBackground,
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
