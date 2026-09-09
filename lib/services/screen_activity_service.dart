import 'package:flutter/services.dart';
import '../models/behavioral_event.dart';

/// Wraps the native 'neuralsafe/screen_state' EventChannel and exposes
/// screen lock/unlock activity as a Dart Stream<BehavioralEvent>.
///
/// Step 1 scope: streaming only. Persisting these to the encrypted
/// vault is Step 2's job (a future BehavioralEventRepository), not
/// this service's.
class ScreenActivityService {
  static const _channel = EventChannel('neuralsafe/screen_state');

  Stream<BehavioralEvent>? _stream;

  Stream<BehavioralEvent> get events {
    _stream ??= _channel.receiveBroadcastStream().map((event) {
      return BehavioralEvent.fromChannelMap(event as Map<dynamic, dynamic>);
    });
    return _stream!;
  }
}
