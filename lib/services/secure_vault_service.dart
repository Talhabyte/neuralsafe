import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Owns the one encrypted Hive box the rest of the app's sensitive data
/// lives in: secret/decoy codes (Step 2), emergency contacts (Step 4),
/// user profile (Step 5), and onboarding state (Step 3).
///
/// The AES key itself never touches disk in plaintext — it's generated
/// once and handed to `flutter_secure_storage`, which is backed by the
/// Android Keystore / iOS Keychain. Hive then uses that key to encrypt
/// every value written into the box.
class SecureVaultService {
  SecureVaultService._();
  static final SecureVaultService instance = SecureVaultService._();

  static const _boxName = 'secure_vault';
  static const _keyStorageName = 'neuralsafe_vault_key';

  final _secureStorage = const FlutterSecureStorage();
  Box? _box;

  bool get isInitialized => _box != null && _box!.isOpen;

  /// Call once, before runApp(). Idempotent — safe to call again.
  Future<void> init() async {
    if (isInitialized) return;

    await Hive.initFlutter();

    final encryptionKey = await _getOrCreateEncryptionKey();
    _box = await Hive.openBox(
      _boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  Future<List<int>> _getOrCreateEncryptionKey() async {
    final existing = await _secureStorage.read(key: _keyStorageName);
    if (existing != null) {
      return base64Decode(existing);
    }

    // Hive's AES cipher expects a 256-bit (32-byte) key.
    final random = Random.secure();
    final newKey = List<int>.generate(32, (_) => random.nextInt(256));
    await _secureStorage.write(
      key: _keyStorageName,
      value: base64Encode(newKey),
    );
    return newKey;
  }

  Box get box {
    if (!isInitialized) {
      throw StateError(
        'SecureVaultService.init() must complete before the vault is used.',
      );
    }
    return _box!;
  }

  /// Wipes the vault's *contents* (not the encryption key). Exposed for
  /// testing right now; a real "panic wipe" feature can reuse this later.
  Future<void> clearAll() async {
    await box.clear();
  }
}