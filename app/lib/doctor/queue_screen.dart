import 'dart:async';

import 'package:flutter/material.dart';

import '../core/avatar.dart';
import '../core/live_sync.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

(String, Color) queueStatus(String? s) => switch (s) {
      'called' => (tr('اتنادى', 'Called'), Tone.orange),
      'in_room' => (tr('جوه عند الدكتور', 'With doctor'), Tone.blue),
      'done' => (tr('خلص', 'Done'), Tone.green),
      'skipped' => (tr('مش موجود', 'Skipped'), Colors.grey),
      _ => (tr('منتظر', 'Waiting'), Tone.teal),
    };

/// Reception: today's waiting queue for one clinic — check in bookings, add walk-ins, call the next number.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, this.clinics});

  /// A medical center passes its doctors' clinics ({id, name}); otherwise the doctor's own clinics are used.
  final List<Map<String, dynamic>>? clinics;
  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> with LiveReload<QueueScreen> {
  @override
  void onLiveChange() => _load();

  List<Map<String, dynamic>>? _clinics;
  String? _clinic;
  Map<String, dynamic>? _data;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final rows = widget.clinics ??
          await supa.from('clinics').select('id, name').eq('doctor_id', actingDoctorId()).eq('is_active', true).order('created_at');
      setState(() {
        _clinics = List<Map<String, dynamic>>.from(rows);
        if (_clinics!.isNotEmpty) _clinic = _clinics!.first['id'] as String;
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _load() async {
    if (_clinic == null) return;
    try {
      final r = await rpc('queue_today', {'p_clinic': _clinic});
      if (mounted) setState(() {
        _data = Map<String, dynamic>.from(r as Map);
        _error = null;
      });
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = e);
    }
  }

  Future<void> _act(Future<void> Function() f, {String? ok}) async {
    if (await runBusy(context, f, success: ok)) _load();
  }

  Future<void> _walkIn() async {
    final name = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('إضافة مريض للدور', 'Add to queue')),
        content: TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: tr('اسم المريض', 'Patient name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('إضافة', 'Add'))),
        ],
      ),
    );
    if (go != true || name.text.trim().length < 2) return;
    await _act(() async => rpc('queue_add', {'p_clinic': _clinic, 'p_name': name.text.trim()}));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = (_data?['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final appts = (_data?['appointments'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final waiting = items.where((q) => q['status'] == 'waiting').toList();
    final current = items.where((q) => q['status'] == 'called' || q['status'] == 'in_room').toList();
    final finished = items.where((q) => q['status'] == 'done' || q['status'] == 'skipped').toList();
    final minutes = (_data?['minutes'] as num?)?.toInt() ?? 20;

    return Scaffold(
      appBar: AppBar(title: Text(tr('دور الانتظار', 'Waiting queue')), actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      floatingActionButton: _clinic == null
          ? null
          : FloatingActionButton.extended(onPressed: _walkIn, icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(tr('مريض من غير حجز', 'Walk-in'))),
      body: _error != null && _data == null
          ? ErrorView(message: friendlyError(_error!), onRetry: _init, details: errorDetails(_error!))
          : _clinics == null
              ? const LoadingView()
              : _clinics!.isEmpty
                  ? EmptyView(icon: Icons.local_hospital_outlined, title: tr('ضيف عيادة الأول', 'Add a clinic first'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
                        if (_clinics!.length > 1)
                          DropdownButtonFormField<String>(
                            initialValue: _clinic,
                            decoration: InputDecoration(labelText: tr('العيادة', 'Clinic')),
                            items: [for (final c in _clinics!) DropdownMenuItem(value: c['id'] as String, child: Text('${c['name']}'))],
                            onChanged: (v) => setState(() {
                              _clinic = v;
                              _data = null;
                              _load();
                            }),
                          ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Tone.orange, darken(Tone.orange, 0.2)]),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(tr('الدور دلوقتي', 'Now serving'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                Text(current.isEmpty ? '—' : '${current.last['number']}',
                                    style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, height: 1.1)),
                                if (current.isNotEmpty)
                                  Text('${current.last['patient_name'] ?? ''}', style: const TextStyle(color: Colors.white)),
                              ]),
                            ),
                            Column(children: [
                              Text('${waiting.length}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                              Text(tr('منتظرين', 'waiting'), style: const TextStyle(color: Colors.white)),
                              Text(tr('~${waiting.length * minutes} دقيقة', '~${waiting.length * minutes} min'),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ]),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: Tone.green),
                          onPressed: waiting.isEmpty
                              ? null
                              : () => _act(() async {
                                    final r = await rpc('queue_call_next', {'p_clinic': _clinic});
                                    if (r is Map && mounted) {
                                      showMessage(context, '${tr('اتفضل رقم', 'Calling number')} ${r['number']} — ${r['patient_name'] ?? ''}');
                                    }
                                  }),
                          icon: const Icon(Icons.campaign_rounded, size: 28),
                          label: Text(tr('نادي اللي عليه الدور', 'Call next'), style: const TextStyle(fontSize: 17)),
                        ),
                        if (appts.isNotEmpty) ...[
                          SectionTitle('${tr('حجوزات النهارده لسه ما وصلتش', 'Today’s bookings not checked in')} (${appts.length})'),
                          for (final a in appts)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(child: Text(hhmm(a['time'] as String?), style: const TextStyle(fontSize: 11))),
                                title: Text(a['patient_name'] ?? ''),
                                trailing: FilledButton.tonal(
                                  onPressed: () => _act(() async => rpc('queue_add', {'p_clinic': _clinic, 'p_appointment': a['id']}),
                                      ok: tr('اتضاف للدور ✓', 'Added ✓')),
                                  child: Text(tr('وصل', 'Arrived')),
                                ),
                              ),
                            ),
                        ],
                        SectionTitle('${tr('الدور', 'Queue')} (${waiting.length + current.length})'),
                        if (waiting.isEmpty && current.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(tr('مفيش حد منتظر دلوقتي.', 'Nobody is waiting.'), textAlign: TextAlign.center),
                          ),
                        for (final q in [...current, ...waiting]) _QueueTile(q: q, onStatus: (s) => _act(() async =>
                            rpc('queue_set_status', {'p_id': q['id'], 'p_status': s}))),
                        if (finished.isNotEmpty) ...[
                          SectionTitle('${tr('خلصوا النهارده', 'Done today')} (${finished.length})'),
                          for (final q in finished) Opacity(opacity: 0.6, child: _QueueTile(q: q)),
                        ],
                        const SizedBox(height: 8),
                        Text(tr('القائمة بتتحدث لوحدها كل 15 ثانية، والمريض بيوصله إشعار لما يتنادى.',
                            'Updates every 15 seconds; the patient is notified when called.'),
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ]),
                    ),
    );
  }
}

String hhmm(String? t) {
  if (t == null || t.length < 5) return '';
  final h = int.tryParse(t.substring(0, 2)) ?? 0;
  return '${h % 12 == 0 ? 12 : h % 12}:${t.substring(3, 5)}';
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.q, this.onStatus});
  final Map<String, dynamic> q;
  final ValueChanged<String>? onStatus;
  @override
  Widget build(BuildContext context) {
    final (label, color) = queueStatus(q['status'] as String?);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
          child: Text('${q['number']}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: darken(color, 0.2))),
        ),
        title: Row(children: [
          if (q['patient_id'] != null) ...[
            UserAvatar(url: q['patient_avatar'] as String?, name: q['patient_name'] as String?, radius: 12),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(q['patient_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        subtitle: Text(q['appointment_id'] != null ? tr('بحجز', 'Booked') : tr('من غير حجز', 'Walk-in')),
        trailing: onStatus == null
            ? StatusChip(label, color: color)
            : PopupMenuButton<String>(
                onSelected: onStatus,
                child: StatusChip(label, color: color),
                itemBuilder: (c) => [
                  PopupMenuItem(value: 'called', child: Text(tr('نادي عليه', 'Call'))),
                  PopupMenuItem(value: 'in_room', child: Text(tr('دخل للدكتور', 'With doctor'))),
                  PopupMenuItem(value: 'done', child: Text(tr('خلص', 'Done'))),
                  PopupMenuItem(value: 'skipped', child: Text(tr('مش موجود', 'Skip'))),
                  PopupMenuItem(value: 'waiting', child: Text(tr('رجّعه للانتظار', 'Back to waiting'))),
                ],
              ),
      ),
    );
  }
}

/// Patient home card: "you are number 7 — 3 ahead of you" (refreshes itself).
class MyQueueCard extends StatefulWidget {
  const MyQueueCard({super.key});
  @override
  State<MyQueueCard> createState() => _MyQueueCardState();
}

class _MyQueueCardState extends State<MyQueueCard> with LiveReload<MyQueueCard> {
  @override
  void onLiveChange() => _load();

  List<Map<String, dynamic>> _items = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await rpc('my_queue');
      if (mounted && r is List) setState(() => _items = r.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final q in _items)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: q['status'] == 'waiting'
                ? [Tone.teal, darken(Tone.teal, 0.2)]
                : [Tone.orange, darken(Tone.orange, 0.2)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(children: [
            Column(children: [
              Text(tr('رقمك', 'Your no.'), style: const TextStyle(color: Colors.white)),
              Text('${q['number']}', style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, height: 1.1)),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  q['status'] == 'waiting'
                      ? (((q['ahead'] as num?) ?? 0) == 0
                          ? tr('إنت اللي عليك الدور الجاي 👏', 'You are next 👏')
                          : tr('قدامك ${q['ahead']} — حوالي ${((q['ahead'] as num) * ((q['minutes'] as num?) ?? 20)).round()} دقيقة',
                              '${q['ahead']} ahead — about ${((q['ahead'] as num) * ((q['minutes'] as num?) ?? 20)).round()} min'))
                      : tr('دورك جه! اتفضل ادخل 🔔', 'It’s your turn! 🔔'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text('${tr('الدور دلوقتي', 'Now serving')}: ${q['now_serving'] ?? '—'}  •  ${tr('د.', 'Dr.')} ${q['doctor_name'] ?? ''}',
                    style: const TextStyle(color: Colors.white)),
                Text('${q['clinic_name'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}
