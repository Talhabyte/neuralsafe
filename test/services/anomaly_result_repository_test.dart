import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/services/anomaly_evaluator.dart';
import 'package:neuralsafe/services/anomaly_result_repository.dart';
import 'package:neuralsafe/services/feature_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  final fakeSecureStorage = <String, String>{};
  late Directory tempDir;
  late AnomalyResultRepository repository;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('neuralsafe_anomaly_repo_test_');

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
    repository = AnomalyResultRepository();
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

  const evaluatedResult = AnomalyResult(
    status: AnomalyStatus.evaluated,
    featureZScores: {'meanScreenSessionMs': 1.2},
    aggregateScore: 40.0,
    sampleCountUsed: 12,
  );

  const coldStartResult = AnomalyResult(
    status: AnomalyStatus.coldStart,
    featureZScores: {},
    aggregateScore: 0.0,
    sampleCountUsed: 3,
  );

  test('loadAll() returns an empty list when nothing stored', () {
    expect(repository.loadAll(), isEmpty);
  });

  test(
      'save() persists an entry and loadAll() returns it with correct '
      'metadata', () async {
    final evaluatedAt = DateTime(2026, 3, 1, 10, 0, 0);

    await repository.save(
      evaluatedResult,
      evaluatedAt: evaluatedAt,
      windowKey: '1h',
    );

    final all = repository.loadAll();
    expect(all.length, 1);
    expect(all.first.evaluatedAt, evaluatedAt);
    expect(all.first.windowKey, '1h');
    expect(all.first.result.aggregateScore, 40.0);
    expect(all.first.result.status, AnomalyStatus.evaluated);
  });

  test('multiple saves accumulate in chronological order', () async {
    await repository.save(
      coldStartResult,
      evaluatedAt: DateTime(2026, 3, 1, 9, 0, 0),
      windowKey: '1h',
    );
    await repository.save(
      evaluatedResult,
      evaluatedAt: DateTime(2026, 3, 1, 10, 0, 0),
      windowKey: '1h',
    );

    final all = repository.loadAll();
    expect(all.length, 2);
    expect(all[0].result.status, AnomalyStatus.coldStart);
    expect(all[1].result.status, AnomalyStatus.evaluated);
  });

  test('the rolling cap keeps only the most recent 500 entries', () async {
    for (var i = 0; i < 502; i++) {
      await repository.save(
        evaluatedResult,
        evaluatedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        windowKey: '1h',
      );
    }

    final all = repository.loadAll();

    expect(all.length, AnomalyResultRepository.maxEntries);
    expect(
      all.first.evaluatedAt,
      DateTime(2026, 1, 1).add(const Duration(minutes: 2)),
    );
    expect(
      all.last.evaluatedAt,
      DateTime(2026, 1, 1).add(const Duration(minutes: 501)),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('clearAll() empties the stored log', () async {
    await repository.save(
      evaluatedResult,
      evaluatedAt: DateTime.now(),
      windowKey: '1h',
    );
    expect(repository.loadAll(), isNotEmpty);

    await repository.clearAll();

    expect(repository.loadAll(), isEmpty);
  });
}
