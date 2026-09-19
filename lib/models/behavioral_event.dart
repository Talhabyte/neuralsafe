/// A single raw behavioral event. Originally screen-state only (Step 1);
/// Step 3.3 added the app's own foreground/background lifecycle; Step
/// 3.4 added a completed-foreground-session duration signal; Step 3.5
/// adds a derived device screen-on session duration signal. No
/// aggregation or interpretation happens here — that's a later step's
/// job.
enum BehavioralEventType {
  screenOn,
  screenOff,
  userPresent,
  appForeground,
  appBackground,
  appSession,
  screenSession,
}

class BehavioralEvent {
  final BehavioralEventType type;
  final DateTime timestamp;

  /// Only meaningful (and required) for [BehavioralEventType.appSession]
  /// and [BehavioralEventType.screenSession]: the completed session's
  /// duration in milliseconds. Null for every other event type.
  final int? durationMs;

  const BehavioralEvent({
    required this.type,
    required this.timestamp,
    this.durationMs,
  })  : assert(
          (type != BehavioralEventType.appSession &&
                  type != BehavioralEventType.screenSession) ||
              durationMs != null,
          'appSession/screenSession events require a non-null durationMs.',
        ),
        assert(
          durationMs == null || durationMs >= 0,
          'durationMs must be null or a non-negative integer.',
        );

  /// Parses the native 'neuralsafe/screen_state' EventChannel's payload.
  /// Screen-state events only — appForeground/appBackground/appSession/
  /// screenSession events never travel through this channel, so no
  /// such cases exist here by design. screenSession in particular is a
  /// Flutter-side derived event, never a native channel event.
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
    final map = <String, dynamic>{
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
    // Only written for appSession/screenSession — every other event
    // type's persisted shape is unchanged.
    if (durationMs != null) {
      map['durationMs'] = durationMs;
    }
    return map;
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
      'appSession' => BehavioralEventType.appSession,
      'screenSession' => BehavioralEventType.screenSession,
      _ => throw ArgumentError('Unknown behavioral event type: $rawType'),
    };

    int? durationMs;
    if (type == BehavioralEventType.appSession ||
        type == BehavioralEventType.screenSession) {
      final rawDuration = map['durationMs'];
      if (rawDuration is int && rawDuration >= 0) {
        durationMs = rawDuration;
      } else {
        throw ArgumentError(
          'Event type ${type.name} missing a valid durationMs: $rawDuration',
        );
      }
    }

    return BehavioralEvent(
      type: type,
      timestamp: rawTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp)
          : DateTime.now(),
      durationMs: durationMs,
    );
  }

  @override
  String toString() {
    final durationPart = durationMs != null ? ', durationMs: $durationMs' : '';
    return 'BehavioralEvent(type: ${type.name}, timestamp: $timestamp'
        '$durationPart)';
  }
}
