import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'dart:convert';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (await NotificationService._shouldShowNotification(message)) {
    await NotificationService._showNotification(message);
  }
}

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static GlobalKey<NavigatorState>? _navKey;

  static const String _notificationPrefsKey = 'notification_preferences';

  static Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Addis_Ababa'));

    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      await _onNotificationOpened(initial);
    }
    final permissionGranted = await requestPermissions();
    if (permissionGranted) {
      try {
        final token = await _fcm.getToken();
        debugPrint("FCM Token: $token");
      } catch (_) {}
    }

    if (Platform.isIOS) {
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint("Notification tapped: ${response.payload}");
      },
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (await _shouldShowNotification(message)) {
        await _showNotification(message);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);

    await _migrateOldPreferences();
    await _rescheduleNotifications();
  }
  static void configureNavigation(GlobalKey<NavigatorState> navKey) {
    _navKey = navKey;
  }

  static Future<void> setAdmin({required bool isAdmin}) async {
    if (isAdmin) {
      await _fcm.subscribeToTopic('bin_requests_admins');
    } else {
      await _fcm.unsubscribeFromTopic('bin_requests_admins');
    }
  }

  static Future<void> _migrateOldPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final unifiedPrefs = await _getNotificationPrefs();

    if (prefs.containsKey('daily_notifications_enabled')) {
      unifiedPrefs['daily'] ??= {};
      unifiedPrefs['daily']['enabled'] =
          prefs.getBool('daily_notifications_enabled') ?? false;
      unifiedPrefs['daily']['time'] =
          prefs.getString('daily_notification_time') ?? '20:00';
      await prefs.remove('daily_notifications_enabled');
      await prefs.remove('daily_notification_time');
    }

    if (prefs.containsKey('weekly_recap_enabled')) {
      unifiedPrefs['weekly'] ??= {};
      unifiedPrefs['weekly']['enabled'] =
          prefs.getBool('weekly_recap_enabled') ?? false;
      unifiedPrefs['weekly']['day'] = prefs.getInt('weekly_recap_day') ?? 1;
      unifiedPrefs['weekly']['time'] =
          prefs.getString('weekly_recap_time') ?? '09:00';
      await prefs.remove('weekly_recap_enabled');
      await prefs.remove('weekly_recap_day');
      await prefs.remove('weekly_recap_time');
    }

    await _saveNotificationPrefs(unifiedPrefs);
  }

  static Future<void> _rescheduleNotifications() async {
    final prefs = await _getNotificationPrefs();

    if (prefs['daily']?['enabled'] == true) {
      final timeString = prefs['daily']?['time'] ?? '20:00';
      final timeParts = timeString.split(':');
      await _scheduleDailyReminder(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
    }

    if (prefs['weekly']?['enabled'] == true) {
      final day = prefs['weekly']?['day'] ?? 1;
      final timeString = prefs['weekly']?['time'] ?? '09:00';
      final timeParts = timeString.split(':');
      await _scheduleWeeklyRecap(
        day: day,
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
    }
  }

  static Future<bool> _shouldShowNotification(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'];

    if (type == null) return true;

    if (type == 'daily') {
      return await isDailyNotificationEnabled();
    } else if (type == 'weekly') {
      return await isWeeklyRecapEnabled();
    } else if (type == 'challenge') {
      final challengeId = data['challengeId'];
      if (challengeId != null) {
        return await areChallengeNotificationsEnabled(challengeId);
      }
      return false;
    }
    return true;
  }

  static Future<void> cancelScheduled(int id) async {
    await notificationsPlugin.cancel(id);
  }

  static Future<void> cancelAllScheduled() async {
    await notificationsPlugin.cancelAll();
  }

  static Future<void> _showNotification(RemoteMessage message) async {
    if (!(await areNotificationsEnabled())) return;

    const androidDetails = AndroidNotificationDetails(
      'recyai_channel',
      'Recy.AI Notifications',
      channelDescription: 'Important recycling updates',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF0F9E84),
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = const NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      notificationDetails,
      payload: message.data.toString(),
    );
  }

  static Future<void> _onNotificationOpened(RemoteMessage message) async {
    final screen = message.data['screen']?.toString();
    if (screen == 'admin_requests') {
      _navKey?.currentState?.pushNamed('/admin/requests', arguments: message.data);
      return;
    }
    // Fallback: open admin page if the notification looks like a bin request
    final looksLikeBin = (message.notification?.title ?? '').toLowerCase().contains('bin request');
    if (looksLikeBin) {
      _navKey?.currentState?.pushNamed('/admin/requests', arguments: message.data);
    }
  }

  // ========================== PERMISSION HANDLING ==========================
  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        final status = await Permission.notification.request();
        return status.isGranted;
      }
      return await _areNotificationsEnabledLegacy();
    } else if (Platform.isIOS) {
      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    }
    return false;
    }

  static Future<bool> _areNotificationsEnabledLegacy() async {
    return true;
  }

  static Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        return Permission.notification.isGranted;
      }
      return true;
    } else if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    }
    return false;
  }

  // ========================== PREFERENCE HANDLING ==========================
  static Future<Map<String, dynamic>> _getNotificationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_notificationPrefsKey);

    if (jsonString == null) {
      return {
        'daily': {'enabled': false, 'time': '20:00'},
        'weekly': {'enabled': false, 'day': 1, 'time': '09:00'},
        'challenges': {},
      };
    }

    try {
      return Map<String, dynamic>.from(json.decode(jsonString));
    } catch (_) {
      return {
        'daily': {'enabled': false, 'time': '20:00'},
        'weekly': {'enabled': false, 'day': 1, 'time': '09:00'},
        'challenges': {},
      };
    }
  }

  static Future<void> _saveNotificationPrefs(Map<String, dynamic> prefs) async {
    final sharedPrefs = await SharedPreferences.getInstance();
    await sharedPrefs.setString(_notificationPrefsKey, json.encode(prefs));
  }

  // ========================== DAILY REMINDERS ==========================
  static Future<void> enableDailyNotifications({
    required int hour,
    required int minute,
  }) async {
    final prefs = await _getNotificationPrefs();
    prefs['daily'] = {
      'enabled': true,
      'time': '$hour:$minute',
    };
    await _saveNotificationPrefs(prefs);
    await _scheduleDailyReminder(hour: hour, minute: minute);
  }

  static Future<void> disableDailyNotifications() async {
    final prefs = await _getNotificationPrefs();
    if (prefs['daily'] != null) {
      prefs['daily']['enabled'] = false;
      await _saveNotificationPrefs(prefs);
    }
    await cancelScheduled(0);
  }

  static Future<bool> isDailyNotificationEnabled() async {
    final prefs = await _getNotificationPrefs();
    return prefs['daily']?['enabled'] == true;
  }

  static Future<TimeOfDay?> getDailyNotificationTime() async {
    final prefs = await _getNotificationPrefs();
    final timeString = prefs['daily']?['time'] as String?;
    if (timeString == null) return null;
    final parts = timeString.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static Future<void> _scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminders',
      channelDescription: 'Daily recycling reminders',
      importance: Importance.max,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.zonedSchedule(
      0,
      "🔔 Daily Recycling Reminder",
      "Don't forget to log your recycling today!",
      _nextInstanceOfTime(hour, minute),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ========================== WEEKLY RECAP ==========================
  static Future<void> enableWeeklyRecap({
    required int day,
    required int hour,
    required int minute,
  }) async {
    final prefs = await _getNotificationPrefs();
    prefs['weekly'] = {
      'enabled': true,
      'day': day,
      'time': '$hour:$minute',
    };
    await _saveNotificationPrefs(prefs);
    await _scheduleWeeklyRecap(day: day, hour: hour, minute: minute);
  }

  static Future<void> disableWeeklyRecap() async {
    final prefs = await _getNotificationPrefs();
    if (prefs['weekly'] != null) {
      prefs['weekly']['enabled'] = false;
      await _saveNotificationPrefs(prefs);
    }
    await cancelScheduled(1);
  }

  static Future<bool> isWeeklyRecapEnabled() async {
    final prefs = await _getNotificationPrefs();
    return prefs['weekly']?['enabled'] == true;
  }

  static Future<Map<String, dynamic>> getWeeklyRecapSettings() async {
    final prefs = await _getNotificationPrefs();
    return {
      'enabled': prefs['weekly']?['enabled'] == true,
      'day': prefs['weekly']?['day'] ?? 1,
      'time': prefs['weekly']?['time'] ?? '09:00',
    };
  }

  static Future<void> _scheduleWeeklyRecap({
    required int day,
    required int hour,
    required int minute,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'weekly_recap',
      'Weekly Recap',
      channelDescription: 'Your weekly recycling impact summary',
      importance: Importance.max,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.zonedSchedule(
      1,
      "📝 Weekly Recycling Recap",
      "Check out your recycling impact this week!",
      _nextInstanceOfDayAndTime(day, hour, minute),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  // ========================== CHALLENGE NOTIFICATIONS ==========================
  static Future<void> enableChallengeNotifications({
    required String challengeId,
    required String challengeTitle,
    required DateTime endDate,
  }) async {
    final prefs = await _getNotificationPrefs();
    prefs['challenges'] ??= {};
    prefs['challenges'][challengeId] = {'enabled': true};
    await _saveNotificationPrefs(prefs);

    await _scheduleNewParticipantCheck(challengeId, challengeTitle);
    await _scheduleLeaderboardUpdates(challengeId, challengeTitle);
    await _scheduleChallengeEndReminder(challengeId, challengeTitle, endDate);
  }

  static Future<void> _scheduleNewParticipantCheck(
    String challengeId,
    String challengeTitle,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'challenge_participants',
      'Challenge Participants',
      channelDescription: 'Updates about new participants',
      importance: Importance.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.zonedSchedule(
      challengeId.hashCode + 1,
      "New Participants in $challengeTitle",
      "This is Good!",
      _nextInstanceOfTime(18, 59),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'challenge_$challengeId',
    );
  }

  static Future<void> _scheduleLeaderboardUpdates(
    String challengeId,
    String challengeTitle,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'challenge_leaders',
      'Challenge Leaders',
      channelDescription: 'Updates about challenge leaders',
      importance: Importance.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.zonedSchedule(
      challengeId.hashCode + 2,
      "Leader Update: $challengeTitle",
      "See who's leading the challenge now!",
      _nextInstanceOfTime(12, 0),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'challenge_$challengeId',
    );
  }

  static Future<void> _scheduleChallengeEndReminder(
    String challengeId,
    String challengeTitle,
    DateTime endDate,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'challenge_ending',
      'Challenge Ending',
      channelDescription: 'Reminders about ending challenges',
      importance: Importance.max,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.zonedSchedule(
      challengeId.hashCode + 3,
      "Challenge Ending Soon: $challengeTitle",
      "Final push to reach your goal!",
      tz.TZDateTime.from(endDate.subtract(const Duration(days: 1)), tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'challenge_$challengeId',
    );
  }

  static Future<void> disableChallengeNotifications(String challengeId) async {
    final prefs = await _getNotificationPrefs();
    if (prefs['challenges'] != null &&
        prefs['challenges'].containsKey(challengeId)) {
      prefs['challenges'][challengeId]['enabled'] = false;
      await _saveNotificationPrefs(prefs);
    }

    await notificationsPlugin.cancel(challengeId.hashCode + 1);
    await notificationsPlugin.cancel(challengeId.hashCode + 2);
    await notificationsPlugin.cancel(challengeId.hashCode + 3);
  }

  static Future<bool> areChallengeNotificationsEnabled(
    String challengeId,
  ) async {
    final prefs = await _getNotificationPrefs();
    return prefs['challenges']?[challengeId]?['enabled'] == true;
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  static tz.TZDateTime _nextInstanceOfDayAndTime(
    int day,
    int hour,
    int minute,
  ) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    int daysUntilNext = (day - now.weekday + 7) % 7;
    if (daysUntilNext == 0 && scheduledDate.isBefore(now)) {
      daysUntilNext = 7;
    }
    return scheduledDate.add(Duration(days: daysUntilNext));
  }

  static Future<void> sendTestNotification() async {
    if (!(await areNotificationsEnabled())) {
      if (!(await requestPermissions())) {
        throw Exception('Notification permission denied');
      }
    }

    const androidDetails = AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Test notifications',
      importance: Importance.max,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.show(
      12345,
      "Test Notification",
      "This is a test notification from Recy.AI",
      details,
    );
  }

  static Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  static Future<void> showDailyTimePicker(BuildContext context) async {
    final currentTime = await getDailyNotificationTime() ??
        const TimeOfDay(hour: 20, minute: 0);

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: currentTime,
    );

    if (pickedTime != null) {
      await enableDailyNotifications(
        hour: pickedTime.hour,
        minute: pickedTime.minute,
      );
    }
  }

  static Future<void> showWeeklyRecapPicker(BuildContext context) async {
    final settings = await getWeeklyRecapSettings();
    final currentDay = settings['day'] as int;
    final currentTimeParts = (settings['time'] as String).split(':');
    final currentTime = TimeOfDay(
      hour: int.parse(currentTimeParts[0]),
      minute: int.parse(currentTimeParts[1]),
    );

    final int? pickedDay = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Select Day"),
        content: DropdownButton<int>(
          value: currentDay,
          onChanged: (value) => Navigator.pop(context, value),
          items: const [
            DropdownMenuItem(value: 1, child: Text("Monday")),
            DropdownMenuItem(value: 2, child: Text("Tuesday")),
            DropdownMenuItem(value: 3, child: Text("Wednesday")),
            DropdownMenuItem(value: 4, child: Text("Thursday")),
            DropdownMenuItem(value: 5, child: Text("Friday")),
            DropdownMenuItem(value: 6, child: Text("Saturday")),
            DropdownMenuItem(value: 7, child: Text("Sunday")),
          ],
        ),
      ),
    );

    if (pickedDay == null) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: currentTime,
    );

    if (pickedTime != null) {
      await enableWeeklyRecap(
        day: pickedDay,
        hour: pickedTime.hour,
        minute: pickedTime.minute,
      );
    }
  }
}
