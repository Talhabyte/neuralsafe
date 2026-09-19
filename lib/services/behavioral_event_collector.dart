import 'dart:async';

import '../models/behavioral_event.dart';
import 'behavioral_event_repository.dart';
import 'screen_activity_service.dart';

/// Coordinates ScreenActivityService (streaming) and
/// BehavioralEventRepository (persistence) without merging their
/// responsibilities into either class.
///
/// ScreenActivityService stays responsible only for exposing the native
/// screen-state EventChannel as a Stream<BehavioralEvent>.
/// BehavioralEventRepository stays responsible only for encrypted
/// persistence. This class's only job is: when an event arrives on the
/// stream, forward it to be saved.
///
/// [eventsStream] and [onEvent] are injectable so this can be unit
/// tested with a fake stream and an in-memory callback, with no
/// dependency on the real EventChannel or the encrypted vault.
class BehavioralEventCollector {
  BehavioralEventCollector({
    Stream<BehavioralEvent>? eventsStream,
    Future<void> Function(BehavioralEvent event)? onEvent,
  })  : _eventsStream = eventsStream ?? ScreenActivityService().events,
        _onEvent = onEvent ?? BehavioralEventRepository().save;

  final Stream<BehavioralEvent> _eventsStream;
  final Future<void> Function(BehavioralEvent event) _onEvent;

  StreamSubscription<BehavioralEvent>? _subscription;

  /// True while actively listening for events.
  bool get isRunning => _subscription != null;

  /// Starts listening. Safe to call more than once — a second call
  /// while already running is a no-op, so no duplicate subscriptions
  /// are ever created.
  void start() {
    if (_subscription != null) return;
    _subscription = _eventsStream.listen((event) {
      _onEvent(event);
    });
  }

  /// Stops listening and releases the subscription. Safe to call even
  /// if not currently running.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
