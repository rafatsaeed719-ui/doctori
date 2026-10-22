import 'package:flutter/material.dart';

import '../core/backgrounds.dart';
import '../core/body_map.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/phone.dart';
import '../core/reminders.dart';
import '../core/specialty_templates.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The form of the signed-in doctor (or the doctor an assistant works for).
CaseTemplate myCaseTemplate() {
  final ctx = AppState.context;
  final en = isAssistant ? (ctx['assistant_of'] as Map?)?['specialty_en'] as String? : ctx['specialty_en'] as String?;
  return templateForSpecialty(en);
}

Color _accentFor(Map<String, dynamic> plan) => specialtyLook(plan['specialty_en'] as String?).accent;

String _num(num? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

String _planStatus(String? s) => switch (s) {
      'completed' => tr('اكتمل العلاج 🎉', 'Completed 🎉'),
      'stopped' => tr('متوقف', 'Stopped'),
      _ => tr('جاري', 'Active'),
    };

// ===========================================================================
// Plans list (doctor tab «الحالة» and patient «خطتي العلاجية»)
// ===========================================================================
class CasePlansView extends StatefulWidget {
  /// [patientId] null = the signed-in patient's own plans (read-only).
  const CasePlansView({super.key, this.patientId});
  final String? patientId;
  @override
  State<CasePlansView> createState() => _CasePlansViewState();
}

class _CasePlansViewState extends State<CasePlansView> {
  int _key = 0;
  bool get _doctor => widget.patientId != null;

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await rpc('list_case_plans', {'p_patient': widget.patientId});
    return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _edit([Map<String, dynamic>? plan]) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => CasePlanEditor(patientId: widget.patientId!, plan: plan)));
    if (saved == true) setState(() => _key++);
  }

  Future<void> _session(Map<String, dynamic> p, int delta) async {
    final ok = await runBusy(context, () async {
      await rpc('add_plan_session', {'p_plan': p['id'], 'p_delta': delta});
    }, success: delta > 0 ? tr('اتسجلت الجلسة ✓', 'Session logged ✓') : null);
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    final mine = actingDoctorId();
    final body = FutureView<List<Map<String, dynamic>>>(
      key: ValueKey(_key),
      load: _load,
      builder: (context, plans, reload) => RefreshList(onRefresh: reload, children: [
        if (plans.isEmpty)
          EmptyView(
            icon: Icons.assignment_rounded,
            title: _doctor ? tr('لسه مفيش خطة علاج للحالة', 'No treatment plan yet') : tr('لسه مفيش خطة علاج', 'No treatment plan yet'),
            subtitle: _doctor
                ? tr('حدد نوع المشكلة ومكانها في الجسم والهدف ومدة الكورس.',
                    'Set the problem, where it is, the goal and the course length.')
                : tr('لما الدكتور يحدد خطتك هتظهر هنا: المشكلة، الهدف، ومدة العلاج.',
                    'When your doctor sets your plan it shows here: problem, goal and course.'),
          ),
        for (final p in plans)
          PlanCard(
            plan: p,
            canEdit: _doctor && p['doctor_id'] == mine && can('medical'),
            onEdit: () => _edit(p),
            onSession: (d) => _session(p, d),
          ),
      ]),
    );
    if (!_doctor) return body;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: can('medical')
          ? FloatingActionButton.extended(
              heroTag: 'plan',
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_chart_rounded),
              label: Text(tr('خطة علاج جديدة', 'New plan')),
            )
          : null,
      body: body,
    );
  }
}

class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.plan, this.canEdit = false, this.onEdit, this.onSession});
  final Map<String, dynamic> plan;
  final bool canEdit;
  final VoidCallback? onEdit;
  final ValueChanged<int>? onSession;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = templateByKey(plan['specialty_key'] as String?);
    final accent = _accentFor(plan);
    final data = Map<String, dynamic>.from(plan['data'] as Map? ?? const {});
    final problems = [
      for (final k in (data['problems'] as List? ?? const [])) optLabel(t.problems, '$k'),
      if ((data['problem_other'] as String?)?.trim().isNotEmpty == true) data['problem_other'] as String,
    ];
    final regions = {for (final r in (data['regions'] as List? ?? const [])) '$r'};
    final goals = [for (final k in (data['goals'] as List? ?? const [])) optLabel(t.goals, '$k')];
    final measures = Map<String, dynamic>.from(data['measures'] as Map? ?? const {});
    final history = (plan['history'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final firstMeasures = history.isEmpty ? const <String, dynamic>{} : Map<String, dynamic>.from(history.first['measures'] as Map? ?? const {});
    final total = (plan['sessions_total'] as num?)?.toInt();
    final done = (plan['sessions_done'] as num?)?.toInt() ?? 0;
    final weeks = (plan['course_weeks'] as num?)?.toInt();
    final start = DateTime.tryParse('${plan['start_date']}');
    final end = (start != null && weeks != null) ? start.add(Duration(days: weeks * 7)) : null;
    final daysLeft = end?.difference(DateTime.now()).inDays;
    final status = plan['status'] as String?;
    final w = (measures['weight'] as num?)?.toDouble(), h = (measures['height'] as num?)?.toDouble();
    final bmi = (w != null && h != null && h > 50) ? w / ((h / 100) * (h / 100)) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [lighten(accent, 0.75), lighten(accent, 0.9)])),
            child: Row(children: [
              Icon3D(Icons.assignment_rounded, color: accent, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: darken(accent, 0.45))),
                  Text('${tr('د.', 'Dr.')} ${plan['doctor_name'] ?? ''} • ${tr('من', 'since')} ${formatDate(plan['start_date'] as String?)}',
                      style: TextStyle(fontSize: 12.5, color: darken(accent, 0.4))),
                ]),
              ),
              StatusChip(_planStatus(status),
                  color: status == 'completed' ? Tone.green : (status == 'stopped' ? Colors.grey : darken(accent, 0.2))),
              if (canEdit) IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (problems.isNotEmpty) ...[
                _label(context, '🩺', tr('المشكلة', 'Problem')),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final p in problems) StatusChip(p, color: darken(accent, 0.15))]),
                const SizedBox(height: 12),
              ],
              if (regions.isNotEmpty) ...[
                _label(context, '📍', tr('مكان المشكلة', 'Where')),
                Text(regions.map((r) => regionLabel(r, t)).join(' • '), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (t.map == MapKind.body) BodyMap(selected: regions, color: accent, height: 210),
                if (t.map == MapKind.teeth) TeethChart(selected: regions, color: accent),
                const SizedBox(height: 12),
              ],
              if (goals.isNotEmpty) ...[
                _label(context, '🎯', tr('الهدف', 'Goal')),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final g in goals) StatusChip(g, color: Tone.green)]),
                const SizedBox(height: 12),
              ],
              if (measures.isNotEmpty) ...[
                _label(context, '📏', tr('القياسات', 'Measurements')),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in t.measures)
                    if (measures[m.key] is num) _MeasureBox(m: m, value: measures[m.key] as num, first: firstMeasures[m.key] as num?),
                  if (bmi != null)
                    _MeasureBox(m: const Measure('bmi', 'مؤشر كتلة الجسم', 'BMI', ''), value: double.parse(bmi.toStringAsFixed(1))),
                ]),
                const SizedBox(height: 12),
              ],
              if (total != null || weeks != null) ...[
                _label(context, '⏳', tr('مدة العلاج / الكورس', 'Course')),
                if (total != null) ...[
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (done / total).clamp(0, 1).toDouble(),
                          minHeight: 12,
                          color: accent,
                          backgroundColor: lighten(accent, 0.85),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$done / $total ${t.sessionWord}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 6),
                ],
                if (weeks != null)
                  Text(
                    '${tr('$weeks أسبوع', '$weeks weeks')}'
                    '${end != null ? ' • ${tr('ينتهي تقريباً', 'ends about')} ${formatDate(end.toIso8601String())}' : ''}'
                    '${daysLeft != null && daysLeft > 0 && status == 'active' ? ' • ${tr('فاضل $daysLeft يوم', '$daysLeft days left')}' : ''}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                const SizedBox(height: 12),
              ],
              if ((data['diagnosis'] as String?)?.isNotEmpty == true) ...[
                _label(context, '📝', tr('التشخيص والتعليمات', 'Diagnosis & instructions')),
                Text(data['diagnosis'] as String, style: const TextStyle(height: 1.6)),
              ],
              if (canEdit && status == 'active' && total != null) ...[
                const Divider(height: 24),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(44)),
                      onPressed: () => onSession?.call(1),
                      icon: const Icon(Icons.add_task_rounded),
                      label: Text(tr('تسجيل ${t.sessionAr} تمت', 'Log a ${t.sessionEn}')),
                    ),
                  ),
                  if (done > 0)
                    IconButton(
                      tooltip: tr('تراجع', 'Undo'),
                      onPressed: () => onSession?.call(-1),
                      icon: const Icon(Icons.undo_rounded),
                    ),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _label(BuildContext context, String emoji, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('$emoji  $text', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
      );
}

class _MeasureBox extends StatelessWidget {
  const _MeasureBox({required this.m, required this.value, this.first});
  final Measure m;
  final num value;
  final num? first;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final diff = (first == null) ? 0 : value - first!;
    final good = m.lowerIsBetter == null ? null : (m.lowerIsBetter! ? diff < 0 : diff > 0);
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.label, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
        Text('${_num(value)} ${m.unit}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        if (diff != 0)
          Text('${diff > 0 ? '▲' : '▼'} ${_num(diff.abs())} ${tr('من البداية', 'since start')}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: good == null ? cs.onSurfaceVariant : (good ? Tone.green : Tone.red))),
      ]),
    );
  }
}

// ===========================================================================
// Editor
// ===========================================================================
class CasePlanEditor extends StatefulWidget {
  const CasePlanEditor({super.key, required this.patientId, this.plan});
  final String patientId;
  final Map<String, dynamic>? plan;
  @override
  State<CasePlanEditor> createState() => _CasePlanEditorState();
}

class _CasePlanEditorState extends State<CasePlanEditor> {
  late CaseTemplate _t;
  final _problems = <String>{};
  final _regions = <String>{};
  final _goals = <String>{};
  final _other = TextEditingController();
  final _diagnosis = TextEditingController();
  final _measures = <String, TextEditingController>{};
  late int? _weeks;
  late final _sessions = TextEditingController();
  late DateTime _start;
  String _status = 'active';

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _t = p == null ? myCaseTemplate() : templateByKey(p['specialty_key'] as String?);
    final data = Map<String, dynamic>.from(p?['data'] as Map? ?? const {});
    _problems.addAll([for (final x in (data['problems'] as List? ?? const [])) '$x']);
    _regions.addAll([for (final x in (data['regions'] as List? ?? const [])) '$x']);
    _goals.addAll([for (final x in (data['goals'] as List? ?? const [])) '$x']);
    _other.text = data['problem_other'] as String? ?? '';
    _diagnosis.text = data['diagnosis'] as String? ?? '';
    final ms = Map<String, dynamic>.from(data['measures'] as Map? ?? const {});
    for (final m in _t.measures) {
      _measures[m.key] = TextEditingController(text: ms[m.key] == null ? '' : _num(ms[m.key] as num));
    }
    _weeks = p == null ? _t.weeks : (p['course_weeks'] as num?)?.toInt();
    _sessions.text = p == null ? '${_t.sessions}' : '${p['sessions_total'] ?? ''}';
    _start = DateTime.tryParse('${p?['start_date']}') ?? DateTime.now();
    _status = p?['status'] as String? ?? 'active';
  }

  Future<void> _save() async {
    if (_problems.isEmpty && _other.text.trim().isEmpty) {
      showMessage(context, tr('اختار نوع المشكلة الأول', 'Choose the problem first'), error: true);
      return;
    }
    final measures = <String, num>{};
    for (final e in _measures.entries) {
      final v = num.tryParse(e.value.text.trim().replaceAll(',', '.'));
      if (v != null) measures[e.key] = v;
    }
    final sessions = int.tryParse(_sessions.text.trim());
    final ok = await runBusy(context, () async {
      await rpc('save_case_plan', {
        'p_plan': widget.plan?['id'],
        'p_patient': widget.patientId,
        'p_data': {
          'problems': _problems.toList(),
          'problem_other': _other.text.trim(),
          'regions': _regions.toList(),
          'goals': _goals.toList(),
          'measures': measures,
          'diagnosis': _diagnosis.text.trim(),
        },
        'p_specialty_key': _t.key,
        'p_course_weeks': _weeks,
        'p_sessions_total': sessions,
        'p_start_date': _iso(_start),
        'p_status': _status,
        'p_doctor': actingDoctorId(),
      });
    }, success: tr('تم حفظ الخطة ✓ والمريض يقدر يشوفها', 'Plan saved ✓ — the patient can see it'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _section(String emoji, String title, Widget child, {String? hint}) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$emoji  $title', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
            if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint, style: const TextStyle(fontSize: 12))),
            const SizedBox(height: 10),
            child,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(widget.plan == null ? tr('خطة علاج جديدة', 'New treatment plan') : tr('تعديل الخطة', 'Edit plan'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: DropdownButtonFormField<String>(
              initialValue: _t.key,
              decoration: InputDecoration(labelText: tr('نموذج التخصص', 'Specialty form'), border: InputBorder.none),
              items: [for (final t in allTemplates) DropdownMenuItem(value: t.key, child: Text(t.title))],
              onChanged: widget.plan != null
                  ? null
                  : (k) => setState(() {
                        _t = templateByKey(k);
                        _problems.clear();
                        _regions.clear();
                        _goals.clear();
                        for (final m in _t.measures) {
                          _measures.putIfAbsent(m.key, TextEditingController.new);
                        }
                        _weeks = _t.weeks;
                        _sessions.text = '${_t.sessions}';
                      }),
            ),
          ),
        ),
        _section('🩺', tr('نوع المشكلة', 'Problem type'), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in _t.problems)
              FilterChip(
                label: Text(o.label),
                selected: _problems.contains(o.key),
                onSelected: (v) => setState(() => v ? _problems.add(o.key) : _problems.remove(o.key)),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _other, decoration: InputDecoration(labelText: tr('مشكلة تانية (اكتبها)', 'Other problem'))),
        ])),
        if (_t.map != MapKind.none)
          _section('📍', tr('المشكلة فين؟', 'Where is the problem?'),
              RegionPicker(template: _t, selected: _regions, accent: accent, onChanged: (s) => setState(() {
                    _regions
                      ..clear()
                      ..addAll(s);
                  })),
              hint: _t.map == MapKind.body ? tr('اضغط على الأماكن في الجسم', 'Tap the places on the body') : null),
        _section('🎯', tr('الهدف من العلاج', 'Goal'), Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in _t.goals)
            FilterChip(
              label: Text(o.label),
              selected: _goals.contains(o.key),
              selectedColor: lighten(Tone.green, 0.7),
              onSelected: (v) => setState(() => v ? _goals.add(o.key) : _goals.remove(o.key)),
            ),
        ])),
        if (_t.measures.isNotEmpty)
          _section('📏', tr('القياسات الحالية', 'Current measurements'),
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 10) / 2;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final m in _t.measures)
                    SizedBox(
                      width: w,
                      child: TextField(
                        controller: _measures[m.key],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(labelText: m.label, suffixText: m.unit),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                ]);
              }),
              hint: tr('كل تعديل بيتحفظ، فتقدر تتابع التقدم (مثلاً نزول الوزن).', 'Every update is kept so you can follow progress.')),
        _section('⏳', tr('مدة العلاج / الكورس', 'Treatment course'), Column(children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _weeks,
                decoration: InputDecoration(labelText: tr('المدة', 'Length')),
                items: [
                  for (final w in [1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 36, 52])
                    DropdownMenuItem<int?>(value: w, child: Text(tr('$w أسبوع', '$w weeks'))),
                  DropdownMenuItem<int?>(value: null, child: Text(tr('مفتوحة', 'Open'))),
                ],
                onChanged: (v) => setState(() => _weeks = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _sessions,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: tr('عدد ${_t.sessionAr}ات', 'Number of ${_t.sessionEn}s')),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(tr('بداية العلاج', 'Start date')),
            subtitle: Text(formatDate(_start.toIso8601String())),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _start,
                  firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null) setState(() => _start = d);
            },
          ),
          if (widget.plan != null)
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'active', label: Text(tr('جاري', 'Active'))),
                ButtonSegment(value: 'completed', label: Text(tr('اكتمل', 'Done'))),
                ButtonSegment(value: 'stopped', label: Text(tr('متوقف', 'Stopped'))),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
        ])),
        _section('📝', tr('التشخيص والتعليمات للمريض', 'Diagnosis & instructions'), TextField(
          controller: _diagnosis,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(hintText: tr('مثلاً: تمارين يومية للظهر 15 دقيقة، ممنوع رفع حاجات تقيلة',
              'e.g. daily back exercises, no heavy lifting')),
        )),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: Text(tr('حفظ الخطة', 'Save plan'))),
        ),
      ),
    );
  }
}

// ===========================================================================
// Follow-up appointments set by the doctor
// ===========================================================================
(String, Color) followupStatus(String? s) => switch (s) {
      'done' => (tr('تمت', 'Done'), Tone.green),
      'cancelled' => (tr('ملغي', 'Cancelled'), Tone.red),
      'missed' => (tr('لم يحضر', 'Missed'), Colors.grey),
      _ => (tr('قادم', 'Upcoming'), Tone.blue),
    };

String followupWhen(Map<String, dynamic> f) {
  final d = DateTime.tryParse('${f['local_date']}');
  final day = d == null ? '' : weekdayName(d.weekday % 7);
  return '$day ${formatDate(f['local_date'] as String?)} — ${formatTime('${f['local_time']}:00')}';
}

String followupMessage(Map<String, dynamic> f, {String? patientName}) {
  final doctor = isAssistant ? (AppState.context['assistant_of'] as Map?)?['doctor_name'] : AppState.context['full_name'];
  return tr(
    'أهلاً ${patientName ?? ''} 👋\nميعاد المتابعة بتاعك مع د. ${doctor ?? ''}:\n📅 ${followupWhen(f)}\n🩺 ${f['title']}'
        '${(f['notes'] as String?)?.isNotEmpty == true ? '\n📝 ${f['notes']}' : ''}\nهتلاقي الميعاد كمان في تطبيق ${AppState.appName.value}.',
    'Hello ${patientName ?? ''} 👋\nYour follow-up with Dr. ${doctor ?? ''}:\n📅 ${followupWhen(f)}\n🩺 ${f['title']}'
        '${(f['notes'] as String?)?.isNotEmpty == true ? '\n📝 ${f['notes']}' : ''}\nIt is also in the ${AppState.appName.value} app.',
  );
}

class FollowupsView extends StatefulWidget {
  /// [patientId] null = the signed-in patient's own follow-ups (also schedules phone reminders).
  const FollowupsView({super.key, this.patientId, this.patientName, this.patientPhone});
  final String? patientId;
  final String? patientName;
  final String? patientPhone;
  @override
  State<FollowupsView> createState() => _FollowupsViewState();
}

class _FollowupsViewState extends State<FollowupsView> {
  int _key = 0;
  bool get _doctor => widget.patientId != null;

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await rpc('patient_followups', {'p_patient': widget.patientId});
    final list = (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (!_doctor) Reminders.syncFollowups(list);
    return list;
  }

  Future<void> _add() async {
    final f = await scheduleFollowupDialog(context, patientId: widget.patientId!);
    if (f == null || !mounted) return;
    setState(() => _key++);
    final send = await confirmDialog(context,
        title: tr('تم تحديد الميعاد ✓', 'Follow-up set ✓'),
        body: tr('المريض هيشوفه في التطبيق ويجيله تنبيه قبلها بيوم وقبلها بساعتين. تحب تبعتله رسالة واتساب كمان؟',
            'The patient sees it in the app and gets reminders a day and 2 hours before. Also send a WhatsApp message?'),
        confirm: tr('ابعت واتساب', 'Send WhatsApp'));
    if (send && mounted) {
      await openWhatsApp(context, f['patient_phone'] as String? ?? widget.patientPhone,
          followupMessage(f, patientName: widget.patientName));
    }
  }

  Future<void> _status(Map<String, dynamic> f, String s) async {
    final ok = await runBusy(context, () async {
      await rpc('set_followup_status', {'p_id': f['id'], 'p_status': s});
    });
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureView<List<Map<String, dynamic>>>(
      key: ValueKey(_key),
      load: _load,
      builder: (context, list, reload) {
        final now = DateTime.now();
        final upcoming = list.where((f) => f['status'] == 'scheduled' &&
            (DateTime.tryParse('${f['scheduled_at']}')?.isAfter(now.subtract(const Duration(hours: 3))) ?? false)).toList()
          ..sort((a, b) => '${a['scheduled_at']}'.compareTo('${b['scheduled_at']}'));
        final past = list.where((f) => !upcoming.contains(f)).toList();
        return RefreshList(onRefresh: reload, children: [
          if (!_doctor)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoBanner(icon: Icons.notifications_active_outlined,
                  text: tr('هيجيلك تنبيه على الموبايل قبل كل ميعاد بيوم وقبله بساعتين.',
                      'You get a phone reminder a day and 2 hours before each follow-up.')),
            ),
          if (list.isEmpty)
            EmptyView(
              icon: Icons.event_repeat_rounded,
              title: tr('مفيش مواعيد متابعة', 'No follow-ups'),
              subtitle: _doctor ? tr('حدد للمريض ميعاد متابعة بالتاريخ والوقت.', 'Set a dated follow-up for the patient.') : null,
            ),
          if (upcoming.isNotEmpty) SectionTitle(tr('المواعيد القادمة', 'Upcoming')),
          for (final f in upcoming) _FollowupCard(f: f, doctor: _doctor, onStatus: (s) => _status(f, s),
              onWhatsApp: () => openWhatsApp(context, widget.patientPhone, followupMessage(f, patientName: widget.patientName))),
          if (past.isNotEmpty) SectionTitle(tr('مواعيد سابقة', 'Past')),
          for (final f in past) Opacity(opacity: 0.7, child: _FollowupCard(f: f, doctor: _doctor, onStatus: (s) => _status(f, s))),
        ]);
      },
    );
    if (!_doctor) return body;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: (can('bookings') || can('medical'))
          ? FloatingActionButton.extended(
              heroTag: 'fu',
              onPressed: _add,
              icon: const Icon(Icons.edit_calendar_rounded),
              label: Text(tr('ميعاد متابعة', 'Follow-up')),
            )
          : null,
      body: body,
    );
  }
}

class _FollowupCard extends StatelessWidget {
  const _FollowupCard({required this.f, required this.doctor, this.onStatus, this.onWhatsApp});
  final Map<String, dynamic> f;
  final bool doctor;
  final ValueChanged<String>? onStatus;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final (label, color) = followupStatus(f['status'] as String?);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon3D(Icons.event_repeat_rounded, color: color, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  Text(followupWhen(f), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (!doctor) Text('${tr('د.', 'Dr.')} ${f['doctor_name'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
              StatusChip(label, color: color),
            ]),
            if ((f['notes'] as String?)?.isNotEmpty == true)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('📝 ${f['notes']}', style: const TextStyle(height: 1.5))),
            if (doctor && f['status'] == 'scheduled') ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: Tone.green),
                  onPressed: () => onStatus?.call('done'),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(tr('تمت', 'Done')),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => onStatus?.call('missed'),
                  child: Text(tr('لم يحضر', 'Missed')),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => onStatus?.call('cancelled'),
                  child: Text(tr('إلغاء', 'Cancel')),
                ),
                if (onWhatsApp != null)
                  IconButton(tooltip: tr('تذكير على واتساب', 'WhatsApp reminder'), onPressed: onWhatsApp,
                      icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Doctor picks date, time and purpose. Returns the server result (id, patient phone/name) plus the shown fields.
Future<Map<String, dynamic>?> scheduleFollowupDialog(BuildContext context, {required String patientId}) async {
  final title = TextEditingController(text: tr('متابعة', 'Follow-up'));
  final notes = TextEditingController();
  var date = DateTime.now().add(const Duration(days: 7));
  var time = const TimeOfDay(hour: 17, minute: 0);
  final presets = [
    tr('متابعة', 'Follow-up'),
    tr('جلسة', 'Session'),
    tr('إعادة كشف', 'Re-visit'),
    tr('نتيجة تحاليل', 'Lab results'),
    tr('أشعة', 'X-ray'),
    tr('غيار على جرح', 'Dressing'),
  ];
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('ميعاد متابعة للمريض', 'Follow-up for the patient'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in presets)
                ChoiceChip(label: Text(p), selected: title.text == p, onSelected: (_) => setS(() => title.text = p)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: title, maxLength: 150, decoration: InputDecoration(labelText: tr('سبب الميعاد', 'Purpose'))),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () async {
                    final d = await showDatePicker(context: c, initialDate: date, firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setS(() => date = d);
                  },
                  icon: const Icon(Icons.event),
                  label: Text('${weekdayName(date.weekday % 7)} ${formatDate(date.toIso8601String())}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () async {
                    final t = await showTimePicker(context: c, initialTime: time);
                    if (t != null) setS(() => time = t);
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text(time.format(c)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLines: 2, maxLength: 1000,
                decoration: InputDecoration(labelText: tr('ملاحظة للمريض', 'Note for the patient'),
                    hintText: tr('مثلاً: هات التحاليل معاك، تعالى صايم', 'e.g. bring your lab results'))),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                if (title.text.trim().isNotEmpty) Navigator.pop(c, true);
              },
              icon: const Icon(Icons.check),
              label: Text(tr('تحديد الميعاد', 'Set follow-up')),
            ),
          ]),
        ),
      ),
    ),
  );
  if (go != true || !context.mounted) return null;
  final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  Map<String, dynamic>? result;
  await runBusy(context, () async {
    final r = await rpc('schedule_followup', {
      'p_patient': patientId,
      'p_at': at.toUtc().toIso8601String(),
      'p_title': title.text.trim(),
      'p_notes': notes.text.trim(),
      'p_doctor': actingDoctorId(),
    });
    result = {
      ...Map<String, dynamic>.from(r as Map),
      'title': title.text.trim(),
      'notes': notes.text.trim(),
      'scheduled_at': at.toIso8601String(),
      'local_date': _iso(at),
      'local_time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    };
  });
  return result;
}
