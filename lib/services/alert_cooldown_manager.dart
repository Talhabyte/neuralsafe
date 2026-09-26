/// Global (not per-contact), in-memory-only (resets on app restart)
/// cooldown gate for emergency alert dispatch. A restart-reset cooldown
/// is a deliberate choice: a stale persisted "already alerted" state
/// silently suppressing a genuine post-crash re-alert is judged a
/// worse failure mode than an occasional extra alert after a restart.
class AlertCooldownManager {
  AlertCooldownManager({
    this.cooldownDuration = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration cooldownDuration;
  final DateTime Function() _clock;

  DateTime? _lastAlertSentAt;

  /// True if no alert has ever been recorded, or the cooldown has
  /// fully elapsed since the last one.
  bool canSendAlert() {
    final lastSent = _lastAlertSentAt;
    if (lastSent == null) return true;
    return _clock().difference(lastSent) >= cooldownDuration;
  }

  /// Time remaining until the cooldown clears, or null if it's already
  /// clear (or no alert has ever been sent).
  Duration? remainingCooldown() {
    final lastSent = _lastAlertSentAt;
    if (lastSent == null) return null;
    final elapsed = _clock().difference(lastSent);
    if (elapsed >= cooldownDuration) return null;
    return cooldownDuration - elapsed;
  }

  /// Caller invokes this AFTER a dispatch attempt has actually been
  /// made (not on every canSendAlert() check).
  void recordAlertSent() {
    _lastAlertSentAt = _clock();
  }
}
