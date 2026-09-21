import 'behavioral_event.dart';

/// A pure, computed snapshot of behavioral activity over a fixed time
/// window. Contains ONLY numeric aggregates and counts derived from
/// already-persisted BehavioralEvents — no scoring, no thresholds, no
/// anomaly classification. That interpretation layer is explicitly out
/// of scope for Step 4.1 per the Phase 3/Phase 4 boundary.
///
/// Every numeric field is non-negative by construction; ratio fields
/// are constrained to [0, 1]. Constructing an invalid vector throws an
/// assertion error in debug/test builds, mirroring the validation
/// pattern already used in BehavioralEvent.
class BehavioralFeatureVector {
  final DateTime windowStart;
  final DateTime windowEnd;

  /// Total raw events considered in this window, across ALL event
  /// types (not just the ones with dedicated features below). A
  /// window with eventCount == 0 is meaningfully different from one
  /// where every derived feature happens to compute to zero from a
  /// nonzero event set (e.g. all sessions had exactly 0ms duration).
  final int eventCount;

  // --- Screen activity features ---
  final int screenSessionsCount;
  final double screenSessionsPerHour;
  final double meanScreenSessionMs;
  final double medianScreenSessionMs;
  final double shortSessionRatio;
  final int userPresentCount;

  // --- App lifecycle features ---
  final int appSessionsCount;
  final double meanAppSessionMs;
  final double medianAppSessionMs;
  final double appSessionsPerHour;

  // --- App usage features ---
  final int distinctPackagesCount;
  final int totalAppUsageMs;
  final double topPackageUsageRatio;
  final Map<String, int> perPackageUsageMs;

  BehavioralFeatureVector({
    required this.windowStart,
    required this.windowEnd,
    required this.eventCount,
    required this.screenSessionsCount,
    required this.screenSessionsPerHour,
    required this.meanScreenSessionMs,
    required this.medianScreenSessionMs,
    required this.shortSessionRatio,
    required this.userPresentCount,
    required this.appSessionsCount,
    required this.meanAppSessionMs,
    required this.medianAppSessionMs,
    required this.appSessionsPerHour,
    required this.distinctPackagesCount,
    required this.totalAppUsageMs,
    required this.topPackageUsageRatio,
    required this.perPackageUsageMs,
  })  : assert(!windowEnd.isBefore(windowStart),
            'windowEnd must not be before windowStart'),
        assert(eventCount >= 0, 'eventCount must be non-negative'),
        assert(screenSessionsCount >= 0,
            'screenSessionsCount must be non-negative'),
        assert(screenSessionsPerHour >= 0,
            'screenSessionsPerHour must be non-negative'),
        assert(meanScreenSessionMs >= 0,
            'meanScreenSessionMs must be non-negative'),
        assert(medianScreenSessionMs >= 0,
            'medianScreenSessionMs must be non-negative'),
        assert(shortSessionRatio >= 0 && shortSessionRatio <= 1,
            'shortSessionRatio must be within [0, 1]'),
        assert(userPresentCount >= 0, 'userPresentCount must be non-negative'),
        assert(appSessionsCount >= 0, 'appSessionsCount must be non-negative'),
        assert(meanAppSessionMs >= 0, 'meanAppSessionMs must be non-negative'),
        assert(
            medianAppSessionMs >= 0, 'medianAppSessionMs must be non-negative'),
        assert(
            appSessionsPerHour >= 0, 'appSessionsPerHour must be non-negative'),
        assert(distinctPackagesCount >= 0,
            'distinctPackagesCount must be non-negative'),
        assert(totalAppUsageMs >= 0, 'totalAppUsageMs must be non-negative'),
        assert(topPackageUsageRatio >= 0 && topPackageUsageRatio <= 1,
            'topPackageUsageRatio must be within [0, 1]');

  /// Computes a feature vector from a list of events ALREADY SCOPED to
  /// [windowStart, windowEnd) — this constructor does not itself filter
  /// by time range; that's FeatureExtractor's responsibility. This
  /// separation keeps feature arithmetic testable with plain, small,
  /// hand-built event lists with no window-filtering logic involved.
  ///
  /// [shortSessionThresholdMs] defines what counts as a "short" screen
  /// session for shortSessionRatio (default 5000ms / 5s).
  factory BehavioralFeatureVector.fromEvents({
    required List<BehavioralEvent> events,
    required DateTime windowStart,
    required DateTime windowEnd,
    int shortSessionThresholdMs = 5000,
  }) {
    final windowDurationHours =
        windowEnd.difference(windowStart).inMilliseconds / 3600000.0;

    final screenSessions = events
        .where((e) => e.type == BehavioralEventType.screenSession)
        .toList();
    final appSessions =
        events.where((e) => e.type == BehavioralEventType.appSession).toList();
    final appUsageSessions = events
        .where((e) => e.type == BehavioralEventType.appUsageSession)
        .toList();
    final userPresentCount =
        events.where((e) => e.type == BehavioralEventType.userPresent).length;

    final screenDurations = screenSessions.map((e) => e.durationMs!).toList();
    final appDurations = appSessions.map((e) => e.durationMs!).toList();

    final shortSessions =
        screenDurations.where((d) => d < shortSessionThresholdMs).length;

    final perPackageUsageMs = <String, int>{};
    for (final event in appUsageSessions) {
      final packageName = event.packageName!;
      perPackageUsageMs[packageName] =
          (perPackageUsageMs[packageName] ?? 0) + event.durationMs!;
    }
    final totalAppUsageMs =
        perPackageUsageMs.values.fold<int>(0, (sum, ms) => sum + ms);
    final topPackageUsageMs = perPackageUsageMs.values.isEmpty
        ? 0
        : perPackageUsageMs.values.reduce((a, b) => a > b ? a : b);

    return BehavioralFeatureVector(
      windowStart: windowStart,
      windowEnd: windowEnd,
      eventCount: events.length,
      screenSessionsCount: screenSessions.length,
      screenSessionsPerHour:
          _perHour(screenSessions.length, windowDurationHours),
      meanScreenSessionMs: _mean(screenDurations),
      medianScreenSessionMs: _median(screenDurations),
      shortSessionRatio:
          screenSessions.isEmpty ? 0.0 : shortSessions / screenSessions.length,
      userPresentCount: userPresentCount,
      appSessionsCount: appSessions.length,
      meanAppSessionMs: _mean(appDurations),
      medianAppSessionMs: _median(appDurations),
      appSessionsPerHour: _perHour(appSessions.length, windowDurationHours),
      distinctPackagesCount: perPackageUsageMs.length,
      totalAppUsageMs: totalAppUsageMs,
      topPackageUsageRatio:
          totalAppUsageMs == 0 ? 0.0 : topPackageUsageMs / totalAppUsageMs,
      perPackageUsageMs: perPackageUsageMs,
    );
  }

  static double _perHour(int count, double windowDurationHours) {
    if (windowDurationHours <= 0) return 0.0;
    return count / windowDurationHours;
  }

  static double _mean(List<int> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double _median(List<int> values) {
    if (values.isEmpty) return 0.0;
    final sorted = List<int>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid].toDouble();
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  @override
  String toString() {
    return 'BehavioralFeatureVector('
        'windowStart: $windowStart, windowEnd: $windowEnd, '
        'eventCount: $eventCount, '
        'screenSessionsCount: $screenSessionsCount, '
        'screenSessionsPerHour: $screenSessionsPerHour, '
        'meanScreenSessionMs: $meanScreenSessionMs, '
        'medianScreenSessionMs: $medianScreenSessionMs, '
        'shortSessionRatio: $shortSessionRatio, '
        'userPresentCount: $userPresentCount, '
        'appSessionsCount: $appSessionsCount, '
        'meanAppSessionMs: $meanAppSessionMs, '
        'medianAppSessionMs: $medianAppSessionMs, '
        'appSessionsPerHour: $appSessionsPerHour, '
        'distinctPackagesCount: $distinctPackagesCount, '
        'totalAppUsageMs: $totalAppUsageMs, '
        'topPackageUsageRatio: $topPackageUsageRatio, '
        'perPackageUsageMs: $perPackageUsageMs)';
  }
}
