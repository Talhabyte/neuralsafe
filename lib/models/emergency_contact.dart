import 'dart:math';

/// A single emergency contact who may receive an alert.
///
/// Storage-layer validation (non-empty name/phone) lives in
/// EmergencyContactRepository.save(), not here — this class just
/// represents the data.
class EmergencyContact {
  final String id;
  final String name;
  final String phoneNumber;
  final bool isPrimary;
  final DateTime createdAt;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.isPrimary,
    required this.createdAt,
  });

  factory EmergencyContact.create({
    required String name,
    required String phoneNumber,
    bool isPrimary = false,
  }) {
    final random = Random.secure();
    final uniqueId =
        '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 31)}';
    return EmergencyContact(
      id: uniqueId,
      name: name,
      phoneNumber: phoneNumber,
      isPrimary: isPrimary,
      createdAt: DateTime.now(),
    );
  }

  EmergencyContact copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    bool? isPrimary,
    DateTime? createdAt,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'isPrimary': isPrimary,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory EmergencyContact.fromMap(Map map) {
    final createdAtMillis = map['createdAt'] as int?;
    return EmergencyContact(
      id: map['id'] as String,
      name: map['name'] as String,
      phoneNumber: map['phoneNumber'] as String,
      isPrimary: map['isPrimary'] as bool? ?? false,
      createdAt: createdAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMillis)
          : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'EmergencyContact(id: $id, name: $name, isPrimary: $isPrimary, '
        'createdAt: $createdAt)';
  }
}