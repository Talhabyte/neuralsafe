import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/models/behavioral_event.dart';
import 'package:neuralsafe/services/behavioral_event_repository.dart';
import 'package:neuralsafe/services/secure_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  final fakeSecureStorage = <String, String>{};
  late Directory tempDir;
  late BehavioralEventRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('neuralsafe_test_');

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

    await SecureVaultService.instance.init();
    repository = BehavioralEventRepository();
  });

  tearDownAll(() async {
    await SecureVaultService.instance.box.close();

    try {
      await tempDir.delete(recursive: true);
    } catch (e) {
      debugPrint('[test cleanup] Could not delete temp dir (non-fatal): $e');
    }
  });

  setUp(() async {
    await repository.clearAll();
  });

  test('loadAll() returns empty list when nothing stored', () {
    expect(repository.loadAll(), isEmpty);
  });

  test('save() persists events and loadAll() returns them in order', () async {
    final first = BehavioralEvent(
      type: BehavioralEventType.screenOff,
      timestamp: DateTime(2026, 1, 1, 8, 0, 0),
    );
    final second = BehavioralEvent(
      type: BehavioralEventType.screenOn,
      timestamp: DateTime(2026, 1, 1, 8, 5, 0),
    );

    await repository.save(first);
    await repository.save(second);

    final loaded = repository.loadAll();

    expect(loaded.length, 2);
    expect(loaded[0].type, BehavioralEventType.screenOff);
    expect(loaded[0].timestamp, first.timestamp);
    expect(loaded[1].type, BehavioralEventType.screenOn);
    expect(loaded[1].timestamp, second.timestamp);
  });

  test('clearAll() empties the stored events', () async {
    await repository.save(BehavioralEvent(
      type: BehavioralEventType.userPresent,
      timestamp: DateTime.now(),
    ));
    expect(repository.loadAll(), isNotEmpty);

    await repository.clearAll();

    expect(repository.loadAll(), isEmpty);
  });

  test('rolling limit keeps only the most recent 500 events, in order',
      () async {
    for (var i = 0; i < 502; i++) {
      await repository.save(BehavioralEvent(
        type: BehavioralEventType.screenOn,
        timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
      ));
    }

    final loaded = repository.loadAll();

    expect(loaded.length, BehavioralEventRepository.maxEvents);
    // Events for minute 0 and minute 1 should have rolled off.
    expect(loaded.first.timestamp,
        DateTime(2026, 1, 1).add(const Duration(minutes: 2)));
    expect(loaded.last.timestamp,
        DateTime(2026, 1, 1).add(const Duration(minutes: 501)));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
