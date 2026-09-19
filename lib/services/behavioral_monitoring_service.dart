import 'package:flutter/foundation.dart';

import '../models/behavioral_event.dart';
import 'app_lifecycle_service.dart';
import 'behavioral_event_collector.dart';
import 'behavioral_event_repository.dart';
import 'screen_session_service.dart';

/// Owns the application-level lifecycle of ALL behavioral event
/// collection: screen state (via BehavioralEventCollector), the app's
/// own foreground/background lifecycle (via AppLifecycleService,
/// Step 3.3), and, as of Step 3.5, derived device screen-on session
/// duration (via ScreenSessionService). No source's collection or
/// persistence logic is duplicated here — this only starts/stops all
/// three together and, for the production singleton, wires
/// ScreenSessionService to observe the same raw screen events
/// BehavioralEventCollector already persists, sequentially and never
/// concurrently.
class BehavioralMonitoringService {
  BehavioralMonitoringService._({
    required BehavioralEventCollector collector,
    required AppLifecycleService? lifecycleService,
    required ScreenSessionService? screenSessionService,
  })  : _collector = collector,
        _lifecycleService = lifecycleService,
        _screenSessionService = screenSessionService;

  static BehavioralMonitoringService? _instance;

  /// Application-level singleton. Always owns a real
  /// BehavioralEventCollector, AppLifecycleService, and
  /// ScreenSessionService.
  ///
  /// The collector's onEvent is wired to persist each raw event AND
  /// THEN (awaited, sequentially — never concurrently) feed it to
  /// ScreenSessionService.handleEvent(), so a derived screenSession
  /// save never races the raw event's own save against the encrypted
  /// vault's read-modify-write persistence.
  static BehavioralMonitoringService get instance {
    if (_instance != null) return _instance!;

    final screenSessionService = ScreenSessionService();
    final repository = BehavioralEventRepository();

    // Step 3.5 ordering fix (learned from the Step 3.4 physical
    // Android test): during the screen_off transition, the derived
    // screenSession is the priority signal, so it must be persisted
    // BEFORE the raw screenOff event, not after — the second of two
    // sequential awaited saves during an Android lifecycle transition
    // is the one at risk of being lost, so the priority write goes
    // first. handleEvent() itself derives AND persists screenSession
    // (a no-op unless a screen session is actually active, e.g. it is
    // a no-op for screen_on and for a duplicate screen_off).
    //
    // For every other event type (screenOn, userPresent, and anything
    // else), the raw event's own save still happens first, as before
    // Step 3.5 — screen_on's only effect on ScreenSessionService is
    // an in-memory start-time write with no persistence, so ordering
    // relative to the raw save doesn't matter for it, but keeping the
    // raw-save-first order for every non-screenOff type preserves
    // Step 3.1–3.4 behavior exactly and keeps the special case
    // narrowly scoped to the one type that actually needs it.
    final collector = BehavioralEventCollector(
      onEvent: (event) async {
        if (event.type == BehavioralEventType.screenOff) {
          await screenSessionService.handleEvent(event);
          await repository.save(event);
        } else {
          await repository.save(event);
          await screenSessionService.handleEvent(event);
        }
      },
    );

    _instance = BehavioralMonitoringService._(
      collector: collector,
      lifecycleService: AppLifecycleService(),
      screenSessionService: screenSessionService,
    );
    return _instance!;
  }

  /// Test-only construction path. [lifecycleService] and
  /// [screenSessionService] are optional and, when omitted, that
  /// source is simply not started/stopped/considered — existing tests
  /// that only inject a collector continue to work exactly as before.
  @visibleForTesting
  factory BehavioralMonitoringService.test({
    required BehavioralEventCollector collector,
    AppLifecycleService? lifecycleService,
    ScreenSessionService? screenSessionService,
  }) {
    return BehavioralMonitoringService._(
      collector: collector,
      lifecycleService: lifecycleService,
      screenSessionService: screenSessionService,
    );
  }

  final BehavioralEventCollector _collector;
  final AppLifecycleService? _lifecycleService;
  final ScreenSessionService? _screenSessionService;

  bool get isRunning =>
      _collector.isRunning &&
      (_lifecycleService?.isRunning ?? true) &&
      (_screenSessionService?.isRunning ?? true);

  void start() {
    if (!_collector.isRunning) {
      _collector.start();
    }
    final lifecycleService = _lifecycleService;
    if (lifecycleService != null && !lifecycleService.isRunning) {
      lifecycleService.start();
    }
    final screenSessionService = _screenSessionService;
    if (screenSessionService != null && !screenSessionService.isRunning) {
      screenSessionService.start();
    }
  }

  Future<void> stop() async {
    await _collector.stop();
    await _lifecycleService?.stop();
    await _screenSessionService?.stop();
  }
}
