import 'package:flutter/widgets.dart';

import '../models/behavioral_event.dart';
import 'behavioral_event_repository.dart';

/// Observes the NeuralSafe app's own foreground/background lifecycle
/// (not other apps — Flutter's WidgetsBindingObserver only ever reports
/// this app's own process state) and forwards behavioral events into
/// the same persistence pathway BehavioralEventCollector already uses,
/// without going through it.
///
/// Emits:
///  - appForeground on every resumed transition (Step 3.3 behavior,
///    unchanged).
///  - appBackground on every paused transition (Step 3.3 behavior,
///    unchanged).
///  - appSession on paused, ONLY if a session was actually active —
///    representing the just-completed foreground session's duration
///    (Step 3.4).
///
/// IMPORTANT (Step 3.4 fix): appBackground and appSession are both
/// persisted via BehavioralEventRepository.save(), which does a
/// read-modify-write against the vault. Firing both saves without
/// awaiting between them lets the second save's read race ahead of
/// the first save's write, silently dropping the first event. _handlePaused
/// is therefore async and awaits appBackground's save before starting
/// appSession's save, so the two writes are strictly sequential.
///
/// Only resumed/paused are handled; inactive/detached/hidden states
/// are deliberately ignored per scope, and do not affect session state.
///
/// [onEvent] is injectable (defaults to BehavioralEventRepository().save)
/// so this can be unit tested without the encrypted vault. [clock] is
/// injectable so session duration tests are deterministic rather than
/// depending on real wall-clock time.
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService({
    Future<void> Function(BehavioralEvent event)? onEvent,
    WidgetsBinding? binding,
    DateTime Function()? clock,
  })  : _onEvent = onEvent ?? BehavioralEventRepository().save,
        _binding = binding ?? WidgetsBinding.instance,
        _clock = clock ?? DateTime.now;

  final Future<void> Function(BehavioralEvent event) _onEvent;
  final WidgetsBinding _binding;
  final DateTime Function() _clock;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Wall-clock time the current foreground session started, or null
  /// if no session is currently active (i.e. the app is backgrounded,
  /// or the most recent session was already closed out by a paused).
  DateTime? _sessionStart;

  /// Starts observing. Idempotent — a second call while already running
  /// is a no-op, so the observer is never registered twice.
  ///
  /// Deliberately does NOT emit a synthetic appForeground event or
  /// start a session on start(), even though the app is presumably
  /// foregrounded at that point — only genuine OS-driven transitions
  /// (via didChangeAppLifecycleState) generate events or session state.
  void start() {
    if (_isRunning) return;
    _binding.addObserver(this);
    _isRunning = true;
  }

  /// Stops observing and removes the binding observer. Safe to call
  /// even if not currently running. Also clears any in-progress
  /// session, so a later start() begins with clean session state
  /// rather than carrying over a stale start time.
  Future<void> stop() async {
    if (!_isRunning) return;
    _binding.removeObserver(this);
    _isRunning = false;
    _sessionStart = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Guards against a stray callback arriving after stop() (e.g. a
    // race during teardown).
    if (!_isRunning) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _handleResumed();
        return;
      case AppLifecycleState.paused:
        // Fire-and-forget from the framework's synchronous callback —
        // the sequencing that matters (appBackground save fully
        // completing before appSession save starts) happens inside
        // _handlePaused itself via await, not at this call boundary.
        _handlePaused();
        return;
      default:
        return; // inactive/detached/hidden: out of scope, no session effect
    }
  }

  void _handleResumed() {
    // Only start a new session if one isn't already active — a
    // duplicate resumed (no intervening paused) must not reset the
    // session's start time.
    _sessionStart ??= _clock();

    _onEvent(BehavioralEvent(
      type: BehavioralEventType.appForeground,
      timestamp: _clock(),
    ));
  }

  Future<void> _handlePaused() async {
    // Step 3.4 fix #2 (physical Android testing): appSession is
    // persisted FIRST, before appBackground. On a real device, the OS
    // gives a paused process only a limited window to finish work
    // before it may be suspended/killed; physical testing showed the
    // second of two sequential awaited saves was reliably lost across
    // that transition. appSession is the priority signal, so it goes
    // first while the process is definitely still fully alive at
    // callback entry; appBackground (already proven reliable in Step
    // 3.3) goes second.
    final sessionStart = _sessionStart;
    if (sessionStart != null) {
      final sessionEnd = _clock();
      final durationMs = sessionEnd.difference(sessionStart).inMilliseconds;

      // Awaited: must fully complete (including its read-modify-write
      // against the vault) before the appBackground save below begins,
      // otherwise the two saves' loadAll()/put() cycles can interleave
      // and one write silently overwrites the other.
      await _onEvent(BehavioralEvent(
        type: BehavioralEventType.appSession,
        timestamp: sessionEnd,
        durationMs: durationMs < 0 ? 0 : durationMs,
      ));

      // Session is now closed out. A duplicate paused (no intervening
      // resumed) must not create a second appSession event.
      _sessionStart = null;
    }

    await _onEvent(BehavioralEvent(
      type: BehavioralEventType.appBackground,
      timestamp: _clock(),
    ));
  }
}
