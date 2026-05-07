import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _promptChannelId = 'prompt_jobs';
const _payloadOpenHome = 'open_home';

/// Local notifications after home-widget–style prompt runs (success / failure).
class MemJobNotifications {
  MemJobNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static void Function()? onOpenHomeTab;

  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized) return;
    _initialized = true;

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: const DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: false,
          requestAlertPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _promptChannelId,
            'Prompt jobs',
            description: 'Runs started from pinned home screen jobs',
            importance: Importance.defaultImportance,
          ));
    } else if (Platform.isIOS) {
      final iosImp = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosImp?.requestPermissions(alert: true, badge: false, sound: true);
    }
  }

  static void _onTap(NotificationResponse details) {
    if (details.payload == _payloadOpenHome) {
      onOpenHomeTab?.call();
    }
  }

  static Future<void> showPromptJobFinished({
    required String title,
    required bool ok,
    String? detail,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await ensureInitialized();

    final bodyPrefix = ok ? 'Done' : 'Failed';
    var body = bodyPrefix;
    final d = detail?.trim();
    if (d != null && d.isNotEmpty) {
      final clipped = d.length > 280 ? '${d.substring(0, 277)}…' : d;
      body += ': $clipped';
    }

    final android = AndroidNotificationDetails(
      _promptChannelId,
      'Prompt jobs',
      channelDescription: 'Runs started from pinned home screen jobs',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body),
    );
    final details = NotificationDetails(
      android: android,
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 1000000,
      title: ok ? '$title ✓' : '$title — error',
      body: body,
      notificationDetails: details,
      payload: _payloadOpenHome,
    );
  }
}
