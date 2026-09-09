import '../models/onboarding_state.dart';
import 'secure_vault_service.dart';

/// Saves/loads OnboardingState to the same encrypted vault box used by
/// SecureVaultService. No new box, no new encryption setup — this just
/// adds one more key to the existing one from Step 1.
class OnboardingRepository {
  static const _stateKey = 'onboarding_state';

  /// Synchronous on purpose, same reasoning as SecretCodeService:
  /// Hive keeps the box's contents in memory once opened, so reads
  /// don't need to be async.
  OnboardingState load() {
    final raw = SecureVaultService.instance.box.get(_stateKey);
    if (raw is Map) {
      return OnboardingState.fromMap(raw);
    }
    return OnboardingState.initial();
  }

  Future<void> save(OnboardingState state) async {
    await SecureVaultService.instance.box.put(_stateKey, state.toMap());
  }

  /// Records when onboarding first began, if it hasn't already.
  /// Safe to call repeatedly — won't overwrite an existing startedAt.
  Future<void> markStarted() async {
    final current = load();
    if (current.startedAt != null) return;
    await save(current.copyWith(startedAt: DateTime.now()));
  }

  Future<void> markComplete() async {
    final current = load();
    await save(current.copyWith(
      isComplete: true,
      completedAt: DateTime.now(),
    ));
  }
}