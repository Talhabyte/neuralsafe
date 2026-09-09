/// The single local user profile. Unlike EmergencyContact, there's only
/// ever one of these, so it's stored as a single Map under one vault
/// key rather than a list.
class UserProfile {
  final String name;
  final String preferredLanguage; // 'en' or 'ur'
  final DateTime createdAt;

  const UserProfile({
    required this.name,
    required this.preferredLanguage,
    required this.createdAt,
  });

  static const supportedLanguages = ['en', 'ur'];

  UserProfile copyWith({
    String? name,
    String? preferredLanguage,
    DateTime? createdAt,
  }) {
    return UserProfile(
      name: name ?? this.name,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'preferredLanguage': preferredLanguage,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory UserProfile.fromMap(Map map) {
    final createdAtMillis = map['createdAt'] as int?;
    return UserProfile(
      name: map['name'] as String? ?? '',
      preferredLanguage: map['preferredLanguage'] as String? ?? 'en',
      createdAt: createdAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMillis)
          : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'UserProfile(name: $name, preferredLanguage: $preferredLanguage, '
        'createdAt: $createdAt)';
  }
}
