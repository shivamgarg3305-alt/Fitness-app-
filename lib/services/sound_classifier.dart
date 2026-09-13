/// What the classifier thinks it heard, in one analysis window.
enum SoundEventKind { snore, talking, ambientNoise }

class SoundClassification {
  final SoundEventKind kind;
  final int intensityLevel; // 0=light, 1=moderate, 2=loud — matches SoundIntensity index
  const SoundClassification({required this.kind, required this.intensityLevel});
}

/// Pluggable classification interface. [HeuristicSoundClassifier] below is
/// the shipped default — a documented, explainable amplitude/pattern
/// heuristic, NOT a trained ML model. Snoring/talking/ambient-noise
/// classification from raw amplitude alone is inherently approximate;
/// swap in a real model (e.g. tflite_flutter + a YAMNet-style audio
/// classifier fed raw PCM) by implementing this interface and passing it
/// to SoundDetectionService's constructor — nothing else needs to change.
abstract class SoundClassifier {
  /// [recentAmplitudesDb] is a rolling window of recent dB readings
  /// (most-recent-last), roughly one sample per [SoundDetectionService]'s
  /// sample interval. Returns null if nothing worth logging was detected.
  SoundClassification? classify(List<double> recentAmplitudesDb, {required Duration sampleInterval});
}

/// Amplitude + simple-pattern heuristic:
///  - Rhythmic peaks every ~1.5-6s, repeated 3+ times → "snore"-like.
///  - Irregular, bursty peaks with high amplitude variance → "talking"-like.
///  - Sustained moderate level with LOW variance (flat, no peaks) →
///    "ambient noise" (fan/AC hum) — cannot identify the actual source;
///    that would require real audio classification, not amplitude alone.
///  - Otherwise → nothing (silence or not enough signal).
///
/// Thresholds are in dBFS as reported by the `record` package's amplitude
/// stream (roughly -160 silence to 0 max) — tune these against real
/// device behavior; they're reasonable starting points, not calibrated.
class HeuristicSoundClassifier implements SoundClassifier {
  final double silenceThresholdDb;
  final double moderateThresholdDb;
  final double loudThresholdDb;

  const HeuristicSoundClassifier({
    this.silenceThresholdDb = -45,
    this.moderateThresholdDb = -30,
    this.loudThresholdDb = -15,
  });

  @override
  SoundClassification? classify(List<double> window, {required Duration sampleInterval}) {
    if (window.length < 4) return null;

    final peakIndices = <int>[];
    for (int i = 0; i < window.length; i++) {
      if (window[i] > silenceThresholdDb) peakIndices.add(i);
    }
    if (peakIndices.isEmpty) return null;

    final peakValues = peakIndices.map((i) => window[i]).toList();
    final avgPeak = peakValues.reduce((a, b) => a + b) / peakValues.length;
    final intensity = _intensityFor(avgPeak);

    // Rhythmic pattern check: gaps between consecutive peaks, in seconds.
    if (peakIndices.length >= 3) {
      final gapsSeconds = <double>[];
      for (int i = 0; i < peakIndices.length - 1; i++) {
        gapsSeconds.add((peakIndices[i + 1] - peakIndices[i]) * sampleInterval.inMilliseconds / 1000.0);
      }
      final rhythmicGaps = gapsSeconds.where((g) => g >= 1.5 && g <= 6.0).length;
      if (rhythmicGaps >= (gapsSeconds.length * 0.6)) {
        return SoundClassification(kind: SoundEventKind.snore, intensityLevel: intensity);
      }
    }

    // Bursty/irregular with real variance → talking-like.
    if (peakValues.length >= 2) {
      final mean = peakValues.reduce((a, b) => a + b) / peakValues.length;
      final variance = peakValues.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / peakValues.length;
      if (variance > 20 && peakValues.length >= 2) {
        return SoundClassification(kind: SoundEventKind.talking, intensityLevel: intensity);
      }
    }

    // Sustained, flat, moderately-elevated level → ambient noise.
    if (peakIndices.length >= (window.length * 0.6) && avgPeak < loudThresholdDb) {
      return SoundClassification(kind: SoundEventKind.ambientNoise, intensityLevel: intensity);
    }

    return null;
  }

  int _intensityFor(double avgPeakDb) {
    if (avgPeakDb >= loudThresholdDb) return 2;
    if (avgPeakDb >= moderateThresholdDb) return 1;
    return 0;
  }
}
