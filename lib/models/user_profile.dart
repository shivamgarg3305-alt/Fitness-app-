/// The user's physical profile — persisted locally, used to make the
/// HR-zone/Strain math (and eventually Healthspan) reflect the actual
/// person instead of a hardcoded default age.
class UserProfile {
  final DateTime? dateOfBirth; // preferred source of truth for age
  final int? manualAge; // fallback if the user doesn't want to give a DOB
  final double? maxHeartRateBpm; // known/measured max HR, overrides the Fox formula
  final double? heightCm;
  final double? weightKg;
  final String? biologicalSex; // 'male' | 'female' | 'unspecified' — stored for future use, not used in current formulas

  const UserProfile({
    this.dateOfBirth,
    this.manualAge,
    this.maxHeartRateBpm,
    this.heightCm,
    this.weightKg,
    this.biologicalSex,
  });

  static const empty = UserProfile();

  bool get isConfigured => dateOfBirth != null || manualAge != null;

  /// Resolved age: derived from DOB if given (kept accurate as time
  /// passes), else the manually entered age, else null (caller decides
  /// the fallback — HeartRateZoneBreakdown/StrainScreen use 30 with a
  /// visible "set up your profile" prompt, not a silent default).
  int? get resolvedAge {
    if (dateOfBirth != null) {
      final now = DateTime.now();
      int age = now.year - dateOfBirth!.year;
      final hadBirthdayThisYear =
          (now.month > dateOfBirth!.month) || (now.month == dateOfBirth!.month && now.day >= dateOfBirth!.day);
      if (!hadBirthdayThisYear) age -= 1;
      return age;
    }
    return manualAge;
  }

  /// Resolved max HR: the user's known value if set, else the Fox
  /// formula (220 - age) from [resolvedAge], else null if neither is
  /// available.
  double? get resolvedMaxHeartRate {
    if (maxHeartRateBpm != null) return maxHeartRateBpm;
    final age = resolvedAge;
    return age != null ? (220 - age).toDouble() : null;
  }

  UserProfile copyWith({
    DateTime? dateOfBirth,
    int? manualAge,
    double? maxHeartRateBpm,
    double? heightCm,
    double? weightKg,
    String? biologicalSex,
  }) {
    return UserProfile(
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      manualAge: manualAge ?? this.manualAge,
      maxHeartRateBpm: maxHeartRateBpm ?? this.maxHeartRateBpm,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      biologicalSex: biologicalSex ?? this.biologicalSex,
    );
  }

  Map<String, dynamic> toJson() => {
        'dob': dateOfBirth?.toIso8601String(),
        'manualAge': manualAge,
        'maxHr': maxHeartRateBpm,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'sex': biologicalSex,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        dateOfBirth: json['dob'] != null ? DateTime.parse(json['dob'] as String) : null,
        manualAge: json['manualAge'] as int?,
        maxHeartRateBpm: (json['maxHr'] as num?)?.toDouble(),
        heightCm: (json['heightCm'] as num?)?.toDouble(),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        biologicalSex: json['sex'] as String?,
      );
}
