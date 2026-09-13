enum SoundIntensity { light, moderate, loud }

/// A single detected sound event during a sleep session.
class SoundEvent {
  final String type; // "Snore", "Talking", "Ambient Noise", ...
  final String detail; // "(Moderate)", "(Fan)", ...
  final DateTime timestamp;
  final SoundIntensity intensity;

  const SoundEvent({
    required this.type,
    required this.detail,
    required this.timestamp,
    this.intensity = SoundIntensity.light,
  });

  String get formattedTime {
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final suffix = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'detail': detail,
        'timestamp': timestamp.toIso8601String(),
        'intensity': intensity.name,
      };

  factory SoundEvent.fromJson(Map<String, dynamic> json) => SoundEvent(
        type: json['type'] as String,
        detail: json['detail'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        intensity: SoundIntensity.values.firstWhere(
          (e) => e.name == json['intensity'],
          orElse: () => SoundIntensity.light,
        ),
      );
}
