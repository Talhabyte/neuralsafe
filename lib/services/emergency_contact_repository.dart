import '../models/emergency_contact.dart';
import 'secure_vault_service.dart';

class EmergencyContactRepository {
  static const _contactsKey = 'emergency_contacts';

  List<EmergencyContact> loadAll() {
    final raw = SecureVaultService.instance.box.get(_contactsKey);
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((entry) => EmergencyContact.fromMap(entry))
        .toList();
  }

  EmergencyContact? loadPrimary() {
    final all = loadAll();
    for (final contact in all) {
      if (contact.isPrimary) return contact;
    }
    return null;
  }

  Future<void> save(EmergencyContact contact) async {
    if (contact.name.trim().isEmpty) {
      throw ArgumentError('Emergency contact name cannot be empty.');
    }
    if (contact.phoneNumber.trim().isEmpty) {
      throw ArgumentError('Emergency contact phone number cannot be empty.');
    }

    final current = loadAll();
    final existingIndex = current.indexWhere((c) => c.id == contact.id);

    final updatedList = current.map((c) {
      if (c.id == contact.id) return c; // replaced below
      if (contact.isPrimary && c.isPrimary) {
        return c.copyWith(isPrimary: false);
      }
      return c;
    }).toList();

    if (existingIndex == -1) {
      updatedList.add(contact);
    } else {
      updatedList[existingIndex] = contact;
    }

    await SecureVaultService.instance.box.put(
      _contactsKey,
      updatedList.map((c) => c.toMap()).toList(),
    );
  }

  Future<void> delete(String id) async {
    final current = loadAll();
    final updatedList = current.where((c) => c.id != id).toList();
    await SecureVaultService.instance.box.put(
      _contactsKey,
      updatedList.map((c) => c.toMap()).toList(),
    );
  }

  Future<void> clearAll() async {
    await SecureVaultService.instance.box.put(_contactsKey, []);
  }
}