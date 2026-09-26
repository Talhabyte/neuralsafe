enum LocationStatus {
  success,
  permissionDenied,
  serviceDisabled,
  timeout,
  error
}

/// Result of a single location acquisition attempt. [latitude]/[longitude]
/// are only non-null when [status] is success.
class LocationResult {
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;
  final LocationStatus status;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.status,
  });

  bool get isSuccess => status == LocationStatus.success;

  /// A Google Maps link built from the coordinates, or null if this
  /// result did not succeed. Does not itself decide what to show in a
  /// message when unavailable — that's the caller's responsibility
  /// (see EmergencyAlertDispatcher's message template).
  String? get mapsLink {
    if (!isSuccess || latitude == null || longitude == null) return null;
    return 'https://maps.google.com/?q=$latitude,$longitude';
  }

  @override
  String toString() {
    return 'LocationResult(status: $status, latitude: $latitude, '
        'longitude: $longitude, timestamp: $timestamp)';
  }
}
