import 'dart:math';

import 'behavioral_feature_vector.dart';

/// The set of numeric BehavioralFeatureVector fields tracked in a
/// baseline. Deliberately excludes perPackageUsageMs (a map, not a
/// scalar) and the raw *Count fields (screenSessionsCount,
/// appSessionsCount, eventCount), which are largely redundant with
/// their corresponding *PerHour rates once window size is fixed.
/// userPresentCount and distinctPackagesCount are kept, as they are
/// not directly duplicated by a rate field elsewhere.
const List<String> trackedFeatureKeys = [
  'screenSessionsPerHour',
  'meanScreenSessionMs',
  'medianScreenSessionMs',
  'shortSessionRatio',
  'userPresentCount',
  'appSessionsPerHour',
  'meanAppSessionMs',
  'medianAppSessionMs',
  'distinctPackagesCount',
  'totalAppUsageMs',
  'topPackageUsageRatio',
];

/// Extracts the value of [featureKey] from [vector] as a double. Throws
/// if [featureKey] is not one of [trackedFeatureKeys].
double featureValueFor(BehavioralFeatureVector vector, String featureKey) {
  switch (featureKey) {
    case 'screenSessionsPerHour':
      return vector.screenSessionsPerHour;
    case 'meanScreenSessionMs':
      return vector.meanScreenSessionMs;
    case 'medianScreenSessionMs':
      return vector.medianScreenSessionMs;
    case 'shortSessionRatio':
      return vector.shortSessionRatio;
    case 'userPresentCount':
      return vector.userPresentCount.toDouble();
    case 'appSessionsPerHour':
      return vector.appSessionsPerHour;
    case 'meanAppSessionMs':
      return vector.meanAppSessionMs;
    case 'medianAppSessionMs':
      return vector.medianAppSessionMs;
    case 'distinctPackagesCount':
      return vector.distinctPackagesCount.toDouble();
    case 'totalAppUsageMs':
      return vector.totalAppUsageMs.toDouble();
    case 'topPackageUsageRatio':
      return vector.topPackageUsageRatio;
    default:
      throw ArgumentError('Unknown feature key: $featureKey');
  }
}

/// Running statistics for a single numeric feature, updated online via
/// Welford's algorithm (numerically stable streaming mean/variance —
/// avoids storing raw historical values and avoids the precision loss
/// of naive incremental variance formulas). Immutable: [updateWith]
/// returns a new instance rather than mutating in place.
class FeatureStat {
  final int count;
  final double mean;

  /// Welford's M2 accumulator: sum of squared differences from the
  /// running mean. Not variance itself — see [variance].
  final double m2;
  final double min;
  final double max;

  const FeatureStat({
    required this.count,
    required this.mean,
    required this.m2,
    required this.min,
    required this.max,
  });

  /// The empty/zero state before any values have been observed. min/max
  /// are +/-infinity so the very first updateWith() correctly becomes
  /// that value's min and max.
  factory FeatureStat.initial() {
    return const FeatureStat(
      count: 0,
      mean: 0.0,
      m2: 0.0,
      min: double.infinity,
      max: double.negativeInfinity,
    );
  }

  /// Sample variance (Bessel-corrected, dividing by count - 1). Returns
  /// 0.0 for count <= 1, where sample variance is undefined — treated
  /// as "no observed variance yet" rather than throwing or NaN.
  double get variance => count > 1 ? m2 / (count - 1) : 0.0;

  double get stdDev => sqrt(variance);

  FeatureStat updateWith(double value) {
    final newCount = count + 1;
    final delta = value - mean;
    final newMean = mean + delta / newCount;
    final delta2 = value - newMean;
    final newM2 = m2 + delta * delta2;

    return FeatureStat(
      count: newCount,
      mean: newMean,
      m2: newM2,
      min: value < min ? value : min,
      max: value > max ? value : max,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'count': count,
      'mean': mean,
      'm2': m2,
      'min': min,
      'max': max,
    };
  }

  factory FeatureStat.fromMap(Map<dynamic, dynamic> map) {
    return FeatureStat(
      count: map['count'] as int,
      mean: (map['mean'] as num).toDouble(),
      m2: (map['m2'] as num).toDouble(),
      min: (map['min'] as num).toDouble(),
      max: (map['max'] as num).toDouble(),
    );
  }

  @override
  String toString() {
    return 'FeatureStat(count: $count, mean: $mean, stdDev: $stdDev, '
        'min: $min, max: $max)';
  }
}

/// A personal behavioral baseline for one window type (identified by
/// [windowKey], e.g. "15m", "1h", "6h", "24h"). Holds running
/// FeatureStat for every key in [trackedFeatureKeys]. Segmentation
/// beyond window size (e.g. weekday/weekend) is intentionally not
/// implemented here — windowKey is a plain string, so a caller wanting
/// that could use keys like "1h_weekday" without any change to this
/// class; that composition is left for a later step.
///
/// Immutable: [updateWith] returns a new instance. All tracked
/// features are always updated together from the same vector, so
/// every FeatureStat's count stays in lockstep — [sampleCount] is
/// therefore well-defined as a single number for the whole baseline.
class BehavioralBaseline {
  final String windowKey;
  final Map<String, FeatureStat> featureStats;
  final DateTime? lastUpdated;

  const BehavioralBaseline({
    required this.windowKey,
    required this.featureStats,
    required this.lastUpdated,
  });

  factory BehavioralBaseline.initial(String windowKey) {
    return BehavioralBaseline(
      windowKey: windowKey,
      featureStats: {
        for (final key in trackedFeatureKeys) key: FeatureStat.initial(),
      },
      lastUpdated: null,
    );
  }

  /// All tracked features share the same count (see class doc), so
  /// sampleCount reads it from the first tracked key. Returns 0 if,
  /// unexpectedly, featureStats is empty.
  int get sampleCount {
    if (featureStats.isEmpty) return 0;
    return featureStats[trackedFeatureKeys.first]?.count ?? 0;
  }

  BehavioralBaseline updateWith(BehavioralFeatureVector vector) {
    final updatedStats = <String, FeatureStat>{};
    for (final key in trackedFeatureKeys) {
      final current = featureStats[key] ?? FeatureStat.initial();
      final value = featureValueFor(vector, key);
      updatedStats[key] = current.updateWith(value);
    }

    return BehavioralBaseline(
      windowKey: windowKey,
      featureStats: updatedStats,
      lastUpdated: vector.windowEnd,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'windowKey': windowKey,
      'featureStats':
          featureStats.map((key, stat) => MapEntry(key, stat.toMap())),
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
    };
  }

  factory BehavioralBaseline.fromMap(Map<dynamic, dynamic> map) {
    final rawStats = map['featureStats'] as Map;
    final rawLastUpdated = map['lastUpdated'] as int?;

    return BehavioralBaseline(
      windowKey: map['windowKey'] as String,
      featureStats: rawStats.map(
        (key, value) => MapEntry(
          key as String,
          FeatureStat.fromMap(value as Map),
        ),
      ),
      lastUpdated: rawLastUpdated != null
          ? DateTime.fromMillisecondsSinceEpoch(rawLastUpdated)
          : null,
    );
  }

  @override
  String toString() {
    return 'BehavioralBaseline(windowKey: $windowKey, '
        'sampleCount: $sampleCount, lastUpdated: $lastUpdated)';
  }
}
