import 'dart:io' show Platform;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// -----------------------------------------------------------------------
/// ARCHITECTURE NOTE — read before changing this file.
///
/// flutter_foreground_task's TaskHandler runs in a SEPARATE background
/// isolate. Plugins that rely on platform method channels tied to the
/// main FlutterEngine — which includes `record`, the audio-capture
/// plugin SoundDetectionService uses — generally do NOT work correctly
/// if you move their calls into that background isolate; channels aren't
/// automatically available there.
///
/// So this controller does NOT run sound capture itself. Its only job is
/// to start/stop the Android foreground service (a persistent, visible
/// notification) so Android doesn't kill the app process — and therefore
/// doesn't kill the main isolate, where SoundDetectionService's `record`
/// calls keep running exactly as they already did. The TaskHandler below
/// is intentionally a near-no-op: it exists because the plugin requires
/// one, not because real work happens inside it.
///
/// On iOS this plugin's role is much thinner — iOS has no equivalent of
/// an Android foreground service. What actually keeps an iOS app alive
/// during background audio capture is UIBackgroundModes: audio PLUS an
/// active, properly-configured AVAudioSession — i.e. the fact that
/// `record` is actively recording is what iOS uses to justify continued
/// execution, not this plugin. Calling start/stop here on iOS is
/// harmless but is not the thing doing the real work on that platform.
/// -----------------------------------------------------------------------
class ForegroundServiceController {
  ForegroundServiceController._();

  static bool _initialized = false;

  /// Call once at app startup, after WidgetsFlutterBinding.ensureInitialized().
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kitty_sleep_tracking',
        channelName: 'Sleep Tracking',
        channelDescription: 'Shown while Kitty Sleep is listening for sound events overnight.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false, // no user-facing role on iOS; see note above
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000), // heartbeat only — see TaskHandler below
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Requests the Android 13+ notification permission and a battery-
  /// optimization exemption prompt. Best-effort: sleep tracking still
  /// proceeds if the user declines either, since the alternative is
  /// blocking the whole feature on a permission most people will grant
  /// once they understand why (the ongoing notification explains it).
  static Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;
    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    final ignoringBatteryOptimizations = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!ignoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static Future<ServiceRequestResult> startService() {
    return FlutterForegroundTask.startService(
      notificationTitle: 'Kitty Sleep is tracking',
      notificationText: 'Listening for snoring and sleep talking, entirely on your device.',
      callback: _startCallback,
    );
  }

  static Future<ServiceRequestResult> stopService() {
    return FlutterForegroundTask.stopService();
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}

/// Top-level entry point for the background isolate. `@pragma('vm:entry-point')`
/// is required — without it, release-mode tree-shaking can strip this
/// function since nothing in the main isolate appears to call it directly.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_SleepTrackingTaskHandler());
}

/// Deliberately minimal — see the architecture note above for why real
/// sound-detection work does NOT happen here.
class _SleepTrackingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Heartbeat only. If you later need the service to report liveness
    // back to the UI, use FlutterForegroundTask.sendDataToMain here.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
