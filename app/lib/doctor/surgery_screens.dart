import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

const surgeryStatuses = ['planned', 'preparing', 'done', 'recovery', 'closed', 'cancelled'];
(String, Color, IconData) surgeryStatus(String? s) => switch (s) {
      'preparing' => (tr('بيتجهز', 'Preparing'), Tone.orange, Icons.checklist_rounded),
      'done' => (tr('العملية تمت', 'Operated'), Tone.blue, Icons.local_hospital_rounded),
      'recovery' => (tr('متابعة بعد العملية', 'Recovery'), Tone.teal, Icons.healing_rounded),
      'closed' => (tr('خلصت بالسلامة', 'Closed'), Tone.green, Icons.verified_rounded),
      'cancelled' => (tr('اتلغت', 'Cancelled'), Colors.grey, Icons.cancel_rounded),
      _ => (tr('متخططة', 'Planned'), Tone.indigo, Icons.event_rounded),
    };

const _defaultPrep = ['تحاليل ما قبل العملية', 'رسم قلب', 'صيام 8 ساعات قبل العملية', 'إيقاف مسيلات الدم حسب تعليمات الدكتور',
    'إحضار الأشعة والتحاليل', 'مرافق مع المريض'];
const _defaultPost = ['غيار على الجرح', 'فك الغرز', 'المضاد الحيوي في مواعيده', 'متابعة في العيادة', 'علاج طبيعي'];

/// Operations of a patient: preparation checklist → the day → recovery. Doctor edits; the patient follows.
class SurgeriesView extends StatefulWidget {
  /// [patientId] null = my own (patient, read-only).
  const SurgeriesView({super.key, this.patientId});
  final String? patientId;
  @override
  State<SurgeriesView> createState() => _SurgeriesViewState();
}

class _SurgeriesViewState extends State<SurgeriesView> {
  int _key = 0;
  bool get _doctor => widget.patientId != null;

  Future<void> _edit([Map<String, dynamic>? s]) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => SurgeryForm(patientId: widget.patientId!, surgery: s)));
    if (saved == true) setState(() => _key++);
  }

  Future<void> _toggle(Map<String, dynamic> s, String list, int i) async {
    final items = (s[list] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    items[i]['done'] = items[i]['done'] != true;
    final ok = await runBusy(context, () async {
      await rpc('save_surgery', {
        'p_id': s['id'], 'p_patient': s['patient_id'], 'p_name': s['name'], 'p_scheduled_at': s['scheduled_at'],
        'p_place': s['place'], 'p_status': s['status'],
        'p_prep': list == 'prep' ? items : s['prep'], 'p_post': list == 'post' ? items : s['post'],
        'p_notes': s['notes'], 'p_fee': s['fee'], 'p_doctor': actingDoctorId(),
      });
    });
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureView<List<Map<String, dynamic>>>(
      key: ValueKey(_key),
      load: () async => ((await rpc('list_surgeries', {'p_patient': widget.patientId})) as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
        if (list.isEmpty)
          EmptyView(icon: Icons.local_hospital_rounded, title: tr('مفيش عمليات', 'No surgeries'),
              subtitle: _doctor ? tr('خطط لعملية: التجهيز، يوم العملية، والمتابعة بعدها.', 'Plan a surgery: preparation, the day, recovery.') : null),
        for (final s in list) _SurgeryCard(
          s: s,
          canEdit: _doctor && s['doctor_id'] == actingDoctorId() && can('medical'),
          onEdit: () => _edit(s),
          onToggle: (l, i) => _toggle(s, l, i),
        ),
      ]),
    );
    if (!_doctor) return body;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: can('medical')
          ? FloatingActionButton.extended(heroTag: 'surgery', onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded), label: Text(tr('عملية', 'Surgery')))
          : null,
      body: body,
    );
  }
}

class _SurgeryCard extends StatelessWidget {
  const _SurgeryCard({required this.s, required this.canEdit, this.onEdit, this.onToggle});
  final Map<String, dynamic> s;
  final bool canEdit;
  final VoidCallback? onEdit;
  final void Function(String list, int i)? onToggle;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = surgeryStatus(s['status'] as String?);
    final prep = (s['prep'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final post = (s['post'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final at = DateTime.tryParse('${s['scheduled_at']}')?.toLocal();
    final step = switch (s['status']) { 'planned' => 0, 'preparing' => 1, 'done' => 2, 'recovery' => 3, 'closed' => 4, _ => -1 };
    Widget checklist(String title, String key, List<Map<String, dynamic>> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text('$title (${items.where((x) => x['done'] == true).length}/${items.length})',
                    style: const TextStyle(fontWeight: FontWeight.w900))),
            for (var i = 0; i < items.length; i++)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: items[i]['done'] == true,
                onChanged: canEdit ? (_) => onToggle?.call(key, i) : null,
                title: Text('${items[i]['text'] ?? ''}',
                    style: TextStyle(decoration: items[i]['done'] == true ? TextDecoration.lineThrough : null)),
              ),
          ],
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon3D(icon, color: color, size: 46),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5)),
                if (at != null)
                  Text('${weekdayName(at.weekday % 7)} ${formatDate(at.toIso8601String())} — '
                      '${formatTime('${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:00')}'),
                if ((s['place'] as String?)?.isNotEmpty == true) Text('📍 ${s['place']}'),
                if (!canEdit) Text('${tr('د.', 'Dr.')} ${s['doctor_name'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
            StatusChip(label, color: color),
            if (canEdit) IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_rounded)),
          ]),
          if (step >= 0) ...[
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < 5; i++)
                Expanded(child: Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(color: i <= step ? color : color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4)),
                )),
            ]),
          ],
          if (prep.isNotEmpty) checklist(tr('التجهيز قبل العملية', 'Before surgery'), 'prep', prep),
          if (post.isNotEmpty) checklist(tr('بعد العملية', 'After surgery'), 'post', post),
          if ((s['notes'] as String?)?.isNotEmpty == true)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('📝 ${s['notes']}', style: const TextStyle(height: 1.5))),
        ]),
      ),
    );
  }
}

class SurgeryForm extends StatefulWidget {
  const SurgeryForm({super.key, required this.patientId, this.surgery});
  final String patientId;
  final Map<String, dynamic>? surgery;
  @override
  State<SurgeryForm> createState() => _SurgeryFormState();
}

class _SurgeryFormState extends State<SurgeryForm> {
  late final _name = TextEditingController(text: widget.surgery?['name'] as String?);
  late final _place = TextEditingController(text: widget.surgery?['place'] as String?);
  late final _notes = TextEditingController(text: widget.surgery?['notes'] as String?);
  late final _fee = TextEditingController(text: widget.surgery?['fee']?.toString() ?? '');
  late String _status = widget.surgery?['status'] as String? ?? 'planned';
  late DateTime? _at = DateTime.tryParse('${widget.surgery?['scheduled_at']}')?.toLocal();
  late final List<Map<String, dynamic>> _prep = widget.surgery == null
      ? [for (final t in _defaultPrep.take(3)) {'text': t, 'done': false}]
      : (widget.surgery!['prep'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  late final List<Map<String, dynamic>> _post = widget.surgery == null
      ? [for (final t in _defaultPost.take(2)) {'text': t, 'done': false}]
      : (widget.surgery!['post'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      showMessage(context, tr('اكتب اسم العملية', 'Enter the surgery name'), error: true);
      return;
    }
    final ok = await runBusy(context, () async {
      await rpc('save_surgery', {
        'p_id': widget.surgery?['id'],
        'p_patient': widget.patientId,
        'p_name': _name.text.trim(),
        'p_scheduled_at': _at?.toUtc().toIso8601String(),
        'p_place': _place.text.trim(),
        'p_status': _status,
        'p_prep': _prep,
        'p_post': _post,
        'p_notes': _notes.text.trim(),
        'p_fee': num.tryParse(_fee.text.trim()),
        'p_doctor': actingDoctorId(),
      });
    }, success: tr('اتحفظ ✓ والمريض بيشوف خطوات التجهيز', 'Saved ✓ — the patient sees the steps'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _list(String title, List<Map<String, dynamic>> items, List<String> suggestions) {
    final add = TextEditingController();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          for (var i = 0; i < items.length; i++)
            Row(children: [
              Checkbox(value: items[i]['done'] == true, onChanged: (v) => setState(() => items[i]['done'] = v == true)),
              Expanded(child: Text('${items[i]['text']}')),
              IconButton(onPressed: () => setState(() => items.removeAt(i)), icon: const Icon(Icons.close, size: 18)),
            ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final sgg in suggestions.where((x) => !items.any((i) => i['text'] == x)))
              ActionChip(label: Text(sgg), onPressed: () => setState(() => items.add({'text': sgg, 'done': false}))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: add, decoration: InputDecoration(hintText: tr('خطوة تانية…', 'Another step…')))),
            IconButton(
              onPressed: () {
                if (add.text.trim().isEmpty) return;
                setState(() => items.add({'text': add.text.trim(), 'done': false}));
              },
              icon: const Icon(Icons.add_circle_rounded),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.surgery == null ? tr('عملية جديدة', 'New surgery') : tr('تعديل العملية', 'Edit surgery'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(controller: _name, decoration: InputDecoration(labelText: tr('اسم العملية', 'Surgery'))),
              const SizedBox(height: 8),
              TextField(controller: _place, decoration: InputDecoration(labelText: tr('المستشفى / المكان', 'Hospital / place'))),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(tr('ميعاد العملية', 'Date & time')),
                subtitle: Text(_at == null ? tr('مش محدد', 'Not set') : '${formatDate(_at!.toIso8601String())} — '
                    '${TimeOfDay.fromDateTime(_at!).format(context)}'),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _at ?? DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d == null || !context.mounted) return;
                  final t = await showTimePicker(context: context, initialTime: _at == null ? const TimeOfDay(hour: 9, minute: 0)
                      : TimeOfDay.fromDateTime(_at!));
                  setState(() => _at = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: InputDecoration(labelText: tr('المرحلة', 'Stage')),
                items: [for (final s in surgeryStatuses) DropdownMenuItem(value: s, child: Text(surgeryStatus(s).$1))],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 8),
              TextField(controller: _fee, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: tr('تكلفة العملية (للدكتور بس)', 'Fee (doctor only)'), suffixText: tr('ج.م', 'EGP'))),
            ]),
          ),
        ),
        _list(tr('التجهيز قبل العملية', 'Before surgery'), _prep, _defaultPrep),
        _list(tr('بعد العملية', 'After surgery'), _post, _defaultPost),
        TextField(controller: _notes, maxLines: 3, maxLength: 2000,
            decoration: InputDecoration(labelText: tr('ملاحظات وتعليمات للمريض', 'Notes for the patient'))),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: Text(tr('حفظ', 'Save'))),
        ),
      ),
    );
  }
}
