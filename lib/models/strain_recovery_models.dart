import 'package:health/health.dart';

/// Heart-rate training zones, computed from an estimated max HR
/// (220 - age, the standard Fox formula — a rough population estimate,
/// not a lab-measured max). Zone bpm floors follow common %-of-max bands.
enum HrZone { zone1, zone2, zone3, zone4, zone5 }

class HeartRateZoneBreakdown {
  final Map<HrZone, Duration> durations;
  final int? maxHeartRateBpm;

  const HeartRateZoneBreakdown({required this.durations, required this.maxHeartRateBpm});

  Duration get totalActive => durations.values.fold(Duration.zero, (a, b) => a + b);

  factory HeartRateZoneBreakdown.fromHeartRatePoints(
    List<HealthDataPoint> points, {
    required int age,
    double? knownMaxHeartRate,
  }) {
    final maxHr = knownMaxHeartRate ?? (220 - age).toDouble();
    final bounds = {
      HrZone.zone1: 0.50 * maxHr,
      HrZone.zone2: 0.60 * maxHr,
      HrZone.zone3: 0.70 * maxHr,
      HrZone.zone4: 0.80 * maxHr,
      HrZone.zone5: 0.90 * maxHr,
    };

    final durations = {for (final z in HrZone.values) z: Duration.zero};
    final sorted = [...points]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

    for (int i = 0; i < sorted.length - 1; i++) {
      final value = sorted[i].value;
      if (value is! NumericHealthValue) continue;
      final bpm = value.numericValue.toDouble();
      final segmentDuration = sorted[i + 1].dateFrom.difference(sorted[i].dateFrom);
      if (segmentDuration.isNegative || segmentDuration > const Duration(minutes: 10)) {
        continue; // gap too large to attribute to a single reading
      }
      final zone = _zoneFor(bpm, bounds);
      if (zone != null) {
        durations[zone] = durations[zone]! + segmentDuration;
      }
    }
    return HeartRateZoneBreakdown(durations: durations, maxHeartRateBpm: maxHr.round());
  }

  static HrZone? _zoneFor(double bpm, Map<HrZone, double> bounds) {
    if (bpm < bounds[HrZone.zone1]!) return null; // below zone 1 — resting
    if (bpm < bounds[HrZone.zone2]!) return HrZone.zone1;
    if (bpm < bounds[HrZone.zone3]!) return HrZone.zone2;
    if (bpm < bounds[HrZone.zone4]!) return HrZone.zone3;
    if (bpm < bounds[HrZone.zone5]!) return HrZone.zone4;
    return HrZone.zone5;
  }
}

/// Strain — a 0-21 heuristic scale in the shape of WHOOP's (their formula
/// is proprietary; this is our own approximation combining time-in-zone,
/// weighted by intensity, plus a step-volume contribution).
class StrainScore {
  final double value; // 0-21
  final HeartRateZoneBreakdown zones;

  const StrainScore({required this.value, required this.zones});

  factory StrainScore.compute({
    required HeartRateZoneBreakdown zones,
    required int steps,
  }) {
    const zoneWeights = {
      HrZone.zone1: 0.5,
      HrZone.zone2: 1.0,
      HrZone.zone3: 2.0,
      HrZone.zone4: 3.5,
      HrZone.zone5: 5.0,
    };
    double points = 0;
    zones.durations.forEach((zone, duration) {
      points += (duration.inMinutes) * zoneWeights[zone]!;
    });
    // Step volume contributes a smaller, log-dampened amount so walking
    // alone doesn't approach cardio-zone strain levels.
    final stepContribution = steps <= 0 ? 0.0 : (steps / 1000).clamp(0, 15);
    final raw = points / 40 + stepContribution * 0.3; // scaling constants tuned to land ~0-21
    return StrainScore(value: raw.clamp(0, 21), zones: zones);
  }
}

/// Recovery — 0-100%, blended from HRV vs. a rolling baseline, RHR vs.
/// baseline, and last night's sleep performance. Heuristic, not WHOOP's
/// algorithm.
class RecoveryScore {
  final int percent; // 0-100
  final double? hrvDeltaFromBaselinePercent;
  final double? rhrDeltaFromBaselinePercent;

  const RecoveryScore({
    required this.percent,
    required this.hrvDeltaFromBaselinePercent,
    required this.rhrDeltaFromBaselinePercent,
  });

  /// [baselineHrv]/[baselineRhr] should be a rolling ~30-day average the
  /// caller maintains (e.g. persisted locally); pass null if not yet
  /// established (first two weeks of use) and this falls back to sleep
  /// performance alone.
  factory RecoveryScore.compute({
    required double? todayHrv,
    required double? baselineHrv,
    required double? todayRhr,
    required double? baselineRhr,
    required int sleepPerformanceScore,
  }) {
    double? hrvDelta;
    double? rhrDelta;
    double hrvComponent = sleepPerformanceScore.toDouble(); // neutral fallback
    double rhrComponent = sleepPerformanceScore.toDouble();

    if (todayHrv != null && baselineHrv != null && baselineHrv > 0) {
      hrvDelta = (todayHrv - baselineHrv) / baselineHrv * 100;
      // Higher-than-baseline HRV → better recovery. Scale delta into 0-100.
      hrvComponent = (50 + hrvDelta * 2).clamp(0, 100);
    }
    if (todayRhr != null && baselineRhr != null && baselineRhr > 0) {
      rhrDelta = (todayRhr - baselineRhr) / baselineRhr * 100;
      // Lower-than-baseline RHR → better recovery, so invert the sign.
      rhrComponent = (50 - rhrDelta * 3).clamp(0, 100);
    }

    final blended = hrvComponent * 0.40 + rhrComponent * 0.30 + sleepPerformanceScore * 0.30;
    return RecoveryScore(
      percent: blended.round().clamp(0, 100),
      hrvDeltaFromBaselinePercent: hrvDelta,
      rhrDeltaFromBaselinePercent: rhrDelta,
    );
  }
}

/// Biological Age — a novelty wellness estimate blending VO2 Max, deep
/// sleep ratio, HRV, and resting HR against population norms for the
/// person's chronological age. This is NOT a validated biological-age
/// algorithm (those require longitudinal clinical/omics data); treat the
/// output strictly as a motivational estimate, and surface it to users
/// with that framing rather than as a health diagnostic.
class BiologicalAgeEstimate {
  final double estimatedAge;
  final double chronologicalAge;
  final double deltaYears; // negative = "younger than", positive = "older than"

  const BiologicalAgeEstimate({
    required this.estimatedAge,
    required this.chronologicalAge,
    required this.deltaYears,
  });

  factory BiologicalAgeEstimate.compute({
    required int chronologicalAge,
    required double? vo2Max,
    required double deepSleepRatioPercent, // deep / total sleep, 0-100
    required double? hrv,
    required double? restingHeartRate,
  }) {
    // Each factor nudges age up/down from chronological baseline using
    // rough population-average deltas. Missing inputs simply contribute 0.
    double delta = 0;

    if (vo2Max != null) {
      // ~42 mL/kg/min treated as an "age-neutral" reference midpoint.
      delta += (42 - vo2Max) * 0.35;
    }
    if (deepSleepRatioPercent > 0) {
      // ~18% deep-sleep share treated as reference; less deep sleep ages up.
      delta += (18 - deepSleepRatioPercent) * 0.25;
    }
    if (hrv != null) {
      // ~55ms SDNN/RMSSD treated as reference; lower HRV ages up.
      delta += (55 - hrv) * 0.08;
    }
    if (restingHeartRate != null) {
      // ~60bpm treated as reference; higher RHR ages up.
      delta += (restingHeartRate - 60) * 0.15;
    }

    // Clamp the swing so a single missing/extreme input can't produce an
    // absurd result — cap at ±15 years from chronological age.
    final clampedDelta = delta.clamp(-15, 15);
    final estimated = chronologicalAge + clampedDelta;

    return BiologicalAgeEstimate(
      estimatedAge: estimated,
      chronologicalAge: chronologicalAge.toDouble(),
      deltaYears: clampedDelta,
    );
  }
}
