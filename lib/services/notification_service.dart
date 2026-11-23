import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// 基于标题+时间生成确定性 ID，避免重启后覆盖
  int _generateId(String title, DateTime when) {
    return (title.hashCode ^ when.millisecondsSinceEpoch).toUnsigned(31);
  }

  Future<void> init() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);
  }

  Future<void> scheduleReviewReminder(DateTime when, String title) async {
    if (when.isBefore(DateTime.now())) return;

    final id = _generateId('review_$title', when);
    final tzDateTime = tz.TZDateTime.from(when, tz.local);

    await _plugin.zonedSchedule(
      id,
      '复习提醒',
      '「$title」该复习了',
      tzDateTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'review_channel',
          '复习提醒',
          channelDescription: '复习卡片到期提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> scheduleTodoReminder(DateTime when, String title) async {
    if (when.isBefore(DateTime.now())) return;

    final id = _generateId('todo_$title', when);
    final tzDateTime = tz.TZDateTime.from(when, tz.local);

    await _plugin.zonedSchedule(
      id,
      '待办提醒',
      '「$title」即将到期',
      tzDateTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'todo_channel',
          '待办提醒',
          channelDescription: '待办事项截止提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
