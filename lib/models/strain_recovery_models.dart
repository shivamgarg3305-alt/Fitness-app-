import 'package:health/health.dart';

/// Heart-rate training zones, computed from an estimated max HR.
///
/// Zone 1: 50–60%
/// Zone 2: 60–70%
/// Zone 3: 70–80%
/// Zone 4: 80–90%
/// Zone 5: 90%+
enum HrZone {
  zone1,
  zone2,
  zone3,
  zone4,
  zone5,
}

class HeartRateZoneBreakdown {
  final Map<HrZone, Duration> durations;
  final int? maxHeartRateBpm;

  const HeartRateZoneBreakdown({
    required this.durations,
    required this.maxHeartRateBpm,
  });

  Duration get totalActive =>
      durations.values.fold(Duration.zero, (a, b) => a + b);

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

    final durations = {
      for (final z in HrZone.values) z: Duration.zero,
    };

    final sorted = [...points]
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

    for (int i = 0; i < sorted.length - 1; i++) {
      final value = sorted[i].value;

      if (value is! NumericHealthValue) continue;

      final bpm = value.numericValue.toDouble();

      final segmentDuration =
          sorted[i + 1].dateFrom.difference(sorted[i].dateFrom);

      // Ignore invalid or excessively large gaps between readings.
      if (segmentDuration.isNegative ||
          segmentDuration > const Duration(minutes: 10)) {
        continue;
      }

      final zone = _zoneFor(bpm, bounds);

      if (zone != null) {
        durations[zone] = durations[zone]! + segmentDuration;
      }
    }

    return HeartRateZoneBreakdown(
      durations: durations,
      maxHeartRateBpm: maxHr.round(),
    );
  }

  static HrZone? _zoneFor(
    double bpm,
    Map<HrZone, double> bounds,
  ) {
    if (bpm < bounds[HrZone.zone1]!) {
      return null;
    }

    if (bpm < bounds[HrZone.zone2]!) {
      return HrZone.zone1;
    }

    if (bpm < bounds[HrZone.zone3]!) {
      return HrZone.zone2;
    }

    if (bpm < bounds[HrZone.zone4]!) {
      return HrZone.zone3;
    }

    if (bpm < bounds[HrZone.zone5]!) {
      return HrZone.zone4;
    }

    return HrZone.zone5;
  }
}

/// Strain — a 0–21 heuristic scale.
///
/// This is our own approximation combining time-in-zone,
/// weighted by intensity, plus a step-volume contribution.
/// It is not WHOOP's proprietary formula.
class StrainScore {
  final double value;
  final HeartRateZoneBreakdown zones;

  const StrainScore({
    required this.value,
    required this.zones,
  });

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
      points += duration.inMinutes * zoneWeights[zone]!;
    });

    // Step volume contributes a smaller, log-dampened amount.
    final stepContribution = steps <= 0
        ? 0.0
        : (steps / 1000).clamp(0, 15).toDouble();

    final raw = points / 40 + stepContribution * 0.3;

    return StrainScore(
      value: raw.clamp(0, 21).toDouble(),
      zones: zones,
    );
  }
}

/// Recovery — 0–100%.
///
/// Blended from HRV vs. baseline, RHR vs. baseline,
/// and last night's sleep performance.
///
/// This is a heuristic and is not WHOOP's algorithm.
class RecoveryScore {
  final int percent;
  final double? hrvDeltaFromBaselinePercent;
  final double? rhrDeltaFromBaselinePercent;

  const RecoveryScore({
    required this.percent,
    required this.hrvDeltaFromBaselinePercent,
    required this.rhrDeltaFromBaselinePercent,
  });

  /// [baselineHrv] and [baselineRhr] should be rolling averages
  /// maintained by the caller.
  ///
  /// Pass null if a baseline has not yet been established.
  factory RecoveryScore.compute({
    required double? todayHrv,
    required double? baselineHrv,
    required double? todayRhr,
    required double? baselineRhr,
    required int sleepPerformanceScore,
  }) {
    double? hrvDelta;
    double? rhrDelta;

    double hrvComponent = sleepPerformanceScore.toDouble();
    double rhrComponent = sleepPerformanceScore.toDouble();

    if (todayHrv != null &&
        baselineHrv != null &&
        baselineHrv > 0) {
      hrvDelta =
          (todayHrv - baselineHrv) / baselineHrv * 100;

      // Higher-than-baseline HRV → better recovery.
      hrvComponent =
          (50 + hrvDelta * 2).clamp(0, 100).toDouble();
    }

    if (todayRhr != null &&
        baselineRhr != null &&
        baselineRhr > 0) {
      rhrDelta =
          (todayRhr - baselineRhr) / baselineRhr * 100;

      // Lower-than-baseline RHR → better recovery.
      rhrComponent =
          (50 - rhrDelta * 3).clamp(0, 100).toDouble();
    }

    final blended =
        hrvComponent * 0.40 +
        rhrComponent * 0.30 +
        sleepPerformanceScore * 0.30;

    return RecoveryScore(
      percent: blended.round().clamp(0, 100),
      hrvDeltaFromBaselinePercent: hrvDelta,
      rhrDeltaFromBaselinePercent: rhrDelta,
    );
  }
}

/// Biological Age.
///
/// A novelty wellness estimate blending VO2 Max, deep sleep ratio,
/// HRV, and resting heart rate against rough population references.
///
/// This is NOT a validated biological-age algorithm and should not
/// be treated as a medical diagnostic.
class BiologicalAgeEstimate {
  final double estimatedAge;
  final double chronologicalAge;
  final double deltaYears;

  const BiologicalAgeEstimate({
    required this.estimatedAge,
    required this.chronologicalAge,
    required this.deltaYears,
  });

  factory BiologicalAgeEstimate.compute({
    required int chronologicalAge,
    required double? vo2Max,
    required double deepSleepRatioPercent,
    required double? hrv,
    required double? restingHeartRate,
  }) {
    double delta = 0;

    if (vo2Max != null) {
      // Rough age-neutral reference.
      delta += (42 - vo2Max) * 0.35;
    }

    if (deepSleepRatioPercent > 0) {
      // Rough reference for deep-sleep share.
      delta += (18 - deepSleepRatioPercent) * 0.25;
    }

    if (hrv != null) {
      // Rough HRV reference.
      delta += (55 - hrv) * 0.08;
    }

    if (restingHeartRate != null) {
      // Rough resting-HR reference.
      delta += (restingHeartRate - 60) * 0.15;
    }

    // Limit the result to ±15 years.
    final clampedDelta =
        delta.clamp(-15, 15).toDouble();

    final estimated =
        chronologicalAge.toDouble() + clampedDelta;

    return BiologicalAgeEstimate(
      estimatedAge: estimated,
      chronologicalAge: chronologicalAge.toDouble(),
      deltaYears: clampedDelta,
    );
  }
}
