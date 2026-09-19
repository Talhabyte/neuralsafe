import 'package:flutter/foundation.dart';

import 'behavioral_event_collector.dart';

/// Owns the application-level lifecycle of behavioral event collection.
///
/// This does not duplicate any responsibility already handled elsewhere:
/// BehavioralEventCollector remains responsible for forwarding events,
/// BehavioralEventRepository remains responsible for persistence. This
/// class's only job is start/stop/isRunning at the application level,
/// so main.dart has one simple thing to call rather than constructing
/// and managing a BehavioralEventCollector directly.
class BehavioralMonitoringService {
  BehavioralMonitoringService._({BehavioralEventCollector? collector})
      : _collector = collector ?? BehavioralEventCollector();

  static BehavioralMonitoringService? _instance;

  /// Application-level singleton. Uses the real BehavioralEventCollector,
  /// which in turn uses the real ScreenActivityService and
  /// BehavioralEventRepository.
  static BehavioralMonitoringService get instance {
    _instance ??= BehavioralMonitoringService._();
    return _instance!;
  }

  /// Test-only construction path: inject a BehavioralEventCollector
  /// (itself already wired to a fake stream/callback in tests) so this
  /// service can be tested without the real EventChannel or vault.
  @visibleForTesting
  factory BehavioralMonitoringService.test({
    required BehavioralEventCollector collector,
  }) {
    return BehavioralMonitoringService._(collector: collector);
  }

  final BehavioralEventCollector _collector;

  bool get isRunning => _collector.isRunning;

  /// Starts behavioral monitoring. Idempotent — BehavioralEventCollector
  /// itself already guards against duplicate subscriptions, and this
  /// checks isRunning first as well so calling start() repeatedly is
  /// always safe at this layer too.
  void start() {
    if (_collector.isRunning) return;
    _collector.start();
  }

  Future<void> stop() async {
    await _collector.stop();
  }
}
