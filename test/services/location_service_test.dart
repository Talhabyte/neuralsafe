import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:neuralsafe/models/location_result.dart';
import 'package:neuralsafe/services/location_service.dart';

void main() {
  final fixedNow = DateTime(2026, 9, 24, 12, 0, 0);

  group('LocationService.acquireCurrentLocation', () {
    test('returns success with coordinates when everything succeeds', () async {
      final service = LocationService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async => LocationPermission.whileInUse,
        getPosition: () async => Position(
          latitude: 33.7,
          longitude: 73.1,
          timestamp: fixedNow,
          accuracy: 5.0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
        clock: () => fixedNow,
      );

      final result = await service.acquireCurrentLocation();

      expect(result.status, LocationStatus.success);
      expect(result.latitude, 33.7);
      expect(result.longitude, 73.1);
      expect(result.mapsLink, 'https://maps.google.com/?q=33.7,73.1');
    });

    test('returns serviceDisabled when location services are off', () async {
      final service = LocationService(
        isLocationServiceEnabled: () async => false,
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async => LocationPermission.whileInUse,
        getPosition: () async => throw StateError('should not be called'),
        clock: () => fixedNow,
      );

      final result = await service.acquireCurrentLocation();

      expect(result.status, LocationStatus.serviceDisabled);
      expect(result.latitude, isNull);
      expect(result.mapsLink, isNull);
    });

    test(
        'requests permission when initially denied, then succeeds if '
        'granted', () async {
      var requestCalled = false;
      final service = LocationService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async {
          requestCalled = true;
          return LocationPermission.whileInUse;
        },
        getPosition: () async => Position(
          latitude: 1.0,
          longitude: 2.0,
          timestamp: fixedNow,
          accuracy: 5.0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
        clock: () => fixedNow,
      );

      final result = await service.acquireCurrentLocation();

      expect(requestCalled, true);
      expect(result.status, LocationStatus.success);
    });

    test('returns permissionDenied if still denied after requesting', () async {
      final service = LocationService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async => LocationPermission.denied,
        getPosition: () async => throw StateError('should not be called'),
        clock: () => fixedNow,
      );

      final result = await service.acquireCurrentLocation();

      expect(result.status, LocationStatus.permissionDenied);
    });

    test('returns permissionDenied when permanently denied', () async {
      final service = LocationService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.deniedForever,
        requestPermission: () async =>
            throw StateError('should not be called for deniedForever'),
        getPosition: () async => throw StateError('should not be called'),
        clock: () => fixedNow,
      );

      final result = await service.acquireCurrentLocation();

      expect(result.status, LocationStatus.permissionDenied);
    });

    test(
        'returns timeout if getPosition takes longer than the '
        'configured timeout', () async {
      final service = LocationService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async => LocationPermission.whileInUse,
        getPosition: () async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return Position(
            latitude: 1.0,
            longitude: 2.0,
            timestamp: fixedNow,
            accuracy: 5.0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        },
        clock: () => fixedNow,
        timeout: const Duration(milliseconds: 10),
      );

      final result = await service.acquireCurrentLocation();

      expect(result.status, LocationStatus.timeout);
    });

    test('returns error if getPosition throws', () async {
      final service = LocationService(
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async => LocationPermission.whileInUse,
        getPosition: () async => throw Exception('GPS hardware failure'),
        clock: () => fixedNow,
      );

      final result = await service.acquireCurrentLocation();

      expect(result.status, LocationStatus.error);
    });

    test('mapsLink is null for every non-success status', () async {
      final service = LocationService(
        isLocationServiceEnabled: () async => false,
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async => LocationPermission.whileInUse,
        getPosition: () async => throw StateError('should not be called'),
        clock: () => fixedNow,
      );

      final result = await service.acquireCurrentLocation();

      expect(result.mapsLink, isNull);
    });
  });
}
