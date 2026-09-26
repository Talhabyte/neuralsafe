import 'dart:async';

import '../models/dispatch_result.dart';
import '../models/risk_decision.dart';
import '../models/risk_tier.dart';
import 'emergency_alert_dispatcher.dart';

/// Watches a stream of `RiskDecision`s (normally
/// `RiskDecisionEngine.decisions`) and invokes
/// `EmergencyAlertDispatcher.dispatch()` when the risk tier
/// TRANSITIONS INTO `RiskTier.highDanger` — i.e. the previous
/// decision's tier was NOT `highDanger` and the new one IS — not on
/// every single evaluation that happens to already be in that tier.
///
/// This class adds NO cooldown/timer logic of its own. Spam protection
/// for repeated `dispatch()` calls (e.g. from tier flapping in and out
/// of `highDanger` within a short window) is left entirely to
/// `EmergencyAlertDispatcher`'s own `AlertCooldownManager`, so there is
/// exactly one cooldown mechanism in the whole pipeline, not two.
///
/// Deliberately loosely coupled via constructor injection: both the
/// decision stream and the dispatcher are injected, so this can be
/// tested with fakes for both, and a `dryRun`-configured
/// `EmergencyAlertDispatcher` can be substituted freely (e.g. for
/// physical-device pipeline verification without a real SMS being
/// sent) without this class needing to know or care.
///
/// IMPORTANT: this class is standalone and NOT wired into `main.dart`
/// or `BehavioralMonitoringService` by this change — it must be
/// explicitly constructed and started before it does anything.
/// Starting it with a NON-dry-run dispatcher means a real emergency
/// SMS WILL be sent the next time a `highDanger` transition occurs.
class EmergencyResponseOrchestrator {
  EmergencyResponseOrchestrator({
    required Stream<RiskDecision> riskDecisions,
    required EmergencyAlertDispatcher dispatcher,
  })  : _riskDecisions = riskDecisions,
        _dispatcher = dispatcher,
        _dispatchResultsController =
            StreamController<DispatchResult>.broadcast();

  final Stream<RiskDecision> _riskDecisions;
  final EmergencyAlertDispatcher _dispatcher;
  final StreamController<DispatchResult> _dispatchResultsController;

  StreamSubscription<RiskDecision>? _subscription;
  RiskTier? _previousTier;
  DispatchResult? _lastDispatchResult;

  bool get isRunning => _subscription != null;

  /// The most recent `DispatchResult` produced by a triggered dispatch,
  /// or null if none has occurred yet.
  DispatchResult? get lastDispatchResult => _lastDispatchResult;

  /// Broadcast stream of every `DispatchResult` produced as a result of
  /// a highDanger transition. Emits nothing for decisions that don't
  /// trigger a dispatch (e.g. staying in mediumRisk, or staying in
  /// highDanger on a subsequent evaluation).
  Stream<DispatchResult> get dispatchResults =>
      _dispatchResultsController.stream;

  /// Starts listening. Idempotent — a second call while already
  /// running is a no-op, so no duplicate subscriptions (and therefore
  /// no duplicate `dispatch()` calls per transition) are ever created.
  void start() {
    if (_subscription != null) return;
    _subscription = _riskDecisions.listen(_handleDecision);
  }

  /// Stops listening and releases the subscription. Safe to call even
  /// if not currently running. Resets the tracked previous tier, so a
  /// later `start()` does not treat its first decision as "already in
  /// highDanger" based on stale state from before the stop.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _previousTier = null;
  }

  /// Permanently closes the `dispatchResults` stream.
  Future<void> dispose() async {
    await _dispatchResultsController.close();
  }

  void _handleDecision(RiskDecision decision) {
    final isEnteringHighDanger = decision.riskTier == RiskTier.highDanger &&
        _previousTier != RiskTier.highDanger;

    _previousTier = decision.riskTier;

    if (!isEnteringHighDanger) return;

    // Fire-and-forget from this synchronous stream callback's
    // perspective; the dispatch itself is awaited internally so its
    // result can be captured and emitted once it completes.
    unawaited(_triggerDispatch());
  }

  Future<void> _triggerDispatch() async {
    final result = await _dispatcher.dispatch();
    _lastDispatchResult = result;
    if (!_dispatchResultsController.isClosed) {
      _dispatchResultsController.add(result);
    }
  }
}
