import '../models/behavioral_event.dart';
import 'secure_vault_service.dart';

/// Persists BehavioralEvent records to the same encrypted vault box
/// used elsewhere, under a dedicated 'behavioral_events' key holding
/// a List of Maps. No new Hive box, no TypeAdapters — same pattern as
/// EmergencyContactRepository's list-of-maps storage.
///
/// Bounded to the most recent [maxEvents] entries so raw event history
/// can't grow without limit; oldest events roll off first, chronological
/// order is preserved.
class BehavioralEventRepository {
  static const _eventsKey = 'behavioral_events';
  static const int maxEvents = 500;

  List<BehavioralEvent> loadAll() {
    final raw = SecureVaultService.instance.box.get(_eventsKey);
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((entry) => BehavioralEvent.fromMap(entry))
        .toList();
  }

  Future<void> save(BehavioralEvent event) async {
    final current = loadAll()..add(event);

    final trimmed = current.length > maxEvents
        ? current.sublist(current.length - maxEvents)
        : current;

    await SecureVaultService.instance.box.put(
      _eventsKey,
      trimmed.map((e) => e.toMap()).toList(),
    );
  }

  Future<void> clearAll() async {
    await SecureVaultService.instance.box.put(_eventsKey, []);
  }
}
