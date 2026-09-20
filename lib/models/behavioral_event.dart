/// A single raw behavioral event. Originally screen-state only (Step 1);
/// later steps added app lifecycle, app session duration, screen
/// session duration, and (Step 3.6) derived app-usage session duration.
/// No aggregation or interpretation happens here — that's a later
/// step's job.
enum BehavioralEventType {
  screenOn,
  screenOff,
  userPresent,
  appForeground,
  appBackground,
  appSession,
  screenSession,
  appUsageSession,
}

class BehavioralEvent {
  final BehavioralEventType type;
  final DateTime timestamp;

  /// Only meaningful (and required) for appSession, screenSession, and
  /// appUsageSession: the completed session's duration in milliseconds.
  /// Null for every other event type.
  final int? durationMs;

  /// Only meaningful (and required) for appUsageSession: the Android
  /// package name the session belongs to. Null for every other event
  /// type. NeuralSafe's own package is never represented here — it is
  /// excluded at the AppUsageService layer.
  final String? packageName;

  const BehavioralEvent({
    required this.type,
    required this.timestamp,
    this.durationMs,
    this.packageName,
  })  : assert(
          (type != BehavioralEventType.appSession &&
                  type != BehavioralEventType.screenSession &&
                  type != BehavioralEventType.appUsageSession) ||
              durationMs != null,
          'appSession/screenSession/appUsageSession events require a '
          'non-null durationMs.',
        ),
        assert(
          durationMs == null || durationMs >= 0,
          'durationMs must be null or a non-negative integer.',
        ),
        assert(
          type != BehavioralEventType.appUsageSession ||
              (packageName != null && packageName != ''),
          'appUsageSession events require a non-empty packageName.',
        );

  /// Parses the native 'neuralsafe/screen_state' EventChannel's payload.
  /// Screen-state events only — every derived/lifecycle event type
  /// never travels through this channel, so no such cases exist here
  /// by design. appUsageSession in particular is derived entirely on
  /// the Dart side from polled UsageStatsManager data, never a native
  /// channel event.
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
    // Only written when present — every other event type's persisted
    // shape is unchanged.
    if (durationMs != null) {
      map['durationMs'] = durationMs;
    }
    if (packageName != null) {
      map['packageName'] = packageName;
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
      'appUsageSession' => BehavioralEventType.appUsageSession,
      _ => throw ArgumentError('Unknown behavioral event type: $rawType'),
    };

    int? durationMs;
    if (type == BehavioralEventType.appSession ||
        type == BehavioralEventType.screenSession ||
        type == BehavioralEventType.appUsageSession) {
      final rawDuration = map['durationMs'];
      if (rawDuration is int && rawDuration >= 0) {
        durationMs = rawDuration;
      } else {
        throw ArgumentError(
          'Event type ${type.name} missing a valid durationMs: $rawDuration',
        );
      }
    }

    String? packageName;
    if (type == BehavioralEventType.appUsageSession) {
      final rawPackageName = map['packageName'];
      if (rawPackageName is String && rawPackageName.isNotEmpty) {
        packageName = rawPackageName;
      } else {
        throw ArgumentError(
          'appUsageSession event missing a valid packageName: '
          '$rawPackageName',
        );
      }
    }

    return BehavioralEvent(
      type: type,
      timestamp: rawTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp)
          : DateTime.now(),
      durationMs: durationMs,
      packageName: packageName,
    );
  }

  @override
  String toString() {
    final durationPart = durationMs != null ? ', durationMs: $durationMs' : '';
    final packagePart =
        packageName != null ? ', packageName: $packageName' : '';
    return 'BehavioralEvent(type: ${type.name}, timestamp: $timestamp'
        '$durationPart$packagePart)';
  }
}
