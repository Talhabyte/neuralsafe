import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Owns a SEPARATE encrypted Hive box from SecureVaultService's
/// 'secure_vault' box, with its own independent AES key. This gives
/// Phase 4 data (BehavioralBaseline, AnomalyResultLogEntry) true
/// box-level isolation from Phase 3 raw BehavioralEvent data, which
/// remains exactly where it already is — untouched, in
/// SecureVaultService's box.
///
/// Structurally mirrors SecureVaultService exactly (same key-management
/// pattern via flutter_secure_storage, same Hive.initFlutter() +
/// HiveAesCipher approach) but is a distinct sibling service, not a
/// modification of the protected secure_vault_service.dart.
class FeatureVaultService {
  FeatureVaultService._();
  static final FeatureVaultService instance = FeatureVaultService._();

  static const _boxName = 'feature_vault';
  static const _keyStorageName = 'neuralsafe_feature_vault_key';

  final _secureStorage = const FlutterSecureStorage();
  Box? _box;

  bool get isInitialized => _box != null && _box!.isOpen;

  /// Call once, before use. Idempotent — safe to call again.
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
        'FeatureVaultService.init() must complete before the vault is used.',
      );
    }
    return _box!;
  }

  /// Wipes the vault's *contents* (not the encryption key). Exposed for
  /// testing, mirroring SecureVaultService's clearAll().
  Future<void> clearAll() async {
    await box.clear();
  }
}
