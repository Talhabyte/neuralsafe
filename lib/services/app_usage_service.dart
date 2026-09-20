import 'dart:async';

import '../models/behavioral_event.dart';
import 'app_usage_native_bridge.dart';
import 'behavioral_event_repository.dart';

/// The two app-usage transition types this service cares about. Any
/// other UsageEvents type is already filtered out on the native side
/// (AppUsageChannel.kt) and never reaches here.
enum AppUsageEventType { foreground, background }

/// A single raw usage transition for one package, as reported by
/// UsageStatsManager via the native bridge. Contains ONLY package
/// name, transition type, and timestamp — no other app data.
class AppUsageRawEvent {
  final String packageName;
  final AppUsageEventType type;
  final DateTime timestamp;

  const AppUsageRawEvent({
    required this.packageName,
    required this.type,
    required this.timestamp,
  });
}

/// Polls Android's UsageStatsManager (via AppUsageNativeBridge) for
/// per-package foreground/background transitions and derives
/// appUsageSession BehavioralEvents (Step 3.6).
///
/// Explicit foreground/background events for a given package are the
/// ONLY authoritative boundary for that package's own session — a
/// different package becoming foreground is never treated as
/// implicitly backgrounding another package.
///
/// Uses a monotonic cursor: on start(), the cursor is initialized to
/// "now" (no historical backlog is ever imported), and it only ever
/// advances forward, and only after a poll's derived events have all
/// been successfully persisted.
///
/// [onEvent] is injectable (defaults to BehavioralEventRepository().save
/// for standalone use; production wiring in BehavioralMonitoringService
/// always passes an explicit serialized writer instead, so this
/// service's writes are never concurrent with any other source's).
/// [fetchEvents] and [clock] are injectable so this can be fully unit
/// tested without any platform channel.
class AppUsageService {
  AppUsageService({
    required String ownPackageName,
    Future<void> Function(BehavioralEvent event)? onEvent,
    Future<List<AppUsageRawEvent>> Function(DateTime since, DateTime until)?
        fetchEvents,
    DateTime Function()? clock,
    Duration pollInterval = const Duration(seconds: 30),
  })  : _ownPackageName = ownPackageName,
        _onEvent = onEvent ?? BehavioralEventRepository().save,
        _fetchEvents = fetchEvents ?? AppUsageNativeBridge().queryEvents,
        _clock = clock ?? DateTime.now,
        _pollInterval = pollInterval;

  final String _ownPackageName;
  final Future<void> Function(BehavioralEvent event) _onEvent;
  final Future<List<AppUsageRawEvent>> Function(DateTime since, DateTime until)
      _fetchEvents;
  final DateTime Function() _clock;
  final Duration _pollInterval;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  DateTime? _cursor;
  Timer? _timer;

  /// Package name -> the wall-clock time that package's currently open
  /// foreground session started. Only packages with no explicit
  /// background event yet are present here.
  final Map<String, DateTime> _openSessions = {};

  /// Starts polling. Idempotent. Initializes the cursor to "now" — no
  /// historical usage data is ever queried.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _cursor = _clock();
    _timer = Timer.periodic(_pollInterval, (_) => poll());
  }

  /// Stops polling. Safe to call even if not running. Clears any open
  /// (unclosed) sessions WITHOUT persisting them, and clears the
  /// cursor so a later start() begins clean with no historical import.
  Future<void> stop() async {
    if (!_isRunning) return;
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _openSessions.clear();
    _cursor = null;
  }

  /// Guards against overlapping poll() executions — e.g. a Timer tick
  /// firing while a previous poll is still awaiting fetchEvents() or
  /// persistence. A tick that arrives while one is already in flight
  /// is simply skipped; the next tick after that will query starting
  /// from wherever the cursor actually ended up.
  bool _pollInProgress = false;

  /// Runs a single poll cycle. Exposed publicly (not just via the
  /// internal Timer) so tests can drive it deterministically.
  Future<void> poll() async {
    if (!_isRunning) return;
    if (_pollInProgress) return;

    _pollInProgress = true;
    try {
      final cursor = _cursor;
      if (cursor == null) return;

      final pollEnd = _clock();
      if (!pollEnd.isAfter(cursor)) return;

      // Half-open query window: querying from (cursor + 1ms) rather
      // than cursor itself guarantees an event timestamped exactly at
      // the previous poll's boundary can never be returned again by
      // this poll, regardless of whether the native side treats its
      // own `since` bound as inclusive or exclusive. Cursor semantics
      // themselves (_cursor = pollEnd, advanced only after success)
      // are unchanged — only the query's lower bound is nudged.
      final queryStart = cursor.add(const Duration(milliseconds: 1));

      List<AppUsageRawEvent> rawEvents;
      try {
        rawEvents = await _fetchEvents(queryStart, pollEnd);
      } catch (_) {
        // Fetch failed; cursor is not advanced, so the next poll
        // re-queries starting from the same point.
        return;
      }

      final sorted = List<AppUsageRawEvent>.from(rawEvents)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final batch = <BehavioralEvent>[];
      for (final raw in sorted) {
        if (raw.packageName == _ownPackageName) continue;

        if (raw.type == AppUsageEventType.foreground) {
          // Only start a new session if one isn't already active for
          // this package — a duplicate/repeated foreground (no
          // intervening background) must not reset the start time.
          _openSessions.putIfAbsent(raw.packageName, () => raw.timestamp);
        } else {
          // AppUsageEventType.background
          final sessionStart = _openSessions.remove(raw.packageName);
          if (sessionStart == null) {
            // No open session for this package — either a duplicate
            // background, or its foreground was before our cursor. No
            // event fabricated.
            continue;
          }
          final rawDuration =
              raw.timestamp.difference(sessionStart).inMilliseconds;
          batch.add(BehavioralEvent(
            type: BehavioralEventType.appUsageSession,
            timestamp: raw.timestamp,
            durationMs: rawDuration < 0 ? 0 : rawDuration,
            packageName: raw.packageName,
          ));
        }
      }

      try {
        for (final event in batch) {
          await _onEvent(event);
        }
      } catch (_) {
        // Persistence failed partway through the batch. The cursor is
        // not advanced, so the next poll re-queries this window. Note:
        // _openSessions mutations already made during this attempt are
        // not rolled back, so a retry could in principle re-derive/
        // re-persist part of this batch — a known, accepted limitation
        // for this step, not solved here to avoid over-engineering a
        // rare failure path.
        return;
      }

      _cursor = pollEnd;
    } finally {
      _pollInProgress = false;
    }
  }
}
