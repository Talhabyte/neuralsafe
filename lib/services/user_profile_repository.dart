import '../models/user_profile.dart';
import 'secure_vault_service.dart';

/// Saves/loads the single UserProfile to the same encrypted vault box
/// used elsewhere, under one 'user_profile' key.
class UserProfileRepository {
  static const _profileKey = 'user_profile';

  /// Null if no profile has been created yet (i.e. onboarding hasn't
  /// reached that step). Synchronous, same reasoning as the other
  /// repositories — Hive keeps the box in memory once opened.
  UserProfile? load() {
    final raw = SecureVaultService.instance.box.get(_profileKey);
    if (raw is! Map) return null;
    return UserProfile.fromMap(raw);
  }

  bool exists() => load() != null;

  Future<void> save(UserProfile profile) async {
    if (profile.name.trim().isEmpty) {
      throw ArgumentError('User profile name cannot be empty.');
    }
    if (!UserProfile.supportedLanguages.contains(profile.preferredLanguage)) {
      throw ArgumentError(
        'preferredLanguage must be one of ${UserProfile.supportedLanguages}.',
      );
    }

    await SecureVaultService.instance.box.put(_profileKey, profile.toMap());
  }

  Future<void> clear() async {
    await SecureVaultService.instance.box.delete(_profileKey);
  }
}
