/// Tracks how far the user has gotten through initial setup.
///
/// Kept intentionally minimal for Step 3: just enough to know whether
/// setup is done, and when the (future) 7-day behavioral baseline period
/// started/finished. No UI reads or writes this yet — that's Step 6.
class OnboardingState {
  final bool isComplete;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const OnboardingState({
    required this.isComplete,
    this.startedAt,
    this.completedAt,
  });

  factory OnboardingState.initial() => const OnboardingState(
        isComplete: false,
        startedAt: null,
        completedAt: null,
      );

  OnboardingState copyWith({
    bool? isComplete,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return OnboardingState(
      isComplete: isComplete ?? this.isComplete,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isComplete': isComplete,
      'startedAt': startedAt?.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
    };
  }

  factory OnboardingState.fromMap(Map? map) {
    if (map == null) return OnboardingState.initial();

    final startedAtMillis = map['startedAt'] as int?;
    final completedAtMillis = map['completedAt'] as int?;

    return OnboardingState(
      isComplete: map['isComplete'] as bool? ?? false,
      startedAt: startedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(startedAtMillis)
          : null,
      completedAt: completedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(completedAtMillis)
          : null,
    );
  }

  @override
  String toString() {
    return 'OnboardingState(isComplete: $isComplete, '
        'startedAt: $startedAt, completedAt: $completedAt)';
  }
}