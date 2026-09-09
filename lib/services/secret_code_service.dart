library;
import 'package:flutter/foundation.dart';

import 'secure_vault_service.dart';

/// Detects "hidden meaning" in what looks like ordinary calculator input.
///
/// As of Step 2, the actual codes are no longer hardcoded — they're read
/// from (and, on first run, seeded into) the encrypted vault opened in
/// Step 1. The public API is unchanged from Phase 1 on purpose, so
/// `calculator_screen.dart` doesn't need to know anything changed.


enum CodeAction { none, openDashboard, silentDecoyAlarm }

class SecretCodeService {
  static const String _dashboardCodeKey = 'secret_code_dashboard';
  static const String _decoyCodeKey = 'secret_code_decoy';

  // Used ONLY the very first time the vault has no codes stored yet.
  // Once seeded, these constants are dead weight — the vault is the
  // single source of truth from then on.
  static const String _defaultDashboardCode = '1207=';
  static const String _defaultDecoyCode = '9110=';

  bool _seeded = false;

  void _ensureSeeded() {
    if (_seeded) return;
    final vaultBox = SecureVaultService.instance.box;

    final hasDashboardCode = vaultBox.get(_dashboardCodeKey) != null;
    final hasDecoyCode = vaultBox.get(_decoyCodeKey) != null;

    if (!hasDashboardCode || !hasDecoyCode) {
      if (kDebugMode) {
        debugPrint(
          '[NeuralSafe] First run detected — seeding default secret codes '
          'into the encrypted vault.',
        );
      }
    }

    if (!hasDashboardCode) {
      vaultBox.put(_dashboardCodeKey, _defaultDashboardCode);
    }
    if (!hasDecoyCode) {
      vaultBox.put(_decoyCodeKey, _defaultDecoyCode);
    }

    _seeded = true;
  }

  /// [rawInput] is the full string currently shown on the calculator
  /// display, including the trailing '=' if the user just pressed it.
  CodeAction evaluate(String rawInput) {
    _ensureSeeded();
    final vaultBox = SecureVaultService.instance.box;

    final dashboardCode = vaultBox.get(_dashboardCodeKey) as String?;
    final decoyCode = vaultBox.get(_decoyCodeKey) as String?;

    if (dashboardCode != null && rawInput == dashboardCode) {
      return CodeAction.openDashboard;
    }
    if (decoyCode != null && rawInput == decoyCode) {
      return CodeAction.silentDecoyAlarm;
    }
    return CodeAction.none;
  }

  // --- Not wired into any UI yet — for Step 6's setup screen. ---

  Future<void> setDashboardCode(String rawInputWithEquals) async {
    await SecureVaultService.instance.box
        .put(_dashboardCodeKey, rawInputWithEquals);
  }

  Future<void> setDecoyCode(String rawInputWithEquals) async {
    await SecureVaultService.instance.box
        .put(_decoyCodeKey, rawInputWithEquals);
  }

  String? currentDashboardCode() =>
      SecureVaultService.instance.box.get(_dashboardCodeKey) as String?;

  String? currentDecoyCode() =>
      SecureVaultService.instance.box.get(_decoyCodeKey) as String?;
}