import 'dart:async';

import '../models/behavioral_event.dart';
import 'behavioral_event_repository.dart';

/// Unifies behavioral events across all active collectors by polling
/// the single shared BehavioralEventRepository — the point every
/// collector (screen events, app lifecycle, app session, screen
/// session, app usage session) already converges on. This does NOT
/// establish a second listener on any native stream or modify
/// BehavioralEventRepository; it only reads via the repository's
/// existing public loadAll().
///
/// On a configurable window, it identifies events persisted since the
/// last poll and delivers them as a single batch via [onBatch] and/or
/// the [batches] stream. This is plumbing only — no aggregation logic
/// beyond grouping-by-window, no scoring, no AI/ML, no UI.
///
/// Concurrency: a bool guard prevents overlapping poll() executions
/// (same pattern as AppUsageService's _pollInProgress). poll() awaits
/// a microtask immediately after acquiring the guard, guaranteeing it
/// genuinely yields control rather than running to completion
/// synchronously — this keeps execution non-blocking and makes the
/// guard meaningfully testable against a real overlapping call.
///
/// [loadEvents] and [clock] are injectable so this can be fully unit
/// tested without the encrypted vault.
class BehavioralEventAggregator {
  BehavioralEventAggregator({
    List<BehavioralEvent> Function()? loadEvents,
    DateTime Function()? clock,
    Duration window = const Duration(seconds: 60),
    void Function(List<BehavioralEvent> batch)? onBatch,
  })  : _loadEvents = loadEvents ?? BehavioralEventRepository().loadAll,
        _clock = clock ?? DateTime.now,
        _window = window,
        _onBatch = onBatch,
        _controller = StreamController<List<BehavioralEvent>>.broadcast();

  final List<BehavioralEvent> Function() _loadEvents;
  final DateTime Function() _clock;
  final void Function(List<BehavioralEvent> batch)? _onBatch;
  final StreamController<List<BehavioralEvent>> _controller;

  Duration _window;
  Duration get window => _window;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _isTicking = false;

  Timer? _timer;

  /// Wall-clock time of the newest event already delivered in a prior
  /// batch, or null before the first poll. Only events strictly newer
  /// than this are candidates for the next batch.
  DateTime? _lastProcessedTimestamp;

  /// Dedupe guard for events tied exactly at [_lastProcessedTimestamp]
  /// — bounded to only the keys at that single timestamp, so this
  /// never grows unbounded. Mirrors the boundary-duplication fix
  /// already applied to AppUsageService in Step 3.6.
  Set<String> _recentBoundaryKeys = {};

  /// Broadcast stream of new-event batches. Multiple listeners may
  /// subscribe independently of [onBatch].
  Stream<List<BehavioralEvent>> get batches => _controller.stream;

  /// Starts polling. Idempotent. Initializes the cursor to "now" — no
  /// historical backlog already in the vault is imported on start,
  /// consistent with every other collector in this app (AppUsageService,
  /// ScreenSessionService, AppLifecycleService).
  ///
  /// Also seeds [_recentBoundaryKeys] with any events already persisted
  /// at EXACTLY this moment, so a pre-existing event tied at the cursor
  /// timestamp is correctly treated as historical backlog on the very
  /// first poll, not as a new event — closing the tie-at-start edge
  /// case the boundary-dedupe mechanism doesn't otherwise cover until
  /// a batch has actually been delivered once.
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    final now = _clock();
    _lastProcessedTimestamp = now;
    _recentBoundaryKeys = _loadEvents()
        .where((e) => e.timestamp.isAtSameMomentAs(now))
        .map(_keyFor)
        .toSet();

    _timer = Timer.periodic(_window, (_) => poll());
  }

  /// Stops polling. Safe to call even if not running. The batches
  /// stream itself is left open (not closed) so a later start() can
  /// resume delivering to existing listeners; call dispose() instead
  /// if the stream should be closed permanently.
  void stop() {
    if (!_isRunning) return;
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// Permanently closes the batches stream. Call stop() first if
  /// currently running.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Reconfigures the polling window. If currently running, the
  /// periodic timer is restarted with the new duration; the cursor and
  /// dedupe state are left untouched.
  void updateWindow(Duration newWindow) {
    _window = newWindow;
    if (_isRunning) {
      _timer?.cancel();
      _timer = Timer.periodic(_window, (_) => poll());
    }
  }

  /// Runs a single poll cycle. Exposed publicly (not just via the
  /// internal Timer) so tests can drive it deterministically.
  Future<void> poll() async {
    if (!_isRunning) return;
    if (_isTicking) return;

    _isTicking = true;
    try {
      // Guarantees this method genuinely yields control here rather
      // than running to completion synchronously (there would
      // otherwise be no real await anywhere in this method), so a
      // second poll() call made immediately after this one correctly
      // observes _isTicking == true instead of the first call having
      // already finished and reset it.
      await Future<void>.microtask(() {});

      final cursor = _lastProcessedTimestamp;
      if (cursor == null) return;

      final allEvents = _loadEvents();

      final newEvents = allEvents.where((event) {
        if (event.timestamp.isAfter(cursor)) return true;
        if (event.timestamp.isAtSameMomentAs(cursor)) {
          return !_recentBoundaryKeys.contains(_keyFor(event));
        }
        return false;
      }).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (newEvents.isEmpty) return;

      final newestTimestamp = newEvents.last.timestamp;

      _lastProcessedTimestamp = newestTimestamp;
      _recentBoundaryKeys = newEvents
          .where((e) => e.timestamp.isAtSameMomentAs(newestTimestamp))
          .map(_keyFor)
          .toSet();

      _onBatch?.call(newEvents);
      if (!_controller.isClosed) {
        _controller.add(newEvents);
      }
    } finally {
      _isTicking = false;
    }
  }

  String _keyFor(BehavioralEvent event) {
    return '${event.type.name}|${event.timestamp.millisecondsSinceEpoch}|'
        '${event.durationMs}|${event.packageName}';
  }
}
