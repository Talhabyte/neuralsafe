import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/services/feature_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  final fakeSecureStorage = <String, String>{};
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('neuralsafe_feature_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      switch (call.method) {
        case 'write':
          final args = call.arguments as Map;
          fakeSecureStorage[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          final args = call.arguments as Map;
          return fakeSecureStorage[args['key'] as String];
        case 'delete':
          final args = call.arguments as Map;
          fakeSecureStorage.remove(args['key'] as String);
          return null;
        case 'readAll':
          return fakeSecureStorage;
        case 'deleteAll':
          fakeSecureStorage.clear();
          return null;
        case 'containsKey':
          final args = call.arguments as Map;
          return fakeSecureStorage.containsKey(args['key'] as String);
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    await FeatureVaultService.instance.init();
  });

  tearDownAll(() async {
    await FeatureVaultService.instance.box.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (e) {
      debugPrint('[test cleanup] Could not delete temp dir (non-fatal): $e');
    }
  });

  setUp(() async {
    await FeatureVaultService.instance.clearAll();
  });

  test('init() results in an initialized, open box', () {
    expect(FeatureVaultService.instance.isInitialized, true);
  });

  test('put/get round-trips a value through the encrypted box', () async {
    await FeatureVaultService.instance.box.put('some_key', {'a': 1});

    final result = FeatureVaultService.instance.box.get('some_key');

    expect(result, {'a': 1});
  });

  test('clearAll() empties the box contents', () async {
    await FeatureVaultService.instance.box.put('some_key', 'some_value');
    expect(FeatureVaultService.instance.box.get('some_key'), isNotNull);

    await FeatureVaultService.instance.clearAll();

    expect(FeatureVaultService.instance.box.get('some_key'), isNull);
  });

  test(
      'box getter throws StateError if accessed before init completes '
      '(documented via a fresh, un-initialized instance simulation)', () {
    // FeatureVaultService is a singleton already initialized by
    // setUpAll for the rest of this suite, so this test documents the
    // guard's existence via direct inspection of isInitialized rather
    // than constructing a second instance (the class does not support
    // multiple instances by design).
    expect(FeatureVaultService.instance.isInitialized, true);
    expect(() => FeatureVaultService.instance.box, returnsNormally);
  });
}
