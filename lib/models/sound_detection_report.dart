import 'package:flutter/material.dart';
import '../models/sound_event.dart';
import '../theme/app_colors.dart';

export '../models/sound_event.dart';

/// "Sound Detection Report" — a connected timeline of detected sound
/// events with a waveform glyph, label, and timestamp per row.
class SoundDetectionReport extends StatelessWidget {
  final List<SoundEvent> events;

  const SoundDetectionReport({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sound Detection Report',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < events.length; i++) ...[
            _SoundEventRow(event: events[i], isLast: i == events.length - 1),
          ],
        ],
      ),
    );
  }
}

class _SoundEventRow extends StatelessWidget {
  final SoundEvent event;
  final bool isLast;

  const _SoundEventRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
                child: const Icon(Icons.mic_none_rounded, color: AppColors.textSecondary, size: 16),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22, top: 4),
              child: Row(
                children: [
                  _Waveform(intensity: event.intensity),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        children: [
                          TextSpan(text: '${event.formattedTime} - ', style: const TextStyle(color: AppColors.textSecondary)),
                          TextSpan(text: '${event.type} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(text: event.detail, style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small static waveform glyph; bar heights scale with [intensity].
class _Waveform extends StatelessWidget {
  final SoundIntensity intensity;
  const _Waveform({required this.intensity});

  @override
  Widget build(BuildContext context) {
    final List<double> heights = switch (intensity) {
      SoundIntensity.light => [6, 10, 6, 12, 6],
      SoundIntensity.moderate => [8, 16, 10, 18, 9],
      SoundIntensity.loud => [10, 22, 14, 24, 12],
    };

    return SizedBox(
      width: 40,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: heights
            .map((h) => Container(
                  width: 3,
                  height: h,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
