import 'package:flutter/material.dart';
import '../models/health_snapshot.dart';
import '../models/sleep_metrics.dart';
import '../services/daily_metrics_history_service.dart';
import '../services/health_service.dart';
import '../services/sound_detection_service.dart';
import '../theme/app_colors.dart';
import '../widgets/async_state_body.dart';
import '../widgets/circular_gauge.dart';
import '../widgets/hypnogram_chart.dart';
import '../widgets/sound_detection_report.dart';
import '../widgets/stat_card.dart';

class _AnalysisData {
  final HealthSnapshot snapshot;
  final SleepQualityMetrics metrics;
  final List<SoundEvent> soundEvents;
  const _AnalysisData({required this.snapshot, required this.metrics, required this.soundEvents});
}

/// Full Sleep Stage & Analysis screen — live-wired to HealthService.
/// Records the day's Sleep Performance score into DailyMetricsHistoryService
/// on every successful load, which is what feeds the Menstrual Insights
/// phase-vs-sleep-quality correlation.
///
/// Sound events now load from [SoundDetectionService] (the most recently
/// completed session's log) unless [soundEventsOverride] is supplied —
/// that override exists for testing/previewing, not normal use. If no
/// session has ever captured any sound events, this still shows an
/// honest empty state rather than fabricated log entries.
class SleepAnalysisScreen extends StatefulWidget {
  final List<DateTime>? recentBedtimes;
  final List<SoundEvent>? soundEventsOverride;
  final Duration targetSleep;

  const SleepAnalysisScreen({
    super.key,
    this.recentBedtimes,
    this.soundEventsOverride,
    this.targetSleep = const Duration(hours: 8),
  });

  @override
  State<SleepAnalysisScreen> createState() => _SleepAnalysisScreenState();
}

class _SleepAnalysisScreenState extends State<SleepAnalysisScreen> {
  AsyncSnapshotState<_AnalysisData> _state = AsyncSnapshotState.loading();
  int _tabIndex = 0;
  static const List<String> _tabs = ['Sleep', 'Month', 'Light', 'Sleep'];

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
      final snapshot = await HealthService.instance.fetchLast24HoursData();
      final metrics = SleepQualityMetrics.fromSnapshot(
        snapshot,
        targetSleep: widget.targetSleep,
        recentBedtimes: widget.recentBedtimes,
      );

      await DailyMetricsHistoryService.instance.recordToday(sleepPerformanceScore: metrics.performanceScore);

      final soundEvents = widget.soundEventsOverride ?? await SoundDetectionService.instance.loadMostRecentSessionEvents();

      if (!mounted) return;
      setState(() => _state = AsyncSnapshotState.ready(
            _AnalysisData(snapshot: snapshot, metrics: metrics, soundEvents: soundEvents),
          ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = AsyncSnapshotState.error(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.dashboardBackground),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(),
              Expanded(
                child: AsyncStateBody<_AnalysisData>(
                  state: _state,
                  onRetry: _load,
                  loadingLabel: 'Analyzing last night\u2019s sleep\u2026',
                  builder: (context, data) {
                    final segments = data.snapshot.toSleepStageSegments();
                    return RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.cyan,
                      backgroundColor: AppColors.purpleCard,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SegmentedTabs(tabs: _tabs, selectedIndex: _tabIndex, onSelected: (i) => setState(() => _tabIndex = i)),
                            const SizedBox(height: 24),
                            Center(
                              child: CircularGauge(
                                value: data.metrics.performanceScore.toDouble(),
                                maxValue: 100,
                                topLabel: 'Sleep Performance',
                                centerValueText: '${data.metrics.performanceScore}%',
                                gradientColors: const [AppColors.violet, AppColors.cyan],
                              ),
                            ),
                            const SizedBox(height: 24),
                            _StageBreakdownCard(metrics: data.metrics),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: AppColors.cardGradient,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.06)),
                              ),
                              child: segments.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 24),
                                      child: Text(
                                        'No sleep stage data for the last 24 hours yet.',
                                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : HypnogramChart(segments: segments),
                            ),
                            const SizedBox(height: 18),
                            _HoursVsNeededCard(metrics: data.metrics),
                            const SizedBox(height: 18),
                            _QualityMetricsGrid(metrics: data.metrics),
                            const SizedBox(height: 18),
                            if (data.soundEvents.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  gradient: AppColors.cardGradient,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                                ),
                                child: const Text(
                                  'Sound Detection Report\n\nNo sound events logged for this session.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                                ),
                              )
                            else
                              SoundDetectionReport(events: data.soundEvents),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageBreakdownCard extends StatelessWidget {
  final SleepQualityMetrics metrics;
  const _StageBreakdownCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final rows = [
      (SleepStage.deep, 'Deep Sleep'),
      (SleepStage.rem, 'REM Sleep'),
      (SleepStage.light, 'Light Sleep'),
      (SleepStage.awake, 'Awake Time'),
    ];

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
          const Text('Sleep Stage Breakdown', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          for (final (stage, label) in rows) _StageRow(stage: stage, label: label, metrics: metrics),
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  final SleepStage stage;
  final String label;
  final SleepQualityMetrics metrics;

  const _StageRow({required this.stage, required this.label, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final duration = metrics.stageDurations[stage] ?? Duration.zero;
    final percent = metrics.stagePercent(stage);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: stage.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              const Spacer(),
              Text('${hours}h ${minutes}m', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 8),
              Text('${percent.toStringAsFixed(0)}%', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0, 1),
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(stage.color),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoursVsNeededCard extends StatelessWidget {
  final SleepQualityMetrics metrics;
  const _HoursVsNeededCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final actualH = metrics.totalSleep.inMinutes / 60.0;
    final targetH = metrics.targetSleep.inMinutes / 60.0;
    final ratio = (actualH / targetH).clamp(0.0, 1.3);

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
              const Text('Hours vs. Needed', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${actualH.toStringAsFixed(1)}h / ${targetH.toStringAsFixed(1)}h', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio > 1 ? 1 : ratio,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(ratio >= 1 ? AppColors.micGreen : AppColors.cyan),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ratio >= 1 ? 'Target met \u2014 nice.' : '${((1 - ratio) * targetH).toStringAsFixed(1)}h short of target',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _QualityMetricsGrid extends StatelessWidget {
  final SleepQualityMetrics metrics;
  const _QualityMetricsGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.5,
      children: [
        StatCard(label: 'Sleep Efficiency:', value: '${metrics.efficiencyPercent.toStringAsFixed(0)}%', icon: Icons.check_circle_outline_rounded, accent: AppColors.cyan),
        StatCard(
          label: 'Consistency:',
          value: metrics.consistencyVarianceMinutes != null ? '\u00b1${metrics.consistencyVarianceMinutes}m' : '--',
          icon: Icons.schedule_rounded,
          accent: AppColors.violet,
        ),
        StatCard(label: 'Restful:', value: '${metrics.restfulPercent.toStringAsFixed(0)}%', icon: Icons.self_improvement_rounded, accent: AppColors.cyanBright),
        StatCard(
          label: 'SpO\u2082:',
          value: metrics.avgSpo2 != null ? '${metrics.avgSpo2!.toStringAsFixed(0)}%' : '--',
          icon: Icons.bloodtype_rounded,
          accent: AppColors.violet,
        ),
        StatCard(
          label: 'Resp. Rate:',
          value: metrics.avgRespiratoryRate != null ? '${metrics.avgRespiratoryRate!.toStringAsFixed(1)}/min' : '--',
          icon: Icons.air_rounded,
          accent: AppColors.cyan,
        ),
        StatCard(label: 'Restless:', value: '${metrics.restlessPercent.toStringAsFixed(0)}%', icon: Icons.warning_amber_rounded, accent: const Color(0xFFF2A65A)),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
      child: Row(
        children: [
          IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.chevron_left_rounded, color: AppColors.cyan, size: 28)),
          const Text('Back', style: TextStyle(color: AppColors.cyan, fontSize: 16)),
          const Spacer(),
          const Text('Sleep Analysis', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(onPressed: () {}, icon: const Icon(Icons.ios_share_rounded, color: AppColors.textPrimary, size: 20)),
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _SegmentedTabs({required this.tabs, required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: selected ? AppColors.cyan : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(tabs[i],
                    style: TextStyle(color: selected ? AppColors.navyDeep : AppColors.textSecondary, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
          );
        }),
      ),
    );
  }
}
