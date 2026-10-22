import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'l10n.dart';

/// Medicine reminders as notifications on the patient's own phone (free, work offline).
/// The whole schedule is rebuilt from the medicines list every time it is loaded,
/// so new prescriptions from the doctor are picked up when the patient opens the app.
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _maxNotifications = 400; // stay well under Android's alarm limit

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Reminders init failed: $e');
    }
  }

  /// Asks Android for notification + exact alarm permission. Returns false when notifications are refused.
  static Future<bool> askPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final ok = await android.requestNotificationsPermission() ?? true;
    try {
      await android.requestExactAlarmsPermission();
    } catch (_) {/* older Android: not needed */}
    return ok;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'med_reminders',
      'مواعيد الدوا',
      channelDescription: 'تذكير بمواعيد تناول العلاج',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
  );

  /// Dose times of one medicine as minutes after midnight (e.g. every 8h from 08:00 → 08:00, 16:00, 00:00).
  static List<int> doseMinutes(String firstTime, int everyHours) {
    final parts = firstTime.split(':');
    final start = (int.tryParse(parts[0]) ?? 9) * 60 + (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    final n = (24 / everyHours).floor().clamp(1, 6);
    final list = [for (var k = 0; k < n; k++) (start + k * everyHours * 60) % (24 * 60)]..sort();
    return list;
  }

  static String formatMinutes(int m) {
    final h = m ~/ 60, min = (m % 60).toString().padLeft(2, '0');
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$min ${h < 12 ? tr('ص', 'AM') : tr('م', 'PM')}';
  }

  static List<Map<String, dynamic>>? _meds;
  static List<Map<String, dynamic>>? _followups;

  /// Updates the medicines list and rebuilds all reminders.
  static Future<void> sync(List<Map<String, dynamic>> meds) async {
    _meds = meds;
    await _rebuild();
  }

  /// Updates the doctor's follow-up appointments and rebuilds all reminders.
  static Future<void> syncFollowups(List<Map<String, dynamic>> followups) async {
    _followups = followups;
    await _rebuild();
  }

  static Future<void> _chain = Future.value();

  /// Rebuilds one at a time, so two quick updates never interleave.
  static Future<void> _rebuild() => _chain = _chain.then((_) => _doRebuild()).catchError((Object e) {
        debugPrint('Reminders rebuild failed: $e');
      });

  static Future<void> _doRebuild() async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
    await _scheduleFollowups();
    await _scheduleMeds(_meds ?? const []);
  }

  /// A reminder the day before (8 PM) and 2 hours before each upcoming follow-up.
  static Future<void> _scheduleFollowups() async {
    final now = tz.TZDateTime.now(tz.local);
    var id = 5000;
    for (final f in _followups ?? const <Map<String, dynamic>>[]) {
      if (f['status'] != 'scheduled') continue;
      final at = DateTime.tryParse('${f['scheduled_at']}');
      if (at == null) continue;
      final when = tz.TZDateTime.from(at, tz.local);
      if (!when.isAfter(now)) continue;
      final doctor = '${tr('د.', 'Dr.')} ${f['doctor_name'] ?? ''}';
      final time = formatMinutes(when.hour * 60 + when.minute);
      final dayBefore = tz.TZDateTime(tz.local, when.year, when.month, when.day - 1, 20);
      final title = tr('ميعاد متابعة 📅', 'Follow-up appointment 📅');
      if (dayBefore.isAfter(now) && id < 5400) {
        await _schedule(id++, title, '${tr('بكرة الساعة', 'Tomorrow at')} $time — ${f['title']} ($doctor)', dayBefore,
            repeatDaily: false);
      }
      final before = when.subtract(const Duration(hours: 2));
      if (before.isAfter(now) && id < 5400) {
        await _schedule(id++, title, '${tr('النهارده الساعة', 'Today at')} $time — ${f['title']} ($doctor)', before,
            repeatDaily: false);
      }
    }
  }

  static Future<void> _scheduleMeds(List<Map<String, dynamic>> meds) async {
    final now = tz.TZDateTime.now(tz.local);
    final today = tz.TZDateTime(tz.local, now.year, now.month, now.day);
    var id = 1;

    for (final m in meds) {
      if (m['is_active'] != true || m['reminders_on'] != true) continue;
      final end = DateTime.tryParse('${m['end_date'] ?? ''}');
      final start = DateTime.tryParse('${m['start_date'] ?? ''}') ?? today;
      if (end != null && DateTime(end.year, end.month, end.day).isBefore(today)) continue;
      final minutes = doseMinutes('${m['first_time'] ?? '09:00'}', (m['every_hours'] as num?)?.toInt() ?? 24);
      final title = tr('وقت دواك 💊', 'Medicine time 💊');
      final body = [m['name'], m['dose'], m['instructions']].whereType<String>().where((s) => s.isNotEmpty).join(' — ');
      final firstDay = start.isAfter(today) ? tz.TZDateTime(tz.local, start.year, start.month, start.day) : today;

      final shortCourse = end != null && end.difference(today).inDays <= 14;
      if (shortCourse) {
        // One notification per dose until the last day.
        for (var day = firstDay; !day.isAfter(tz.TZDateTime(tz.local, end.year, end.month, end.day));
            day = day.add(const Duration(days: 1))) {
          for (final mm in minutes) {
            final at = day.add(Duration(minutes: mm));
            if (!at.isAfter(now) || id > _maxNotifications) continue;
            await _schedule(id++, title, body, at, repeatDaily: false);
          }
        }
      } else {
        // Daily repeating notifications at each dose time.
        for (final mm in minutes) {
          var at = firstDay.add(Duration(minutes: mm));
          while (!at.isAfter(now)) {
            at = at.add(const Duration(days: 1));
          }
          if (id > _maxNotifications) break;
          await _schedule(id++, title, body, at, repeatDaily: true);
        }
      }
    }
  }

  static Future<void> _schedule(int id, String title, String body, tz.TZDateTime at, {required bool repeatDaily}) async {
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: at,
          notificationDetails: _details,
          androidScheduleMode: mode,
          matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
        );
    try {
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      // Exact alarms not allowed on this phone: fall back to inexact (may arrive a few minutes late).
      try {
        await go(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e) {
        debugPrint('Could not schedule reminder: $e');
      }
    }
  }
}
