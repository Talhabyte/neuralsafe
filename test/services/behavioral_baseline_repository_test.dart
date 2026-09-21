import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_baseline.dart';
import 'package:neuralsafe/models/behavioral_feature_vector.dart';
import 'package:neuralsafe/services/behavioral_baseline_repository.dart';
import 'package:neuralsafe/services/feature_vault_service.dart';

BehavioralFeatureVector _sampleVector() {
  return BehavioralFeatureVector(
    windowStart: DateTime(2026, 1, 1),
    windowEnd: DateTime(2026, 1, 1, 1),
    eventCount: 1,
    screenSessionsCount: 1,
    screenSessionsPerHour: 1.0,
    meanScreenSessionMs: 1000,
    medianScreenSessionMs: 1000,
    shortSessionRatio: 0.5,
    userPresentCount: 1,
    appSessionsCount: 1,
    meanAppSessionMs: 2000,
    medianAppSessionMs: 2000,
    appSessionsPerHour: 1.0,
    distinctPackagesCount: 1,
    totalAppUsageMs: 3000,
    topPackageUsageRatio: 1.0,
    perPackageUsageMs: const {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  final fakeSecureStorage = <String, String>{};
  late Directory tempDir;
  late BehavioralBaselineRepository repository;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('neuralsafe_baseline_repo_test_');

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
    repository = BehavioralBaselineRepository();
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
    await repository.clearAll();
  });

  test('loadAll() returns an empty map when nothing stored', () {
    expect(repository.loadAll(), isEmpty);
  });

  test('load() returns null for a windowKey that has never been saved', () {
    expect(repository.load('1h'), isNull);
  });

  test('save() persists a baseline and load() retrieves it by windowKey',
      () async {
    final baseline =
        BehavioralBaseline.initial('1h').updateWith(_sampleVector());

    await repository.save(baseline);

    final loaded = repository.load('1h');
    expect(loaded, isNotNull);
    expect(loaded!.windowKey, '1h');
    expect(loaded.sampleCount, 1);
  });

  test(
      'saving a baseline for a new windowKey does not overwrite an '
      'existing different windowKey', () async {
    final baseline1h =
        BehavioralBaseline.initial('1h').updateWith(_sampleVector());
    final baseline24h =
        BehavioralBaseline.initial('24h').updateWith(_sampleVector());

    await repository.save(baseline1h);
    await repository.save(baseline24h);

    final all = repository.loadAll();
    expect(all.length, 2);
    expect(all['1h'], isNotNull);
    expect(all['24h'], isNotNull);
  });

  test(
      'saving the SAME windowKey twice overwrites rather than '
      'duplicating (single running state per key)', () async {
    var baseline = BehavioralBaseline.initial('1h');
    baseline = baseline.updateWith(_sampleVector());
    await repository.save(baseline);

    baseline = baseline.updateWith(_sampleVector());
    await repository.save(baseline);

    final all = repository.loadAll();
    expect(all.length, 1); // still just one entry for '1h'
    expect(all['1h']!.sampleCount, 2); // reflects the updated state
  });

  test('clearAll() removes all stored baselines', () async {
    final baseline =
        BehavioralBaseline.initial('1h').updateWith(_sampleVector());
    await repository.save(baseline);
    expect(repository.loadAll(), isNotEmpty);

    await repository.clearAll();

    expect(repository.loadAll(), isEmpty);
  });

  test(
      'a saved baseline persists across a fresh load() call reading '
      'the same underlying box (persistence sanity check)', () async {
    final baseline =
        BehavioralBaseline.initial('6h').updateWith(_sampleVector());
    await repository.save(baseline);

    final freshRepository = BehavioralBaselineRepository();
    final loaded = freshRepository.load('6h');

    expect(loaded, isNotNull);
    expect(loaded!.sampleCount, 1);
  });
}
