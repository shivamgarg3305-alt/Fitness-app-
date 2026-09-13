import 'package:flutter/material.dart';
import '../models/manual_sleep_session.dart';
import '../services/health_service.dart';
import '../services/sound_detection_service.dart';
import '../theme/app_colors.dart';

enum _TrackingPhase {
  checkingActiveSession, // reading SharedPreferences on screen load
  idle, // no session running — show "Start Sleep"
  active, // session running — show the pulsing ring + hold-to-wake
  stopping, // hold completed, stopManualSession() in flight
}

/// Active Tracking screen — the One-Tap manual sleep tracker.
///
/// - Pure #000000 background for OLED night optimization.
/// - On load, checks [HealthService.getActiveManualSession] in case a
///   session was already started (e.g. app was backgrounded/relaunched)
///   so the ring resumes from the real start time instead of restarting.
/// - Tapping the idle button calls [HealthService.startManualSession]
///   AND starts [SoundDetectionService] for the same session.
/// - "Hold to Wake Up" for [holdDuration] stops both
///   [HealthService.stopManualSession] and [SoundDetectionService],
///   attaches the captured sound log to the completed session's report,
///   and reports the [ManualSleepSession] via [onSessionEnded].
class ActiveTrackingScreen extends StatefulWidget {
  final bool isSmartAlarmSet;
  final bool enableSoundDetection;
  final Duration holdDuration;
  final void Function(ManualSleepSession session)? onSessionEnded;

  const ActiveTrackingScreen({
    super.key,
    this.isSmartAlarmSet = true,
    this.enableSoundDetection = true,
    this.holdDuration = const Duration(seconds: 2),
    this.onSessionEnded,
  });

  @override
  State<ActiveTrackingScreen> createState() => _ActiveTrackingScreenState();
}

class _ActiveTrackingScreenState extends State<ActiveTrackingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _holdController;

  _TrackingPhase _phase = _TrackingPhase.checkingActiveSession;
  DateTime? _sessionStart;
  bool _holdCompleted = false;
  bool _micActive = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _holdController = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_holdCompleted) {
          _holdCompleted = true;
          _stopSession();
        }
      });

    _checkForActiveSession();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  Future<void> _checkForActiveSession() async {
    final active = await HealthService.instance.getActiveManualSession();
    if (!mounted) return;
    setState(() {
      if (active != null) {
        _sessionStart = active.start;
        _phase = _TrackingPhase.active;
        // Audio capture is in-memory and can't survive a process
        // relaunch, so a resumed session (app was killed and reopened)
        // shows the mic as inactive rather than falsely claiming it's
        // still recording — only the manual-session timestamp persists.
        _micActive = false;
      } else {
        _phase = _TrackingPhase.idle;
      }
    });
  }

  Future<void> _startSession() async {
    setState(() => _errorMessage = null);
    try {
      final session = await HealthService.instance.startManualSession();

      bool micActive = false;
      if (widget.enableSoundDetection) {
        micActive = await SoundDetectionService.instance.start(sessionStart: session.start);
      }

      if (!mounted) return;
      setState(() {
        _sessionStart = session.start;
        _phase = _TrackingPhase.active;
        _micActive = micActive;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Couldn\u2019t start tracking: $e');
    }
  }

  Future<void> _stopSession() async {
    setState(() => _phase = _TrackingPhase.stopping);
    try {
      // Stop sound capture first so its persisted log's timestamp window
      // matches the session as closely as possible, then close out the
      // manual session itself.
      if (_micActive) {
        await SoundDetectionService.instance.stop();
      }
      final completed = await HealthService.instance.stopManualSession();
      if (!mounted) return;
      if (completed != null) {
        widget.onSessionEnded?.call(completed);
      }
      setState(() {
        _phase = _TrackingPhase.idle;
        _sessionStart = null;
        _micActive = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Couldn\u2019t end the session cleanly: $e';
        _phase = _TrackingPhase.active; // let them retry the hold
      });
    } finally {
      _holdCompleted = false;
      _holdController.reset();
    }
  }

  void _onHoldStart(LongPressStartDetails details) {
    if (_phase != _TrackingPhase.active) return;
    _holdCompleted = false;
    _holdController.forward(from: 0);
  }

  void _onHoldEnd(LongPressEndDetails details) {
    if (!_holdCompleted && _phase == _TrackingPhase.active) {
      _holdController.reverse();
    }
  }

  String _formattedTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute|$period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pureBlack, // OLED: true black, not a dark gradient
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              switch (_phase) {
                _TrackingPhase.checkingActiveSession => ' ',
                _TrackingPhase.idle => 'Ready to Track Sleep',
                _TrackingPhase.active => 'Sleep Session Active',
                _TrackingPhase.stopping => 'Ending Session…',
              },
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFF2745A), fontSize: 12),
                ),
              ),
            ],
            const Spacer(),
            _CenterContent(
              phase: _phase,
              pulseController: _pulseController,
              sessionStart: _sessionStart,
              formattedTime: _formattedTime,
              onStartTap: _startSession,
            ),
            const Spacer(),
            if (_phase == _TrackingPhase.active || _phase == _TrackingPhase.stopping) ...[
              _IndicatorRow(
                isMicActive: _micActive,
                isSmartAlarmSet: widget.isSmartAlarmSet,
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _HoldToWakeBar(
                  controller: _holdController,
                  enabled: _phase == _TrackingPhase.active,
                  onHoldStart: _onHoldStart,
                  onHoldEnd: _onHoldEnd,
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Swaps between the loading spinner, the idle "Start Sleep" button, and
/// the active pulsing session ring, depending on [phase].
class _CenterContent extends StatelessWidget {
  final _TrackingPhase phase;
  final AnimationController pulseController;
  final DateTime? sessionStart;
  final String Function(DateTime) formattedTime;
  final VoidCallback onStartTap;

  const _CenterContent({
    required this.phase,
    required this.pulseController,
    required this.sessionStart,
    required this.formattedTime,
    required this.onStartTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case _TrackingPhase.checkingActiveSession:
        return const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 3),
        );

      case _TrackingPhase.idle:
        return GestureDetector(
          onTap: onStartTap,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.navyBase,
              border: Border.all(color: AppColors.cyan.withOpacity(0.5), width: 2),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bedtime_rounded, color: AppColors.cyan, size: 36),
                SizedBox(height: 12),
                Text(
                  'Tap to Start\nSleep Tracking',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );

      case _TrackingPhase.active:
      case _TrackingPhase.stopping:
        final parts = sessionStart != null ? formattedTime(sessionStart!).split('|') : ['--', ''];
        return _PulsingSessionRing(
          controller: pulseController,
          timeMain: parts[0],
          timePeriod: parts.length > 1 ? parts[1] : '',
          dimmed: phase == _TrackingPhase.stopping,
        );
    }
  }
}

class _PulsingSessionRing extends StatelessWidget {
  final AnimationController controller;
  final String timeMain;
  final String timePeriod;
  final bool dimmed;

  const _PulsingSessionRing({
    required this.controller,
    required this.timeMain,
    required this.timePeriod,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final double glow = (0.25 + (controller.value * 0.25)) * (dimmed ? 0.4 : 1.0);
        final double scale = 1.0 + (controller.value * 0.03);

        return Opacity(
          opacity: dimmed ? 0.6 : 1.0,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.sessionButtonGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withOpacity(glow),
                    blurRadius: 70,
                    spreadRadius: 12,
                  ),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.9), width: 2),
              ),
              child: Center(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: timeMain,
                        style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: timePeriod,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IndicatorRow extends StatelessWidget {
  final bool isMicActive;
  final bool isSmartAlarmSet;

  const _IndicatorRow({required this.isMicActive, required this.isSmartAlarmSet});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isMicActive) _DimIndicator(icon: Icons.mic_rounded, label: 'Microphone\nActive', color: AppColors.micGreen),
        if (isMicActive && isSmartAlarmSet) const SizedBox(width: 36),
        if (isSmartAlarmSet) _DimIndicator(icon: Icons.alarm_rounded, label: 'Smart Alarm\nSet', color: AppColors.textSecondary),
      ],
    );
  }
}

class _DimIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DimIndicator({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12)),
          child: Icon(icon, color: color.withOpacity(0.85), size: 16),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color.withOpacity(0.7), fontSize: 11, height: 1.2),
        ),
      ],
    );
  }
}

/// "Hold to Wake Up" gesture bar. Holding fills the pill from left to
/// right over [controller]'s duration; releasing early reverses the fill.
/// Disabled (dimmed, non-interactive) once [enabled] is false — i.e.
/// while the stop request is already in flight.
class _HoldToWakeBar extends StatelessWidget {
  final AnimationController controller;
  final bool enabled;
  final void Function(LongPressStartDetails) onHoldStart;
  final void Function(LongPressEndDetails) onHoldEnd;

  const _HoldToWakeBar({
    required this.controller,
    required this.enabled,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onLongPressStart: enabled ? onHoldStart : null,
        onLongPressEnd: enabled ? onHoldEnd : null,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  return FractionallySizedBox(
                    widthFactor: controller.value.clamp(0.0, 1.0),
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  );
                },
              ),
              AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  return Padding(
                    padding: EdgeInsets.only(left: 4 + (controller.value.clamp(0.0, 1.0) * 200)),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Text(
                        '${controller.duration!.inSeconds}s',
                        style: const TextStyle(color: AppColors.navyDeep, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  );
                },
              ),
              Center(
                child: Text(
                  enabled ? 'Hold to Wake Up' : 'Ending…',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
