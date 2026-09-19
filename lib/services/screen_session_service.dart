import '../models/behavioral_event.dart';
import 'behavioral_event_repository.dart';

/// Derives a screenSession BehavioralEvent (device screen-on duration)
/// from the raw screenOn/screenOff/userPresent events already flowing
/// through BehavioralEventCollector — WITHOUT establishing a second
/// listener on the native screen-state stream.
///
/// This service does not subscribe to any stream itself. Instead,
/// BehavioralMonitoringService's production singleton feeds it each
/// raw BehavioralEvent via handleEvent() from INSIDE the same
/// collector onEvent callback that persists the raw event —
/// sequentially, awaited, after the raw event's own save() has
/// already completed. This avoids two independent async save() calls
/// racing against the encrypted vault's read-modify-write persistence
/// (the same class of bug fixed in Step 3.4 for appSession/
/// appBackground).
///
/// [onEvent] is injectable (defaults to BehavioralEventRepository().save)
/// so this can be unit tested without the encrypted vault. [clock] is
/// injectable so duration tests are deterministic.
class ScreenSessionService {
  ScreenSessionService({
    Future<void> Function(BehavioralEvent event)? onEvent,
    DateTime Function()? clock,
  })  : _onEvent = onEvent ?? BehavioralEventRepository().save,
        _clock = clock ?? DateTime.now;

  final Future<void> Function(BehavioralEvent event) _onEvent;
  final DateTime Function() _clock;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Wall-clock time the current screen-on session started, or null if
  /// no session is currently active.
  DateTime? _screenSessionStart;

  /// Starts processing. Idempotent. Does not itself subscribe to
  /// anything — it only gates whether handleEvent() does any work,
  /// mirroring the start/stop contract of the other collection
  /// sources this app already has.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
  }

  /// Stops processing. Safe to call even if not running. Clears any
  /// in-progress session so a later start() begins clean.
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    _screenSessionStart = null;
  }

  /// Called for every raw screen-state event, AFTER that event's own
  /// save() has already completed. Only screenOn/screenOff affect
  /// session state; userPresent (and anything else) is ignored here.
  Future<void> handleEvent(BehavioralEvent event) async {
    if (!_isRunning) return;

    switch (event.type) {
      case BehavioralEventType.screenOn:
        _handleScreenOn();
        return;
      case BehavioralEventType.screenOff:
        await _handleScreenOff();
        return;
      default:
        return;
    }
  }

  void _handleScreenOn() {
    // Only start a new session if one isn't already active — a
    // duplicate screen_on (no intervening screen_off) must not reset
    // the session's start time.
    _screenSessionStart ??= _clock();
  }

  Future<void> _handleScreenOff() async {
    final sessionStart = _screenSessionStart;
    if (sessionStart == null) return; // duplicate screen_off: no-op

    final sessionEnd = _clock();
    final durationMs = sessionEnd.difference(sessionStart).inMilliseconds;

    await _onEvent(BehavioralEvent(
      type: BehavioralEventType.screenSession,
      timestamp: sessionEnd,
      durationMs: durationMs < 0 ? 0 : durationMs,
    ));

    // Clear only after persistence has completed, and only after a
    // genuine active session — duplicate screen_off must not create
    // a second screenSession.
    _screenSessionStart = null;
  }
}
