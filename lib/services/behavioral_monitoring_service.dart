import 'package:flutter/foundation.dart';

import 'app_lifecycle_service.dart';
import 'behavioral_event_collector.dart';

/// Owns the application-level lifecycle of ALL behavioral event
/// collection: screen state (via BehavioralEventCollector) and, as of
/// Step 3.3, the app's own foreground/background lifecycle (via
/// AppLifecycleService). Neither source's collection/persistence logic
/// is duplicated here — this only starts/stops both together.
///
/// The production singleton (.instance) always owns a real
/// AppLifecycleService. The test factory (.test) makes lifecycleService
/// optional and does NOT construct one when omitted — this is
/// deliberate: existing tests that only inject a collector are testing
/// screen-event monitoring and must never construct/start a real
/// AppLifecycleService, which would touch WidgetsBinding.instance and
/// require a Flutter test binding those tests don't initialize. Only
/// tests that explicitly pass lifecycleService exercise that path.
class BehavioralMonitoringService {
  BehavioralMonitoringService._({
    required BehavioralEventCollector collector,
    required AppLifecycleService? lifecycleService,
  })  : _collector = collector,
        _lifecycleService = lifecycleService;

  static BehavioralMonitoringService? _instance;

  /// Application-level singleton. Always owns a real
  /// BehavioralEventCollector and a real AppLifecycleService.
  static BehavioralMonitoringService get instance {
    _instance ??= BehavioralMonitoringService._(
      collector: BehavioralEventCollector(),
      lifecycleService: AppLifecycleService(),
    );
    return _instance!;
  }

  /// Test-only construction path. [lifecycleService] is optional and,
  /// when omitted, no AppLifecycleService is created at all — start()
  /// and stop() then simply skip that source entirely.
  @visibleForTesting
  factory BehavioralMonitoringService.test({
    required BehavioralEventCollector collector,
    AppLifecycleService? lifecycleService,
  }) {
    return BehavioralMonitoringService._(
      collector: collector,
      lifecycleService: lifecycleService,
    );
  }

  final BehavioralEventCollector _collector;
  final AppLifecycleService? _lifecycleService;

  /// Reflects the collector's running state, combined with the
  /// lifecycle service's state only when one exists. When no lifecycle
  /// service was injected (the pre-3.3 test path), this is exactly the
  /// collector's running state, as before.
  bool get isRunning =>
      _collector.isRunning && (_lifecycleService?.isRunning ?? true);

  /// Starts both collection sources. Idempotent for each — every
  /// underlying service already guards against duplicate start, and
  /// this checks isRunning first as well. Safely does nothing for the
  /// lifecycle source if none was injected.
  void start() {
    if (!_collector.isRunning) {
      _collector.start();
    }
    final lifecycleService = _lifecycleService;
    if (lifecycleService != null && !lifecycleService.isRunning) {
      lifecycleService.start();
    }
  }

  Future<void> stop() async {
    await _collector.stop();
    await _lifecycleService?.stop();
  }
}
