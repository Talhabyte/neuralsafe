import '../models/behavioral_baseline.dart';
import 'package:flutter/foundation.dart';

import '../models/behavioral_event.dart';
import 'app_lifecycle_service.dart';
import 'app_usage_service.dart';
import 'behavioral_event_aggregator.dart';
import 'behavioral_event_collector.dart';
import 'behavioral_event_repository.dart';
import 'screen_session_service.dart';

/// Serializes every write into BehavioralEventRepository behind one
/// FIFO queue, regardless of which source (screen events, derived
/// screenSession, app lifecycle, derived appSession, or derived
/// appUsageSession) is calling it. This closes a pre-existing gap:
/// prior to this, the collector and AppLifecycleService each called
/// repository.save() independently, with no guarantee against two
/// saves' read-modify-write cycles interleaving (the same class of
/// bug fixed for appSession/appBackground in Step 3.4, just between
/// two different sources instead of within one). BehavioralEventRepository
/// itself is NOT modified — this is purely a call-site discipline
/// change in how the app's sources are wired together.
///
/// Note: BehavioralEventAggregator does NOT go through this writer —
/// it only ever reads via BehavioralEventRepository.loadAll(), never
/// calls save(), so it has no write-concurrency exposure to guard
/// against here.
class _SerializedEventWriter {
  _SerializedEventWriter(this._repository);
  final BehavioralEventRepository _repository;
  Future<void> _tail = Future<void>.value();

  Future<void> call(BehavioralEvent event) {
    final result = _tail.then((_) => _repository.save(event));
    // Swallow errors in the chain itself so one failed save doesn't
    // permanently wedge the queue for subsequent, unrelated events —
    // the error still propagates to whoever awaited this specific call.
    _tail = result.catchError((_) {});
    return result;
  }
}

/// Owns the application-level lifecycle of ALL behavioral event
/// collection: screen state (via BehavioralEventCollector), derived
/// screen-on session duration (via ScreenSessionService), the app's
/// own foreground/background lifecycle and derived session duration
/// (via AppLifecycleService), derived Android app-usage session
/// duration (via AppUsageService), and, as of this wiring, cross-source
/// batch aggregation (via BehavioralEventAggregator, which reads back
/// from the same repository every other source writes into). No
/// source's collection or persistence logic is duplicated here — this
/// only starts/stops all sources together and, for the production
/// singleton, wires every WRITING source through the single serialized
/// writer above so no two sources' saves can ever race each other.
class BehavioralMonitoringService {
  BehavioralMonitoringService._({
    required BehavioralEventCollector collector,
    required AppLifecycleService? lifecycleService,
    required ScreenSessionService? screenSessionService,
    required AppUsageService? appUsageService,
    required BehavioralEventAggregator? aggregator,
  })  : _collector = collector,
        _lifecycleService = lifecycleService,
        _screenSessionService = screenSessionService,
        _appUsageService = appUsageService,
        _aggregator = aggregator;

  static BehavioralMonitoringService? _instance;

  /// Must match the Android applicationId / Kotlin package
  /// (com.example.neuralsafe, per MainActivity.kt) so AppUsageService
  /// correctly excludes NeuralSafe's own usage from appUsageSession
  /// events. If the applicationId is ever changed from the Flutter
  /// default, this constant must be updated to match — there is no
  /// dependency-free way to read it at runtime without adding a
  /// package-info plugin, which this step deliberately avoids.
  static const _ownPackageName = 'com.example.neuralsafe';

  /// Application-level singleton. Always owns a real
  /// BehavioralEventCollector, AppLifecycleService, ScreenSessionService,
  /// AppUsageService, and BehavioralEventAggregator, with every writing
  /// source wired through one shared _SerializedEventWriter so every
  /// persisted write across every source happens strictly one at a
  /// time. The aggregator is currently unconsumed downstream (no
  /// onBatch/listener wired) — it runs and correctly discovers new
  /// events across all sources, but nothing acts on the batches yet.
  static BehavioralMonitoringService get instance {
    if (_instance != null) return _instance!;

    final repository = BehavioralEventRepository();
    final writer = _SerializedEventWriter(repository);

    final screenSessionService = ScreenSessionService(onEvent: writer.call);

    final collector = BehavioralEventCollector(
      onEvent: (event) async {
        if (event.type == BehavioralEventType.screenOff) {
          // screenSession is the priority signal during the
          // screen-off transition (Step 3.5 physical-testing lesson):
          // persist it first, fully awaited, before the raw screenOff
          // event.
          await screenSessionService.handleEvent(event);
          await writer(event);
        } else {
          await writer(event);
          await screenSessionService.handleEvent(event);
        }
      },
    );

    final lifecycleService = AppLifecycleService(onEvent: writer.call);

    final appUsageService = AppUsageService(
      ownPackageName: _ownPackageName,
      onEvent: writer.call,
    );

    _instance = BehavioralMonitoringService._(
      collector: collector,
      lifecycleService: lifecycleService,
      screenSessionService: screenSessionService,
      appUsageService: appUsageService,
      aggregator: BehavioralEventAggregator(),
    );
    return _instance!;
  }

  /// Test-only construction path. Every optional parameter defaults to
  /// null, meaning that source is simply not started/stopped/
  /// considered — existing tests that only inject a collector (or a
  /// collector plus a subset of the other sources) continue to work
  /// exactly as before, unaffected by later additions.
  @visibleForTesting
  factory BehavioralMonitoringService.test({
    required BehavioralEventCollector collector,
    AppLifecycleService? lifecycleService,
    ScreenSessionService? screenSessionService,
    AppUsageService? appUsageService,
    BehavioralEventAggregator? aggregator,
  }) {
    return BehavioralMonitoringService._(
      collector: collector,
      lifecycleService: lifecycleService,
      screenSessionService: screenSessionService,
      appUsageService: appUsageService,
      aggregator: aggregator,
    );
  }

  final BehavioralEventCollector _collector;
  final AppLifecycleService? _lifecycleService;
  final ScreenSessionService? _screenSessionService;
  final AppUsageService? _appUsageService;
  final BehavioralEventAggregator? _aggregator;

  bool get isRunning =>
      _collector.isRunning &&
      (_lifecycleService?.isRunning ?? true) &&
      (_screenSessionService?.isRunning ?? true) &&
      (_appUsageService?.isRunning ?? true) &&
      (_aggregator?.isRunning ?? true);

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
    final appUsageService = _appUsageService;
    if (appUsageService != null && !appUsageService.isRunning) {
      appUsageService.start();
    }
    final aggregator = _aggregator;
    if (aggregator != null && !aggregator.isRunning) {
      aggregator.start();
    }
  }

  Future<void> stop() async {
    await _collector.stop();
    await _lifecycleService?.stop();
    await _screenSessionService?.stop();
    await _appUsageService?.stop();
    _aggregator?.stop();
  }
}
