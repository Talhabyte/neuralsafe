import '../models/behavioral_event.dart';
import '../models/behavioral_feature_vector.dart';
import 'behavioral_event_repository.dart';

/// Stateless, on-demand feature computation engine. Deliberately has
/// no start()/stop()/timer, unlike every Phase 3 collector — nothing
/// here runs continuously; a vector is computed only when explicitly
/// requested. Any periodic pre-computation/caching is intentionally
/// left for a later step, layered on top of this class rather than
/// built into it.
///
/// [loadEvents] is injectable (defaults to querying
/// BehavioralEventRepository.loadAll() and filtering client-side by
/// timestamp, since the repository itself is not being extended with
/// a native range-query method in this step) so this can be fully
/// unit tested with plain event lists, no vault involved. [clock] is
/// injectable for deterministic "now"-relative window tests.
class FeatureExtractor {
  FeatureExtractor({
    List<BehavioralEvent> Function(DateTime start, DateTime end)? loadEvents,
    DateTime Function()? clock,
  })  : _loadEvents = loadEvents ?? _defaultLoadEvents,
        _clock = clock ?? DateTime.now;

  final List<BehavioralEvent> Function(DateTime start, DateTime end)
      _loadEvents;
  final DateTime Function() _clock;

  static List<BehavioralEvent> _defaultLoadEvents(
      DateTime start, DateTime end) {
    return BehavioralEventRepository()
        .loadAll()
        .where((e) => !e.timestamp.isBefore(start) && e.timestamp.isBefore(end))
        .toList();
  }

  /// Computes a feature vector over the explicit half-open window
  /// [start, end). An event exactly at [end] belongs to the NEXT
  /// window, not this one — consistent with the boundary semantics
  /// already used by AppUsageService and BehavioralEventAggregator.
  BehavioralFeatureVector extractWindow(DateTime start, DateTime end) {
    final events = _loadEvents(start, end);
    return BehavioralFeatureVector.fromEvents(
      events: events,
      windowStart: start,
      windowEnd: end,
    );
  }

  /// Computes a feature vector over a CALENDAR-ALIGNED window of
  /// [windowSize] containing [referenceTime] (defaults to now):
  /// top-of-the-hour for windows dividing evenly into an hour,
  /// midnight-aligned for a 24-hour window, etc. [windowSize] must
  /// evenly divide 24 hours for alignment to behave as a clean
  /// calendar boundary (true for 15m/1h/6h/24h); other sizes still
  /// work but align relative to local midnight rather than a more
  /// "natural" boundary for that size.
  BehavioralFeatureVector extractCalendarWindow(
    Duration windowSize, {
    DateTime? referenceTime,
  }) {
    final reference = referenceTime ?? _clock();
    final midnight = DateTime(reference.year, reference.month, reference.day);
    final elapsedMs = reference.difference(midnight).inMilliseconds;
    final windowSizeMs = windowSize.inMilliseconds;
    final flooredMs = elapsedMs - (elapsedMs % windowSizeMs);

    final start = midnight.add(Duration(milliseconds: flooredMs));
    final end = start.add(windowSize);

    return extractWindow(start, end);
  }

  /// Computes a feature vector over a TRAILING/ROLLING window of
  /// [windowSize] ending now (or [now], if provided) — NOT
  /// calendar-aligned. Intended for real-time/on-demand queries where
  /// "the last N minutes" matters more than day-over-day comparability.
  BehavioralFeatureVector extractRecent(Duration windowSize, {DateTime? now}) {
    final end = now ?? _clock();
    final start = end.subtract(windowSize);
    return extractWindow(start, end);
  }
}
