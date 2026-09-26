import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/location_result.dart';

/// Wraps geolocator for one-shot current-location acquisition. Every
/// geolocator call is behind an injectable function, so this is fully
/// unit testable without real GPS — same pattern as every other
/// native-adjacent service in this codebase (e.g. AppUsageService).
class LocationService {
  LocationService({
    Future<bool> Function()? isLocationServiceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? getPosition,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 15),
  })  : _isLocationServiceEnabled =
            isLocationServiceEnabled ?? Geolocator.isLocationServiceEnabled,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _getPosition = getPosition ??
            (() => Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high)),
        _clock = clock ?? DateTime.now;

  final Future<bool> Function() _isLocationServiceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function() _getPosition;
  final DateTime Function() _clock;
  final Duration timeout;

  Future<LocationResult> acquireCurrentLocation() async {
    final now = _clock();

    final serviceEnabled = await _isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationResult(
        latitude: null,
        longitude: null,
        timestamp: now,
        status: LocationStatus.serviceDisabled,
      );
    }

    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return LocationResult(
        latitude: null,
        longitude: null,
        timestamp: now,
        status: LocationStatus.permissionDenied,
      );
    }

    try {
      final position = await _getPosition().timeout(timeout);
      return LocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: now,
        status: LocationStatus.success,
      );
    } on TimeoutException {
      return LocationResult(
        latitude: null,
        longitude: null,
        timestamp: now,
        status: LocationStatus.timeout,
      );
    } catch (_) {
      return LocationResult(
        latitude: null,
        longitude: null,
        timestamp: now,
        status: LocationStatus.error,
      );
    }
  }
}
