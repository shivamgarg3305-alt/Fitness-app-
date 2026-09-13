import 'dart:async';
import 'dart:convert';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sound_event.dart';
import 'foreground_service_controller.dart';
import 'sound_classifier.dart';

/// -----------------------------------------------------------------------
/// Required dependencies (pubspec.yaml):
///   record: ^5.1.2 — verify the API (AudioRecorder, RecordConfig,
///     onAmplitudeChanged) against your pinned version.
///   flutter_foreground_task: ^8.10.0 — verify TaskHandler's method
///     signatures against your pinned version; see
///     foreground_service_controller.dart for the full architecture note
///     on why capture stays on the main isolate instead of moving into
///     the task handler.
///
/// Platform setup outside this file:
///  - iOS: NSMicrophoneUsageDescription + UIBackgroundModes: audio in
///    Info.plist.
///  - Android: RECORD_AUDIO, FOREGROUND_SERVICE,
///    FOREGROUND_SERVICE_MICROPHONE, POST_NOTIFICATIONS in
///    AndroidManifest.xml.
///
/// PRIVACY: raw audio is never written to disk or transmitted anywhere.
/// This service opens a PCM stream purely so the OS keeps the microphone
/// engine active for amplitude metering, and immediately discards every
/// buffer it receives — only the derived classification (a type + rough
/// intensity + timestamp) is kept. If you swap in a real ML classifier
/// later that needs raw audio frames, that changes this guarantee — call
/// it out to users explicitly if you do.
/// -----------------------------------------------------------------------
class SoundDetectionService {
  SoundDetectionService._internal({SoundClassifier? classifier}) : _classifier = classifier ?? const HeuristicSoundClassifier();
  static final SoundDetectionService instance = SoundDetectionService._internal();

  final SoundClassifier _classifier;
  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<List<int>>? _pcmSub;

  static const _sampleInterval = Duration(milliseconds: 500);
  static const _windowSize = 20; // ~10s of samples at 500ms
  static const _eventCooldown = Duration(seconds: 45); // per event kind

  final List<double> _recentDb = [];
  final List<SoundEvent> _events = [];
  final Map<SoundEventKind, DateTime> _lastEventAt = {};
  DateTime? _sessionStart;

  static const _sessionIndexKey = 'kitty_sleep.sound_events.session_index';
  static const _sessionHistoryLimit = 60;

  /// Starts listening. Returns false (and starts nothing) if microphone
  /// permission isn't granted — callers should degrade gracefully (dim
  /// the mic indicator) rather than block sleep tracking on this.
  ///
  /// Also starts the Android foreground service (see
  /// foreground_service_controller.dart for why) so this keeps running
  /// once the screen locks. If the foreground service fails to start for
  /// any reason, capture still proceeds in the foreground — degraded,
  /// not blocked, same philosophy as the microphone-permission check.
  Future<bool> start({required DateTime sessionStart}) async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    _sessionStart = sessionStart;
    _recentDb.clear();
    _events.clear();
    _lastEventAt.clear();

    try {
      await ForegroundServiceController.requestPermissions();
      await ForegroundServiceController.startService();
    } catch (e) {
      // ignore: avoid_print
      print('SoundDetectionService.start: foreground service failed to start (continuing foreground-only): $e');
    }

    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      // Intentionally discarded — see the privacy note above. Kept
      // subscribed only so the recorder stays active for amplitude data.
      _pcmSub = stream.listen((_) {});

      _ampSub = _recorder.onAmplitudeChanged(_sampleInterval).listen(_onAmplitude);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('SoundDetectionService.start failed: $e');
      await ForegroundServiceController.stopService();
      return false;
    }
  }

  void _onAmplitude(Amplitude amp) {
    _recentDb.add(amp.current);
    if (_recentDb.length > _windowSize) {
      _recentDb.removeAt(0);
    }

    final classification = _classifier.classify(_recentDb, sampleInterval: _sampleInterval);
    if (classification == null) return;

    final now = DateTime.now();
    final lastAt = _lastEventAt[classification.kind];
    if (lastAt != null && now.difference(lastAt) < _eventCooldown) return;

    _lastEventAt[classification.kind] = now;
    _events.add(_toSoundEvent(classification, now));
  }

  SoundEvent _toSoundEvent(SoundClassification c, DateTime time) {
    final type = switch (c.kind) {
      SoundEventKind.snore => 'Snore',
      SoundEventKind.talking => 'Talking',
      SoundEventKind.ambientNoise => 'Ambient Noise',
    };
    final intensity = SoundIntensity.values[c.intensityLevel];
    final intensityLabel = switch (intensity) {
      SoundIntensity.light => 'Light',
      SoundIntensity.moderate => 'Moderate',
      SoundIntensity.loud => 'Loud',
    };
    // Ambient noise can't be attributed to a specific source (e.g. "Fan")
    // from amplitude alone — that needs real audio classification, which
    // this heuristic isn't. Label it by intensity like everything else
    // rather than guessing a source.
    return SoundEvent(type: type, detail: '($intensityLabel)', timestamp: time, intensity: intensity);
  }

  /// Stops listening, persists the session's events, and returns them.
  Future<List<SoundEvent>> stop() async {
    await _ampSub?.cancel();
    await _pcmSub?.cancel();
    _ampSub = null;
    _pcmSub = null;

    try {
      await _recorder.stop();
    } catch (e) {
      // ignore: avoid_print
      print('SoundDetectionService.stop (recorder.stop) failed: $e');
    }

    try {
      await ForegroundServiceController.stopService();
    } catch (e) {
      // ignore: avoid_print
      print('SoundDetectionService.stop: foreground service stop failed: $e');
    }

    final events = List<SoundEvent>.unmodifiable(_events);
    if (_sessionStart != null) {
      await _persist(_sessionStart!, events);
    }

    _recentDb.clear();
    _events.clear();
    _lastEventAt.clear();
    _sessionStart = null;
    return events;
  }

  /// Cancels an in-progress capture without saving anything — e.g. the
  /// user discarded the sleep session it belonged to.
  Future<void> discard() async {
    await _ampSub?.cancel();
    await _pcmSub?.cancel();
    _ampSub = null;
    _pcmSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await ForegroundServiceController.stopService();
    } catch (_) {}
    _recentDb.clear();
    _events.clear();
    _lastEventAt.clear();
    _sessionStart = null;
  }

  String _keyFor(DateTime sessionStart) => 'kitty_sleep.sound_events.${sessionStart.millisecondsSinceEpoch}';

  Future<void> _persist(DateTime sessionStart, List<SoundEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(sessionStart), jsonEncode(events.map((e) => e.toJson()).toList()));

    final index = prefs.getStringList(_sessionIndexKey) ?? <String>[];
    final key = sessionStart.millisecondsSinceEpoch.toString();
    index.remove(key); // avoid duplicates if re-persisted
    index.insert(0, key); // most-recent-first
    final trimmed = index.length > _sessionHistoryLimit ? index.sublist(0, _sessionHistoryLimit) : index;
    await prefs.setStringList(_sessionIndexKey, trimmed);
  }

  Future<List<SoundEvent>> loadEventsForSession(DateTime sessionStart) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(sessionStart));
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => SoundEvent.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Loads events for the most recently completed session, if any.
  Future<List<SoundEvent>> loadMostRecentSessionEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_sessionIndexKey) ?? const [];
    if (index.isEmpty) return const [];
    final raw = prefs.getString('kitty_sleep.sound_events.${index.first}');
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => SoundEvent.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> dispose() async {
    await _ampSub?.cancel();
    await _pcmSub?.cancel();
    await _recorder.dispose();
  }
}
