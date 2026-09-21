import '../models/behavioral_baseline.dart';
import 'feature_vault_service.dart';

/// Persists BehavioralBaseline states to FeatureVaultService's box,
/// under a dedicated 'behavioral_baselines' key holding a
/// `Map<String, Map>` (window key -> baseline-as-Map). One baseline
/// per window key — saving overwrites the previous state for that key
/// (a baseline is a single running state, not a history), mirroring
/// UserProfileRepository's single-record-per-slot pattern rather than
/// BehavioralEventRepository's rolling-list pattern.
class BehavioralBaselineRepository {
  static const _baselinesKey = 'behavioral_baselines';

  Map<String, BehavioralBaseline> loadAll() {
    final raw = FeatureVaultService.instance.box.get(_baselinesKey);
    if (raw is! Map) return {};

    final result = <String, BehavioralBaseline>{};
    raw.forEach((key, value) {
      if (value is Map) {
        result[key as String] = BehavioralBaseline.fromMap(value);
      }
    });
    return result;
  }

  BehavioralBaseline? load(String windowKey) {
    return loadAll()[windowKey];
  }

  Future<void> save(BehavioralBaseline baseline) async {
    final current = loadAll();
    current[baseline.windowKey] = baseline;

    await FeatureVaultService.instance.box.put(
      _baselinesKey,
      current.map((key, value) => MapEntry(key, value.toMap())),
    );
  }

  Future<void> clearAll() async {
    await FeatureVaultService.instance.box.delete(_baselinesKey);
  }
}
