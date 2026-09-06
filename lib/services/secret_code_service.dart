/// Detects "hidden meaning" in what looks like ordinary calculator input.
///
/// Phase 1 note: codes are hardcoded here for development only.
/// Phase 2 will move these into the encrypted local database so each
/// user can set their own codes during onboarding, and so the codes
/// never appear in source control or a decompiled APK as plain strings.
library;

enum CodeAction { none, openDashboard, silentDecoyAlarm }

class SecretCodeService {
  // TODO(Phase 2): replace with encrypted-storage-backed values.
  static const String _dashboardCode = '1207=';
  static const String _decoyAlarmCode = '9110=';

  /// [rawInput] is the full string currently shown on the calculator
  /// display, including the trailing '=' if the user just pressed it.
  CodeAction evaluate(String rawInput) {
    if (rawInput == _dashboardCode) {
      return CodeAction.openDashboard;
    }
    if (rawInput == _decoyAlarmCode) {
      return CodeAction.silentDecoyAlarm;
    }
    return CodeAction.none;
  }
}
