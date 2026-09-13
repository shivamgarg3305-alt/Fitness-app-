import 'package:flutter/material.dart';
import '../models/health_snapshot.dart';
import '../models/strain_recovery_models.dart';
import '../services/health_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../widgets/async_state_body.dart';
import '../widgets/circular_gauge.dart';
import '../widgets/stat_card.dart';
import 'user_profile_screen.dart';

class _StrainData {
  final HealthSnapshot snapshot;
  final StrainScore strain;
  final bool profileConfigured;
  const _StrainData({required this.snapshot, required this.strain, required this.profileConfigured});
}

/// Strain screen — live-wired to HealthService AND UserProfileService.
/// HR-zone bounds now use the person's real age (or known max HR override)
/// instead of a hardcoded default; when no profile is set yet, this still
/// shows data (using a 30-year-old fallback so the screen isn't empty on
/// first run) but with a visible banner prompting setup, since the numbers
/// are only approximate until then.
class StrainScreen extends StatefulWidget {
  const StrainScreen({super.key});

  @override
  State<StrainScreen> createState() => _StrainScreenState();
}

class _StrainScreenState extends State<StrainScreen> {
  AsyncSnapshotState<_StrainData> _state = AsyncSnapshotState.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = AsyncSnapshotState.loading());
    final granted = await HealthService.instance.requestPermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() => _state = AsyncSnapshotState.permissionDenied());
      return;
    }
    try {
      final profile = await UserProfileService.instance.loadProfile();
      final age = profile.resolvedAge ?? 30;

      final snapshot = await HealthService.instance.fetchLast24HoursData();
      final zones = HeartRateZoneBreakdown.fromHeartRatePoints(
        snapshot.heartRatePoints,
        age: age,
        knownMaxHeartRate: profile.maxHeartRateBpm,
      );
      final strain = StrainScore.compute(zones: zones, steps: snapshot.totalSteps);
      if (!mounted) return;
      setState(() => _state = AsyncSnapshotState.ready(
            _StrainData(snapshot: snapshot, strain: strain, profileConfigured: profile.isConfigured),
          ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = AsyncSnapshotState.error(e.toString()));
    }
  }

  Future<void> _openProfile() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const UserProfileScreen()));
    if (saved == true) _load();
  }

  static String _formatDuration(Duration d) => '${d.inHours}h ${d.inMinutes % 60}m';

  static String _formatThousands(int n) {
    final digits = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      if (i != 0 && remaining % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.dashboardBackground),
        child: SafeArea(
          child: AsyncStateBody<_StrainData>(
            state: _state,
            onRetry: _load,
            loadingLabel: 'Reading strain data\u2026',
            builder: (context, data) {
              final zones = data.strain.zones;
              return RefreshIndicator(
                onRefresh: _load,
                color: AppColors.cyan,
                backgroundColor: AppColors.purpleCard,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Strain', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
                      if (!data.profileConfigured) ...[
                        const SizedBox(height: 12),
                        _ProfileNudge(onTap: _openProfile),
                      ],
                      const SizedBox(height: 24),
                      Center(
                        child: CircularGauge(
                          value: data.strain.value,
                          maxValue: 21,
                          topLabel: 'Day Strain',
                          centerValueText: data.strain.value.toStringAsFixed(1),
                          bottomLabel: 'of 21.0',
                          gradientColors: const [Color(0xFF3D7CF2), Color(0xFFF2A65A), Color(0xFFE0503A)],
                        ),
                      ),
                      const SizedBox(height: 28),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 1.5,
                        children: [
                          StatCard(label: 'Steps:', value: _formatThousands(data.snapshot.totalSteps), icon: Icons.directions_walk_rounded, accent: AppColors.cyan),
                          StatCard(label: 'Active Zones:', value: _formatDuration(zones.totalActive), icon: Icons.local_fire_department_rounded, accent: const Color(0xFFE0503A)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _ZoneBreakdownCard(zones: zones),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileNudge extends StatelessWidget {
  final VoidCallback onTap;
  const _ProfileNudge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFF2A65A).withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFF2A65A), size: 16),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Using an estimated age (30) for HR zones. Set up your profile for accurate numbers.',
                style: TextStyle(color: Color(0xFFF2A65A), fontSize: 12),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFF2A65A), size: 18),
          ],
        ),
      ),
    );
  }
}

class _ZoneBreakdownCard extends StatelessWidget {
  final HeartRateZoneBreakdown zones;
  const _ZoneBreakdownCard({required this.zones});

  static const _zoneColors = {
    HrZone.zone1: Color(0xFF3D7CF2),
    HrZone.zone2: Color(0xFF5AD8F2),
    HrZone.zone3: Color(0xFFF2D65A),
    HrZone.zone4: Color(0xFFF2A65A),
    HrZone.zone5: Color(0xFFE0503A),
  };

  static const _zoneLabels = {
    HrZone.zone1: 'Zone 1 \u00b7 50-60%',
    HrZone.zone2: 'Zone 2 \u00b7 60-70%',
    HrZone.zone3: 'Zone 3 \u00b7 70-80%',
    HrZone.zone4: 'Zone 4 \u00b7 80-90%',
    HrZone.zone5: 'Zone 5 \u00b7 90-100%',
  };

  @override
  Widget build(BuildContext context) {
    final total = zones.totalActive.inSeconds;

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
          Row(
            children: [
              const Text('Heart Rate Zones', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (zones.maxHeartRateBpm != null)
                Text('Est. Max HR ${zones.maxHeartRateBpm} bpm', style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 14),
          for (final zone in HrZone.values) ...[
            _ZoneRow(
              label: _zoneLabels[zone]!,
              color: _zoneColors[zone]!,
              duration: zones.durations[zone] ?? Duration.zero,
              percent: total == 0 ? 0 : (zones.durations[zone]!.inSeconds / total * 100),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  final String label;
  final Color color;
  final Duration duration;
  final double percent;

  const _ZoneRow({required this.label, required this.color, required this.duration, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const Spacer(),
            Text('${duration.inMinutes}m', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0, 1),
            minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
