import 'package:flutter/services.dart';

import 'app_usage_service.dart';

/// Thin Dart wrapper over the native 'neuralsafe/app_usage' MethodChannel.
/// Collects ONLY package name, foreground/background event type, and
/// timestamp — never notification/screen/accessibility content, never
/// keyboard input, never any other app data. See AppUsageChannel.kt for
/// the native-side implementation.
class AppUsageNativeBridge {
  static const _channel = MethodChannel('neuralsafe/app_usage');

  Future<bool> hasUsageAccess() async {
    final result = await _channel.invokeMethod<bool>('hasUsageAccess');
    return result ?? false;
  }

  /// Opens Android's Usage Access settings screen so the user can
  /// manually grant this special-access permission. No runtime dialog
  /// exists for PACKAGE_USAGE_STATS.
  Future<void> openUsageAccessSettings() async {
    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  Future<List<AppUsageRawEvent>> queryEvents(
      DateTime since, DateTime until) async {
    final result = await _channel.invokeMethod<List<dynamic>>('queryEvents', {
      'since': since.millisecondsSinceEpoch,
      'until': until.millisecondsSinceEpoch,
    });

    if (result == null) return [];

    return result
        .whereType<Map<dynamic, dynamic>>()
        .map(_parseRawEvent)
        .whereType<AppUsageRawEvent>()
        .toList();
  }

  AppUsageRawEvent? _parseRawEvent(Map<dynamic, dynamic> raw) {
    final rawType = raw['eventType'] as String?;
    final type = switch (rawType) {
      'foreground' => AppUsageEventType.foreground,
      'background' => AppUsageEventType.background,
      _ => null,
    };
    final packageName = raw['packageName'] as String?;
    final rawTimestamp = raw['timestamp'] as int?;

    if (type == null || packageName == null || rawTimestamp == null) {
      return null; // malformed entry: skip rather than throw
    }

    return AppUsageRawEvent(
      packageName: packageName,
      type: type,
      timestamp: DateTime.fromMillisecondsSinceEpoch(rawTimestamp),
    );
  }
}
