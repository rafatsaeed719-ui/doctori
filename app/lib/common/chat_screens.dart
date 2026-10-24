import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/avatar.dart';
import '../core/live_sync.dart';
import '../core/l10n.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

String _time(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final t = '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? tr('ص', 'AM') : tr('م', 'PM')}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return t;
  return '${d.day}/${d.month} $t';
}

/// Conversations: a patient sees their clinics; staff ([staff] true) see the doctor's patients.
class ChatThreadsScreen extends StatefulWidget {
  const ChatThreadsScreen({super.key, this.staff = false});
  final bool staff;
  @override
  State<ChatThreadsScreen> createState() => _ChatThreadsScreenState();
}

class _ChatThreadsScreenState extends State<ChatThreadsScreen> {
  int _key = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.staff ? tr('رسائل المرضى', 'Patient messages') : tr('رسائلي', 'My messages'))),
      floatingActionButton: widget.staff
          ? FloatingActionButton.extended(
              onPressed: () async {
                final list = await rpcList('doctor_my_patients', {'p_doctor': actingDoctorId()}).catchError((_) => <Map<String, dynamic>>[]);
                if (!context.mounted) return;
                final p = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (c) => SafeArea(child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.65),
                    child: ListView(shrinkWrap: true, children: [
                      for (final x in list)
                        ListTile(
                          leading: UserAvatar(url: x['avatar_url'] as String?, name: x['patient_name'] as String?, radius: 18),
                          title: Text(x['patient_name'] ?? ''),
                          onTap: () => Navigator.pop(c, x),
                        ),
                    ]),
                  )),
                );
                if (p == null || !context.mounted) return;
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                    doctorId: actingDoctorId(), patientId: p['patient_id'] as String, title: p['patient_name'] as String? ?? '')));
                setState(() => _key++);
              },
              icon: const Icon(Icons.edit_rounded),
              label: Text(tr('رسالة جديدة', 'New message')),
            )
          : null,
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => rpcList('chat_threads', {if (widget.staff) 'p_doctor': actingDoctorId()}),
        builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
          if (list.isEmpty)
            EmptyView(icon: Icons.chat_bubble_outline_rounded, title: tr('مفيش رسائل', 'No messages'),
                subtitle: widget.staff ? null : tr('تقدر تراسل أي دكتور انضميت لعيادته.', 'You can message any doctor you joined.')),
          for (final t in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: UserAvatar(url: t['avatar_url'] as String?, name: t['name'] as String?, radius: 22),
                title: Text('${widget.staff ? '' : '${tr('د.', 'Dr.')} '}${t['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(t['last'] as String? ?? tr('ابدأ المحادثة', 'Start the conversation'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_time(t['last_at'] as String?), style: const TextStyle(fontSize: 11)),
                  if (((t['unread'] as num?) ?? 0) > 0) Badge(label: Text('${t['unread']}')),
                ]),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                        doctorId: widget.staff ? actingDoctorId() : t['doctor_id'] as String,
                        patientId: widget.staff ? t['patient_id'] as String : null,
                        title: '${widget.staff ? '' : '${tr('د.', 'Dr.')} '}${t['name'] ?? ''}',
                      )));
                  setState(() => _key++);
                },
              ),
            ),
        ]),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  /// [patientId] set = clinic staff talking to that patient; null = the signed-in patient.
  const ChatScreen({super.key, required this.doctorId, this.patientId, required this.title});
  final String doctorId;
  final String? patientId;
  final String title;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with LiveReload<ChatScreen> {
  @override
  void onLiveChange() => _load();

  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msgs = const [];
  bool _loading = true;
  RealtimeChannel? _ch;
  Timer? _poll;
  bool get _staff => widget.patientId != null;

  @override
  void initState() {
    super.initState();
    _load();
    final pid = widget.patientId ?? myId;
    try {
      _ch = supa
          .channel('chat-${widget.doctorId}-$pid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'patient_id', value: pid),
            callback: (p) {
              if (p.newRecord['doctor_id'] == widget.doctorId) _load();
            },
          )
          .subscribe();
    } catch (_) {}
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_ch != null) supa.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await rpc('chat_messages', {'p_doctor': widget.doctorId, 'p_patient': widget.patientId});
      final list = (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      final grew = list.length != _msgs.length;
      setState(() {
        _msgs = list;
        _loading = false;
      });
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (e) {
      if (mounted && _loading) {
        setState(() => _loading = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    try {
      await rpc('send_message', {'p_doctor': widget.doctorId, 'p_body': t, 'p_patient': widget.patientId});
      await _load();
    } catch (e) {
      _text.text = t;
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const LoadingView()
              : _msgs.isEmpty
                  ? EmptyView(icon: Icons.chat_rounded, title: tr('ابدأ المحادثة', 'Start the conversation'),
                      subtitle: _staff ? null : tr('الرد بيكون من الدكتور أو السكرتارية. في الطوارئ اتصل بـ123.',
                          'Replies come from the doctor or reception. In an emergency call 123.'))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _msgs.length,
                      itemBuilder: (context, i) {
                        final m = _msgs[i];
                        final mine = (m['from_patient'] == true) != _staff;
                        return Align(
                          alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                            decoration: BoxDecoration(
                              color: mine ? cs.primary : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (!mine && m['from_patient'] != true && m['sender'] != null)
                                Text('${m['sender']}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cs.primary)),
                              Text('${m['body']}', style: TextStyle(color: mine ? cs.onPrimary : cs.onSurface, height: 1.45)),
                              const SizedBox(height: 2),
                              Text('${_time(m['created_at'] as String?)}${mine && m['read'] == true ? '  ✓✓' : ''}',
                                  style: TextStyle(fontSize: 10.5, color: mine ? cs.onPrimary.withValues(alpha: 0.8) : cs.onSurfaceVariant)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(hintText: tr('اكتب رسالتك…', 'Type a message…'), counterText: ''),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}
