import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/reminders.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Live notifications: listens for new rows while the app runs and rings the phone.
class Notifs {
  static final unread = ValueNotifier<int>(0);
  static RealtimeChannel? _channel;
  static Timer? _poll;
  static int _lastId = 0;

  static Future<void> start() async {
    stop();
    await refresh(silent: true);
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    try {
      _channel = supa
          .channel('notifications-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
            callback: (payload) => _onNew(payload.newRecord),
          )
          .subscribe();
    } catch (_) {/* fall back to polling */}
    // Safety net when live updates are unavailable.
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => refresh());
  }

  static void stop() {
    _poll?.cancel();
    _poll = null;
    final c = _channel;
    _channel = null;
    if (c != null) supa.removeChannel(c);
    unread.value = 0;
    _lastId = 0;
  }

  static void _onNew(Map<String, dynamic> row) {
    final id = (row['id'] as num?)?.toInt() ?? 0;
    if (id <= _lastId) return;
    _lastId = id;
    unread.value = unread.value + 1;
    Reminders.showNow(id, '${row['title'] ?? ''}', '${row['body'] ?? ''}');
  }

  /// Reloads the unread count; rings for anything newer than what we already showed.
  static Future<List<Map<String, dynamic>>> refresh({bool silent = false}) async {
    try {
      final r = Map<String, dynamic>.from(await rpc('my_notifications', {'p_limit': 60}) as Map);
      final items = (r['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      unread.value = (r['unread'] as num?)?.toInt() ?? 0;
      final newest = items.isEmpty ? 0 : (items.first['id'] as num).toInt();
      if (!silent && _lastId > 0) {
        for (final n in items.reversed) {
          final id = (n['id'] as num).toInt();
          if (id > _lastId && n['read'] != true) Reminders.showNow(id, '${n['title']}', '${n['body'] ?? ''}');
        }
      }
      if (newest > _lastId) _lastId = newest;
      return items;
    } catch (_) {
      return const [];
    }
  }
}

/// Bell with the unread count; opens the notifications list.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Notifs.unread,
      builder: (context, n, _) => IconButton(
        tooltip: tr('الإشعارات', 'Notifications'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        icon: Badge(
          isLabelVisible: n > 0,
          label: Text(n > 99 ? '99+' : '$n'),
          child: Icon(Icons.notifications_rounded, color: color, size: 28),
        ),
      ),
    );
  }
}

(IconData, Color) _kindLook(String? k) => switch (k) {
      'booking' => (Icons.event_available_rounded, Tone.blue),
      'prescription' => (Icons.receipt_long_rounded, Tone.purple),
      'followup' => (Icons.event_repeat_rounded, Tone.teal),
      'medication' || 'med_review' => (Icons.medication_rounded, Tone.green),
      'chat' => (Icons.chat_rounded, Tone.sky),
      'queue' => (Icons.campaign_rounded, Tone.orange),
      'review' => (Icons.star_rounded, Tone.amber),
      'surgery' => (Icons.local_hospital_rounded, Tone.red),
      'stock' => (Icons.inventory_2_rounded, Tone.red),
      'join' => (Icons.person_add_rounded, Tone.indigo),
      _ => (Icons.notifications_rounded, Tone.indigo),
    };

String _ago(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return tr('دلوقتي', 'now');
  if (m < 60) return tr('من $m دقيقة', '${m}m ago');
  if (m < 1440) return tr('من ${m ~/ 60} ساعة', '${m ~/ 60}h ago');
  return formatDate(iso);
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _key = 0;

  @override
  void dispose() {
    rpc('mark_notifications_read').then((_) => Notifs.unread.value = 0).catchError((_) => 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('الإشعارات', 'Notifications'))),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => Notifs.refresh(silent: true),
        builder: (context, items, reload) => RefreshList(onRefresh: reload, children: [
          if (items.isEmpty)
            EmptyView(icon: Icons.notifications_none_rounded, title: tr('مفيش إشعارات', 'No notifications'),
                subtitle: tr('هنا هتلاقي تأكيد الحجوزات والرسائل والروشتات وأي جديد.', 'Bookings, messages and updates show here.')),
          for (final n in items)
            Card(
              color: n['read'] == true ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon3D(_kindLook(n['kind'] as String?).$1, color: _kindLook(n['kind'] as String?).$2, size: 42),
                title: Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text([n['body'], _ago(n['created_at'] as String?)].whereType<String>().where((s) => s.isNotEmpty).join('\n')),
                isThreeLine: (n['body'] as String?)?.isNotEmpty == true,
              ),
            ),
        ]),
      ),
    );
  }
}
