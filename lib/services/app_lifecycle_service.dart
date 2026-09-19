import 'package:flutter/widgets.dart';

import '../models/behavioral_event.dart';
import 'behavioral_event_repository.dart';

/// Observes the NeuralSafe app's own foreground/background lifecycle
/// (not other apps — Flutter's WidgetsBindingObserver only ever reports
/// this app's own process state) and forwards appForeground/appBackground
/// BehavioralEvents into the same persistence pathway
/// BehavioralEventCollector already uses, without going through it.
///
/// Only resumed → appForeground and paused → appBackground are handled;
/// inactive/detached/hidden states are deliberately ignored per scope.
///
/// [onEvent] is injectable (defaults to BehavioralEventRepository().save)
/// so this can be unit tested without the encrypted vault.
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService({
    Future<void> Function(BehavioralEvent event)? onEvent,
    WidgetsBinding? binding,
  })  : _onEvent = onEvent ?? BehavioralEventRepository().save,
        _binding = binding ?? WidgetsBinding.instance;

  final Future<void> Function(BehavioralEvent event) _onEvent;
  final WidgetsBinding _binding;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Starts observing. Idempotent — a second call while already running
  /// is a no-op, so the observer is never registered twice.
  ///
  /// Deliberately does NOT emit a synthetic appForeground event on
  /// start(), even though the app is presumably foregrounded at that
  /// point — only genuine OS-driven transitions (via
  /// didChangeAppLifecycleState) generate events, so initialization
  /// itself can never produce a duplicate or spurious event.
  void start() {
    if (_isRunning) return;
    _binding.addObserver(this);
    _isRunning = true;
  }

  /// Stops observing and removes the binding observer. Safe to call
  /// even if not currently running.
  Future<void> stop() async {
    if (!_isRunning) return;
    _binding.removeObserver(this);
    _isRunning = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Guards against a stray callback arriving after stop() (e.g. a
    // race during teardown) as well as being the mapping point for
    // which states are in scope.
    if (!_isRunning) return;

    final eventType = _mapState(state);
    if (eventType == null) return;

    _onEvent(BehavioralEvent(type: eventType, timestamp: DateTime.now()));
  }

  BehavioralEventType? _mapState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        return BehavioralEventType.appForeground;
      case AppLifecycleState.paused:
        return BehavioralEventType.appBackground;
      default:
        return null; // inactive/detached/hidden: out of scope for this step
    }
  }
}
