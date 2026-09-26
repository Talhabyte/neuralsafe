import 'location_result.dart';

enum DispatchOutcome {
  sent,
  suppressedByCooldown,
  noContactsConfigured,
  partialFailure
}

/// Result of one EmergencyAlertDispatcher.dispatch() call. Pure data —
/// no side effects live here; the side effects (SMS sent) have already
/// happened (or been skipped/simulated) by the time this is returned.
class DispatchResult {
  final DispatchOutcome outcome;
  final LocationResult? location;

  /// Contact id -> whether the SMS to that contact succeeded. Empty
  /// when [outcome] is suppressedByCooldown or noContactsConfigured,
  /// since no send attempts were made in either case.
  final Map<String, bool> perContactSuccess;
  final DateTime attemptedAt;

  const DispatchResult({
    required this.outcome,
    required this.location,
    required this.perContactSuccess,
    required this.attemptedAt,
  });

  @override
  String toString() {
    return 'DispatchResult(outcome: $outcome, location: $location, '
        'perContactSuccess: $perContactSuccess, attemptedAt: $attemptedAt)';
  }
}
