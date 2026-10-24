import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../common/notifications.dart';
import '../common/settings_screen.dart';
import '../core/avatar.dart';
import '../core/backgrounds.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../doctor/finance_screen.dart' show incomeKinds, incomeKindInfo, expenseCategories, expenseInfo, money;
import '../doctor/add_patient_screen.dart';
import '../doctor/queue_screen.dart';
import '../patient/booking_screens.dart';

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
final _pct = intl.NumberFormat('#,##0.#', 'en');

String centerRoleLabel(String? r) => switch (r) {
      'owner' => tr('صاحب المركز', 'Owner'),
      'manager' => tr('مدير', 'Manager'),
      'reception' => tr('استقبال', 'Reception'),
      _ => tr('طبيب', 'Doctor'),
    };

String _specialty(Map<String, dynamic> d) => (L10n.isAr ? d['specialty_ar'] : (d['specialty_en'] ?? d['specialty_ar'])) as String? ?? '';

Future<List<Map<String, dynamic>>> _doctors(String center) => rpcList('center_doctors', {'p_center': center});

// ===========================================================================
// Home of a center (owner, manager, reception)
// ===========================================================================
class CenterHome extends StatefulWidget {
  const CenterHome({super.key, required this.centerId, required this.name, this.role = 'reception', this.canFinance = false, this.standalone = true});
  final String centerId;
  final String name;
  final String role;
  final bool canFinance;

  /// true when it is the account's home screen (staff); false when a doctor opens it from their app.
  final bool standalone;
  @override
  State<CenterHome> createState() => _CenterHomeState();
}

class _CenterHomeState extends State<CenterHome> {
  int _key = 0;
  bool get _admin => widget.role == 'owner' || widget.role == 'manager';

  void _open(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    if (mounted) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    final look = specialtyLook(null);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.standalone ? null : AppBar(title: Text(widget.name)),
      body: PatternBackground(
        look: const SpecialtyLook(Tone.indigo, ['🏥', '🩺', '👩‍⚕️', '📅', '💊']),
        child: SafeArea(
          child: FutureView<List<Map<String, dynamic>>>(
            key: ValueKey(_key),
            load: () => _doctors(widget.centerId),
            builder: (context, docs, reload) {
              final active = docs.where((d) => d['status'] == 'active').toList();
              final today = active.fold<num>(0, (s, d) => s + _n(d['today_bookings']));
              final waiting = active.fold<num>(0, (s, d) => s + _n(d['waiting']));
              final clinics = [
                for (final d in active)
                  if (d['clinic_id'] != null) {'id': d['clinic_id'], 'name': '${tr('د.', 'Dr.')} ${d['name']} — ${_specialty(d)}'},
              ];
              return RefreshList(onRefresh: reload, padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                GlassCard(
                  child: Row(children: [
                    const Icon3D(Icons.local_hospital_rounded, color: Tone.indigo, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                        Text('${centerRoleLabel(widget.role)} • ${AppState.context['full_name'] ?? ''}',
                            style: TextStyle(color: darken(look.accent, 0.1), fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    if (widget.standalone) const NotificationBell(),
                  ]),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Stat(tr('أطباء', 'Doctors'), '${active.length}', Icons.medical_services_rounded, Tone.teal)),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat(tr('حجوزات النهارده', 'Today'), '$today', Icons.event_available_rounded, Tone.blue)),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat(tr('منتظرين', 'Waiting'), '$waiting', Icons.people_alt_rounded, Tone.orange)),
                ]),
                const SizedBox(height: 14),
                TileGrid(children: [
                  Tile3D(icon: Icons.event_note_rounded, color: Tone.blue, label: tr('حجوزات المركز', 'Center bookings'),
                      subtitle: tr('كل الأطباء في شاشة واحدة', 'All doctors on one screen'),
                      onTap: () => _open(CenterBookingsScreen(centerId: widget.centerId, canFinance: widget.canFinance))),
                  Tile3D(icon: Icons.campaign_rounded, color: Tone.orange, label: tr('دور الانتظار', 'Waiting queue'),
                      subtitle: tr('لكل دكتور دوره', 'Per doctor'),
                      onTap: () {
                        if (clinics.isEmpty) {
                          showMessage(context, tr('ضيف أطباء للمركز الأول', 'Add doctors first'), error: true);
                          return;
                        }
                        _open(QueueScreen(clinics: clinics));
                      }),
                  Tile3D(icon: Icons.account_balance_wallet_rounded, color: Tone.green, label: tr('حسابات المركز', 'Center accounts'),
                      subtitle: widget.canFinance ? tr('دخل كل دكتور ونصيبه', 'Each doctor’s income & share') : tr('تسجيل الدخل', 'Record income'),
                      onTap: () => _open(CenterFinanceScreen(centerId: widget.centerId, canFinance: widget.canFinance))),
                  Tile3D(icon: Icons.medical_services_rounded, color: Tone.teal, label: tr('أطباء المركز', 'Doctors'),
                      subtitle: _admin ? tr('النسب والمواعيد', 'Shares & hours') : tr('المواعيد', 'Hours'),
                      onTap: () => _open(CenterDoctorsScreen(centerId: widget.centerId, admin: _admin))),
                  if (_admin)
                    Tile3D(icon: Icons.badge_rounded, color: Tone.purple, label: tr('الموظفين', 'Staff'),
                        subtitle: tr('استقبال ومديرين', 'Reception & managers'),
                        onTap: () => _open(CenterStaffScreen(centerId: widget.centerId))),
                  if (_admin)
                    Tile3D(icon: Icons.settings_rounded, color: Tone.indigo, label: tr('بيانات المركز', 'Center info'),
                        onTap: () => _open(CenterInfoScreen(centerId: widget.centerId))),
                  if (widget.standalone)
                    Tile3D(icon: Icons.person_rounded, color: Tone.pink, label: tr('حسابي', 'My account'),
                        onTap: () => _open(const SettingsScreen())),
                ]),
                const SizedBox(height: 16),
                if (active.isNotEmpty) SectionTitle(tr('الأطباء النهارده', 'Doctors today')),
                for (final d in active)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: UserAvatar(url: d['avatar_url'] as String?, name: d['name'] as String?, radius: 22,
                          ring: specialtyLook(d['specialty_en'] as String?).accent),
                      title: Text('${tr('د.', 'Dr.')} ${d['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_specialty(d)),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('📅 ${d['today_bookings']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('🧍 ${d['waiting']}', style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Icon3D(icon, color: color, size: 34),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: darken(color, 0.2))),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ]),
      );
}

// ===========================================================================
// Doctors: invite, share %, hours, remove
// ===========================================================================
class CenterDoctorsScreen extends StatefulWidget {
  const CenterDoctorsScreen({super.key, required this.centerId, required this.admin});
  final String centerId;
  final bool admin;
  @override
  State<CenterDoctorsScreen> createState() => _CenterDoctorsScreenState();
}

class _CenterDoctorsScreenState extends State<CenterDoctorsScreen> {
  int _key = 0;

  Future<void> _invite() async {
    final login = TextEditingController();
    final share = TextEditingController(text: '50');
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('إضافة دكتور للمركز', 'Add a doctor')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('الدكتور لازم يكون عامل حساب على دكتوري. هيوصله دعوة يوافق عليها.',
              'The doctor needs a Doctori account; they will get an invitation to accept.'), style: const TextStyle(height: 1.5)),
          const SizedBox(height: 10),
          TextField(controller: login, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('موبايل أو إيميل الدكتور', 'Doctor’s mobile or email'))),
          const SizedBox(height: 10),
          TextField(controller: share, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('نسبة الدكتور من الدخل', 'Doctor’s share of income'), suffixText: '%')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('إرسال الدعوة', 'Invite'))),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('center_invite_doctor', {
        'p_center': widget.centerId,
        'p_login': login.text.trim(),
        'p_share': num.tryParse(share.text.trim()) ?? 50,
      });
    }, success: tr('الدعوة اتبعتت ✓', 'Invitation sent ✓'));
    if (ok) setState(() => _key++);
  }

  Future<void> _edit(Map<String, dynamic> d) async {
    final changed = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => CenterDoctorEditor(centerId: widget.centerId, doctor: d, admin: widget.admin)));
    if (changed == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('أطباء المركز', 'Center doctors'))),
      floatingActionButton: widget.admin
          ? FloatingActionButton.extended(onPressed: _invite, icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(tr('إضافة دكتور', 'Add doctor')))
          : null,
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => _doctors(widget.centerId),
        builder: (context, docs, reload) => RefreshList(onRefresh: reload, children: [
          if (docs.isEmpty)
            EmptyView(icon: Icons.medical_services_rounded, title: tr('مفيش أطباء لسه', 'No doctors yet'),
                subtitle: tr('ضيف أطباء المركز من كل التخصصات.', 'Add the center’s doctors from every specialty.')),
          for (final d in docs)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                onTap: d['status'] == 'active' ? () => _edit(d) : null,
                leading: UserAvatar(url: d['avatar_url'] as String?, name: d['name'] as String?, radius: 26,
                    ring: specialtyLook(d['specialty_en'] as String?).accent),
                title: Text('${tr('د.', 'Dr.')} ${d['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text([
                  _specialty(d),
                  if (widget.admin && d['share_percent'] != null) '${tr('نسبته', 'Share')} ${_pct.format(_n(d['share_percent']))}٪',
                  '${(d['hours'] as List? ?? const []).length} ${tr('فترة عمل', 'shifts')}',
                ].where((s) => s.isNotEmpty).join(' • ')),
                trailing: d['status'] == 'invited'
                    ? StatusChip(tr('مستني يوافق', 'Invited'), color: Tone.orange)
                    : (d['doctor_status'] != 'verified'
                        ? StatusChip(tr('حسابه مش متفعل', 'Not verified'), color: Tone.red)
                        : const Icon(Icons.chevron_right)),
              ),
            ),
        ]),
      ),
    );
  }
}

class CenterDoctorEditor extends StatefulWidget {
  const CenterDoctorEditor({super.key, required this.centerId, required this.doctor, required this.admin});
  final String centerId;
  final Map<String, dynamic> doctor;
  final bool admin;
  @override
  State<CenterDoctorEditor> createState() => _CenterDoctorEditorState();
}

class _CenterDoctorEditorState extends State<CenterDoctorEditor> {
  late final _share = TextEditingController(text: _pct.format(_n(widget.doctor['share_percent'] ?? 50)));
  late final Map<String, TextEditingController> _byKind = {
    for (final k in incomeKinds)
      k: TextEditingController(text: (widget.doctor['share_by_kind'] as Map?)?[k]?.toString() ?? ''),
  };
  // weekday (0 = Sunday) → [opens, closes] or null
  late final Map<int, List<TimeOfDay>?> _hours = {
    for (var w = 0; w < 7; w++) w: null,
  };

  @override
  void initState() {
    super.initState();
    for (final h in (widget.doctor['hours'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(h as Map);
      _hours[(m['weekday'] as num).toInt()] = [_t(m['opens'] as String), _t(m['closes'] as String)];
    }
  }

  TimeOfDay _t(String s) => TimeOfDay(hour: int.parse(s.substring(0, 2)), minute: int.parse(s.substring(3, 5)));
  String _s(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final ok = await runBusy(context, () async {
      if (widget.admin) {
        final by = <String, num>{};
        _byKind.forEach((k, c) {
          final v = num.tryParse(c.text.trim());
          if (v != null) by[k] = v;
        });
        await rpc('center_set_share', {
          'p_center': widget.centerId,
          'p_doctor': widget.doctor['doctor_id'],
          'p_share': num.tryParse(_share.text.trim()) ?? 50,
          'p_by_kind': by,
        });
        await rpc('center_set_hours', {
          'p_center': widget.centerId,
          'p_doctor': widget.doctor['doctor_id'],
          'p_hours': [
            for (final e in _hours.entries)
              if (e.value != null) {'weekday': e.key, 'opens': _s(e.value![0]), 'closes': _s(e.value![1])},
          ],
        });
      }
    }, success: tr('تم الحفظ ✓', 'Saved ✓'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    final yes = await confirmDialog(context,
        title: tr('إخراج الدكتور من المركز؟', 'Remove from center?'),
        body: tr('الحجوزات الجديدة عنده في المركز هتتقفل. حساباته القديمة هتفضل في التقارير.',
            'New center bookings stop; past accounts stay in the reports.'),
        confirm: tr('إخراج', 'Remove'), danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async =>
        rpc('center_remove_doctor', {'p_center': widget.centerId, 'p_doctor': widget.doctor['doctor_id']}));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doctor;
    return Scaffold(
      appBar: AppBar(title: Text('${tr('د.', 'Dr.')} ${d['name'] ?? ''}'), actions: [
        if (widget.admin) IconButton(tooltip: tr('إخراج من المركز', 'Remove'), onPressed: _remove, icon: const Icon(Icons.person_remove_outlined)),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
        Card(
          child: ListTile(
            leading: UserAvatar(url: d['avatar_url'] as String?, name: d['name'] as String?, radius: 24),
            title: Text(_specialty(d), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(displayPhone(d['phone'] as String?)),
            trailing: (d['phone'] as String?)?.isNotEmpty == true
                ? IconButton(onPressed: () => launchUrl(Uri(scheme: 'tel', path: displayPhone(d['phone'] as String?))),
                    icon: const Icon(Icons.call))
                : null,
          ),
        ),
        if (widget.admin) ...[
          SectionTitle(tr('نسبة الدكتور من الدخل', 'Doctor’s share of income')),
          TextField(controller: _share, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('النسبة العامة', 'General share'), suffixText: '%',
                  helperText: tr('الباقي نصيب المركز', 'The rest goes to the center'))),
          const SizedBox(height: 10),
          Text(tr('نسبة مختلفة لخدمة معينة (اختياري)', 'Different share per service (optional)'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final k in incomeKinds)
              SizedBox(
                width: 150,
                child: TextField(controller: _byKind[k], keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: '${incomeKindInfo(k).$1} ${incomeKindInfo(k).$2}', suffixText: '%', isDense: true)),
              ),
          ]),
        ],
        SectionTitle(tr('مواعيد الدكتور في المركز', 'Hours at the center')),
        for (var w in [6, 0, 1, 2, 3, 4, 5])
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: SwitchListTile(
              value: _hours[w] != null,
              onChanged: !widget.admin
                  ? null
                  : (v) => setState(() => _hours[w] = v ? [const TimeOfDay(hour: 17, minute: 0), const TimeOfDay(hour: 22, minute: 0)] : null),
              title: Text(weekdayName(w), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: _hours[w] == null
                  ? Text(tr('مش موجود', 'Off'))
                  : Row(children: [
                      TextButton(
                        onPressed: !widget.admin ? null : () async {
                          final t = await showTimePicker(context: context, initialTime: _hours[w]![0]);
                          if (t != null) setState(() => _hours[w]![0] = t);
                        },
                        child: Text('${tr('من', 'From')} ${_hours[w]![0].format(context)}'),
                      ),
                      TextButton(
                        onPressed: !widget.admin ? null : () async {
                          final t = await showTimePicker(context: context, initialTime: _hours[w]![1]);
                          if (t != null) setState(() => _hours[w]![1] = t);
                        },
                        child: Text('${tr('لـ', 'To')} ${_hours[w]![1].format(context)}'),
                      ),
                    ]),
            ),
          ),
      ]),
      bottomNavigationBar: widget.admin
          ? SafeArea(child: Padding(padding: const EdgeInsets.all(12),
              child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: Text(tr('حفظ', 'Save')))))
          : null,
    );
  }
}

// ===========================================================================
// Bookings of all doctors
// ===========================================================================
class CenterBookingsScreen extends StatefulWidget {
  const CenterBookingsScreen({super.key, required this.centerId, required this.canFinance});
  final String centerId;
  final bool canFinance;
  @override
  State<CenterBookingsScreen> createState() => _CenterBookingsScreenState();
}

class _CenterBookingsScreenState extends State<CenterBookingsScreen> {
  DateTime _day = DateTime.now();
  String? _doctor;
  int _key = 0;

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    final res = await Future.wait([
      rpcList('center_appointments', {'p_center': widget.centerId, 'p_from': _iso(_day), 'p_to': _iso(_day)}),
      _doctors(widget.centerId),
    ]);
    return (res[0], res[1].where((d) => d['status'] == 'active').toList());
  }

  Future<void> _status(Map<String, dynamic> a, String s) async {
    final ok = await runBusy(context, () async => rpc('set_appointment_status', {'p_id': a['id'], 'p_status': s}),
        success: tr('تم التحديث', 'Updated'));
    if (!ok || !mounted) return;
    setState(() => _key++);
    if (s == 'completed') {
      final add = await confirmDialog(context, title: tr('تسجيل الكشف في حسابات المركز؟', 'Record the payment?'),
          body: '${a['patient_name'] ?? ''} — ${tr('د.', 'Dr.')} ${a['doctor_name'] ?? ''}', confirm: tr('تسجيل', 'Record'));
      if (add && mounted) {
        await centerIncomeSheet(context, centerId: widget.centerId, doctorId: a['doctor_id'] as String?,
            patientId: a['patient_id'] as String?, patientName: a['patient_name'] as String?, appointmentId: a['id'] as String?);
      }
    }
  }

  Future<void> _book(List<Map<String, dynamic>> docs) async {
    if (docs.isEmpty) return;
    final d = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(child: ListView(shrinkWrap: true, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(tr('الحجز عند مين؟', 'Book with'), style: Theme.of(c).textTheme.titleLarge)),
        for (final x in docs)
          ListTile(
            leading: UserAvatar(url: x['avatar_url'] as String?, name: x['name'] as String?, radius: 18),
            title: Text('${tr('د.', 'Dr.')} ${x['name']}'),
            subtitle: Text(_specialty(x)),
            onTap: () => Navigator.pop(c, x),
          ),
      ])),
    );
    if (d == null || !mounted) return;
    List<Map<String, dynamic>> patients = const [];
    Map<String, dynamic>? pub;
    final ok = await runBusy(context, () async {
      patients = await rpcList('doctor_my_patients', {'p_doctor': d['doctor_id']});
      final r = await rpc('get_doctor_public', {'p_doctor': d['doctor_id']});
      pub = r is Map ? Map<String, dynamic>.from(r) : null;
    });
    if (!ok || !mounted) return;
    if (pub == null) {
      showMessage(context, tr('حساب الدكتور لسه مش متفعل.', 'The doctor is not verified yet.'), error: true);
      return;
    }
    // only the center clinic of this doctor
    pub!['clinics'] = (pub!['clinics'] as List? ?? const []).where((c) => (c as Map)['id'] == d['clinic_id']).toList();
    final p = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.65),
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
            title: Text(tr('مريض جديد', 'New patient'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(tr('سجّله الأول وبعدين احجزله', 'Register, then book')),
            onTap: () => Navigator.pop(c, {'new': true}),
          ),
          const Divider(height: 1),
          for (final x in patients)
            ListTile(
              leading: UserAvatar(url: x['avatar_url'] as String?, name: x['patient_name'] as String?, radius: 18),
              title: Text(x['patient_name'] ?? ''),
              subtitle: Text(displayPhone(x['phone'] as String?)),
              onTap: () => Navigator.pop(c, x),
            ),
        ]),
      )),
    );
    if (p == null || !mounted) return;
    if (p['new'] == true) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => AddPatientScreen(doctorId: d['doctor_id'] as String)));
      if (mounted) showMessage(context, tr('دوس «حجز لمريض» تاني واختار المريض الجديد', 'Tap “Book” again and pick the new patient'));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingScreen(
        doctor: pub!, patientId: p['patient_id'] as String, patientName: p['patient_name'] as String?)));
    setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return FutureView<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
      key: ValueKey(_key),
      load: _load,
      builder: (context, data, reload) {
        final (appts, docs) = data;
        final shown = appts.where((a) => _doctor == null || a['doctor_id'] == _doctor).toList();
        return Scaffold(
          appBar: AppBar(title: Text(tr('حجوزات المركز', 'Center bookings'))),
          floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _book(docs), icon: const Icon(Icons.add), label: Text(tr('حجز لمريض', 'Book'))),
          body: RefreshList(onRefresh: reload, children: [
            Row(children: [
              IconButton(onPressed: () => setState(() {
                    _day = _day.subtract(const Duration(days: 1));
                    _key++;
                  }), icon: const Icon(Icons.chevron_right)),
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2024),
                        lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setState(() {
                      _day = d;
                      _key++;
                    });
                  },
                  icon: const Icon(Icons.event),
                  label: Text('${weekdayName(_day.weekday % 7)} ${formatDate(_day.toIso8601String())}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              IconButton(onPressed: () => setState(() {
                    _day = _day.add(const Duration(days: 1));
                    _key++;
                  }), icon: const Icon(Icons.chevron_left)),
            ]),
            SizedBox(
              height: 46,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(
                    label: Text('${tr('الكل', 'All')} (${appts.length})'), selected: _doctor == null,
                    onSelected: (_) => setState(() => _doctor = null))),
                for (final d in docs)
                  Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(
                      label: Text('${d['name']} (${appts.where((a) => a['doctor_id'] == d['doctor_id']).length})'),
                      selected: _doctor == d['doctor_id'],
                      onSelected: (_) => setState(() => _doctor = d['doctor_id'] as String))),
              ]),
            ),
            const SizedBox(height: 10),
            if (shown.isEmpty)
              EmptyView(icon: Icons.event_busy_rounded, title: tr('مفيش حجوزات في اليوم ده', 'No bookings this day')),
            for (final a in shown) _CenterAppt(a: a, onStatus: (s) => _status(a, s)),
          ]),
        );
      },
    );
  }
}

class _CenterAppt extends StatelessWidget {
  const _CenterAppt({required this.a, required this.onStatus});
  final Map<String, dynamic> a;
  final ValueChanged<String> onStatus;
  @override
  Widget build(BuildContext context) {
    final (label, color) = appointmentStatus(a['status'] as String?);
    final accent = specialtyLook(a['specialty_en'] as String?).accent;
    final st = a['status'];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: accent, width: 5))),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(hhmm12(a['local_time'] as String?), style: TextStyle(fontWeight: FontWeight.w900, color: darken(accent, 0.2))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['patient_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${tr('د.', 'Dr.')} ${a['doctor_name'] ?? ''} • ${_specialty(a)}', style: const TextStyle(fontSize: 12.5)),
            ])),
            StatusChip(label, color: color),
          ]),
          if (st == 'pending' || st == 'confirmed')
            Wrap(spacing: 6, children: [
              if (st == 'pending') TextButton(onPressed: () => onStatus('confirmed'), child: Text(tr('تأكيد', 'Confirm'))),
              TextButton(onPressed: () => onStatus('completed'), child: Text(tr('تم الكشف', 'Done'))),
              TextButton(onPressed: () => onStatus('no_show'), child: Text(tr('لم يحضر', 'No show'))),
              TextButton(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => onStatus('cancelled'), child: Text(tr('إلغاء', 'Cancel'))),
              if ((a['patient_phone'] as String?)?.isNotEmpty == true)
                IconButton(onPressed: () => launchUrl(Uri(scheme: 'tel', path: displayPhone(a['patient_phone'] as String?))),
                    icon: const Icon(Icons.call, size: 20)),
            ]),
        ]),
      ),
    );
  }
}

// ===========================================================================
// Money
// ===========================================================================
Future<bool> centerIncomeSheet(BuildContext context,
    {required String centerId, String? doctorId, String? patientId, String? patientName, String? appointmentId}) async {
  List<Map<String, dynamic>> docs;
  try {
    docs = (await _doctors(centerId)).where((d) => d['status'] == 'active').toList();
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
    return false;
  }
  if (!context.mounted) return false;
  String? doc = doctorId ?? (docs.length == 1 ? docs.first['doctor_id'] as String : null);
  var kind = 'visit';
  final amount = TextEditingController();
  final name = TextEditingController(text: patientName);
  final note = TextEditingController();
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('دخل حالة في المركز', 'Center income'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(tr('الدكتور', 'Doctor'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in docs)
                ChoiceChip(
                  avatar: UserAvatar(url: d['avatar_url'] as String?, name: d['name'] as String?, radius: 12),
                  label: Text('${d['name']}'),
                  selected: doc == d['doctor_id'],
                  onSelected: (_) => setS(() => doc = d['doctor_id'] as String),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in incomeKinds)
                ChoiceChip(label: Text('${incomeKindInfo(k).$1} ${incomeKindInfo(k).$2}'), selected: kind == k,
                    onSelected: (_) => setS(() => kind = k)),
            ]),
            const SizedBox(height: 10),
            TextField(controller: amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                decoration: InputDecoration(labelText: tr('المبلغ', 'Amount'), suffixText: tr('ج.م', 'EGP'))),
            const SizedBox(height: 10),
            TextField(controller: name, readOnly: patientId != null, decoration: InputDecoration(labelText: tr('اسم الحالة', 'Patient'))),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('ملاحظة', 'Note'))),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Tone.green, minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                if (doc == null || (num.tryParse(amount.text.trim()) ?? 0) <= 0) {
                  showMessage(c, tr('اختار الدكتور واكتب المبلغ', 'Choose the doctor and the amount'), error: true);
                  return;
                }
                Navigator.pop(c, true);
              },
              child: Text(tr('حفظ', 'Save')),
            ),
          ])),
        )),
  );
  if (go != true || !context.mounted) return false;
  return runBusy(context, () async {
    await rpc('center_save_income', {
      'p_center': centerId,
      'p_doctor': doc,
      'p_kind': kind,
      'p_amount': num.parse(amount.text.trim()),
      'p_patient': patientId,
      'p_patient_name': patientId == null ? name.text.trim() : null,
      'p_note': note.text.trim(),
      'p_appointment': appointmentId,
    });
  }, success: tr('اتسجل ✓', 'Recorded ✓'));
}

class CenterFinanceScreen extends StatefulWidget {
  const CenterFinanceScreen({super.key, required this.centerId, required this.canFinance});
  final String centerId;
  final bool canFinance;
  @override
  State<CenterFinanceScreen> createState() => _CenterFinanceScreenState();
}

class _CenterFinanceScreenState extends State<CenterFinanceScreen> {
  String _period = 'today';
  DateTime _day = DateTime.now();
  int _key = 0;

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    return switch (_period) {
      'week' => (now.subtract(const Duration(days: 6)), now),
      'month' => (DateTime(now.year, now.month, 1), now),
      'day' => (_day, _day),
      _ => (now, now),
    };
  }

  Future<void> _expense() async {
    var cat = 'rent';
    final amount = TextEditingController();
    final reason = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, setS) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('مصروف على المركز', 'Center expense'), style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in expenseCategories)
                  ChoiceChip(label: Text('${expenseInfo(k).$1} ${expenseInfo(k).$2}'), selected: cat == k, onSelected: (_) => setS(() => cat = k)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: amount, autofocus: true, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: tr('المبلغ', 'Amount'), suffixText: tr('ج.م', 'EGP'))),
              TextField(controller: reason, decoration: InputDecoration(labelText: tr('السبب', 'Reason'))),
              const SizedBox(height: 12),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: Tone.red), onPressed: () => Navigator.pop(c, true),
                  child: Text(tr('حفظ', 'Save'))),
            ]),
          )),
    );
    final v = num.tryParse(amount.text.trim());
    if (go != true || v == null || v <= 0 || !mounted) return;
    final ok = await runBusy(context, () async => rpc('center_save_expense', {
          'p_center': widget.centerId, 'p_category': cat, 'p_amount': v, 'p_reason': reason.text.trim()}),
        success: tr('اتسجل ✓', 'Recorded ✓'));
    if (ok) setState(() => _key++);
  }

  Future<void> _delete(String type, Map<String, dynamic> it) async {
    final yes = await confirmDialog(context, title: tr('حذف؟', 'Delete?'), body: money(_n(it['amount'])), confirm: tr('حذف', 'Delete'), danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async => rpc('center_delete_entry', {'p_center': widget.centerId, 'p_type': type, 'p_id': it['id']}));
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range;
    return Scaffold(
      appBar: AppBar(title: Text(tr('حسابات المركز', 'Center accounts'))),
      floatingActionButton: Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.canFinance) ...[
          FloatingActionButton.extended(heroTag: 'exp', backgroundColor: Tone.red, foregroundColor: Colors.white,
              onPressed: _expense, icon: const Icon(Icons.remove), label: Text(tr('مصروف', 'Expense'))),
          const SizedBox(width: 10),
        ],
        FloatingActionButton.extended(heroTag: 'inc', backgroundColor: Tone.green, foregroundColor: Colors.white,
            onPressed: () async {
              if (await centerIncomeSheet(context, centerId: widget.centerId)) setState(() => _key++);
            },
            icon: const Icon(Icons.add), label: Text(tr('دخل حالة', 'Income'))),
      ]),
      body: FutureView<Map<String, dynamic>>(
        key: ValueKey('$_key$_period${_iso(_day)}'),
        load: () async => Map<String, dynamic>.from(
            await rpc('center_finance', {'p_center': widget.centerId, 'p_from': _iso(from), 'p_to': _iso(to)}) as Map),
        builder: (context, f, reload) {
          final fin = f['can_finance'] == true;
          final doctors = (f['doctors'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final income = (f['income_items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final exps = (f['expense_items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          return RefreshList(onRefresh: reload, padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'today', label: Text(tr('النهارده', 'Today'))),
                ButtonSegment(value: 'week', label: Text(tr('أسبوع', 'Week'))),
                ButtonSegment(value: 'month', label: Text(tr('الشهر', 'Month'))),
                ButtonSegment(value: 'day', label: Text(tr('يوم', 'Day')), icon: const Icon(Icons.event, size: 16)),
              ],
              selected: {_period},
              onSelectionChanged: (s) async {
                if (s.first == 'day') {
                  final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2024), lastDate: DateTime.now());
                  if (d == null) return;
                  _day = d;
                }
                setState(() => _period = s.first);
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Tone.indigo, Color(0xFF2E3A9E)]),
                  borderRadius: BorderRadius.circular(24)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fin ? tr('صافي المركز', 'Center net') : tr('دخل المركز', 'Center income'),
                    style: const TextStyle(color: Colors.white70)),
                FittedBox(child: Text(money(fin ? _n(f['net']) : _n(f['income'])),
                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900))),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _pill('💵 ${tr('الدخل', 'Income')}', money(_n(f['income']))),
                  _pill('👥 ${tr('الحالات', 'Cases')}', '${f['cases'] ?? 0}'),
                  if (fin) _pill('🩺 ${tr('نصيب الأطباء', 'Doctors')}', money(_n(f['doctor_shares']))),
                  if (fin) _pill('🏥 ${tr('نصيب المركز', 'Center')}', money(_n(f['center_share']))),
                  if (fin) _pill('🧾 ${tr('المصروفات', 'Expenses')}', money(_n(f['expenses']))),
                ]),
              ]),
            ),
            SectionTitle(tr('كل دكتور', 'Per doctor')),
            if (doctors.isEmpty) Text(tr('مفيش دخل متسجل في الفترة دي.', 'No income in this period.'), textAlign: TextAlign.center),
            for (final d in doctors)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    UserAvatar(url: d['avatar_url'] as String?, name: d['name'] as String?, radius: 22,
                        ring: specialtyLook(d['specialty_en'] as String?).accent),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${tr('د.', 'Dr.')} ${d['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text('${_specialty(d)} • ${d['cases']} ${tr('حالة', 'cases')}', style: const TextStyle(fontSize: 12.5)),
                      if (fin)
                        Text('${tr('نصيبه', 'His share')} ${money(_n(d['doctor_share']))} • ${tr('للمركز', 'Center')} ${money(_n(d['center_share']))}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ])),
                    Text(money(_n(d['income'])), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E7B45))),
                  ]),
                ),
              ),
            SectionTitle('${tr('الدخل', 'Income')} (${income.length})'),
            for (final i in income)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Text(incomeKindInfo(i['kind'] as String?).$1, style: const TextStyle(fontSize: 26)),
                  title: Text('${incomeKindInfo(i['kind'] as String?).$2} — ${tr('د.', 'Dr.')} ${i['doctor_name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([i['patient_name'], formatDate(i['paid_on'] as String?), if (i['by'] != null) '${tr('سجّله', 'by')} ${i['by']}']
                      .whereType<String>().where((s) => s.isNotEmpty).join(' • ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('+${money(_n(i['amount']))}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E7B45))),
                    if (fin) IconButton(onPressed: () => _delete('income', i), icon: const Icon(Icons.delete_outline, size: 20)),
                  ]),
                ),
              ),
            if (fin) ...[
              SectionTitle('${tr('مصروفات المركز', 'Center expenses')} (${exps.length})'),
              for (final e in exps)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: Text(expenseInfo(e['category'] as String?).$1, style: const TextStyle(fontSize: 26)),
                    title: Text(expenseInfo(e['category'] as String?).$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([e['reason'], formatDate(e['spent_on'] as String?)].whereType<String>().where((s) => s.isNotEmpty).join(' • ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('−${money(_n(e['amount']))}', style: const TextStyle(fontWeight: FontWeight.w900, color: Tone.red)),
                      IconButton(onPressed: () => _delete('expense', e), icon: const Icon(Icons.delete_outline, size: 20)),
                    ]),
                  ),
                ),
            ],
          ]);
        },
      ),
    );
  }

  Widget _pill(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
        child: Text('$label: $value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

// ===========================================================================
// Staff
// ===========================================================================
class CenterStaffScreen extends StatefulWidget {
  const CenterStaffScreen({super.key, required this.centerId});
  final String centerId;
  @override
  State<CenterStaffScreen> createState() => _CenterStaffScreenState();
}

class _CenterStaffScreenState extends State<CenterStaffScreen> {
  int _key = 0;

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final pw = TextEditingController(text: generatePassword());
    var role = 'reception';
    var fin = false;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, setS) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('موظف جديد', 'New staff'), style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'reception', label: Text(tr('استقبال', 'Reception'))),
                  ButtonSegment(value: 'manager', label: Text(tr('مدير', 'Manager'))),
                ],
                selected: {role},
                onSelectionChanged: (s) => setS(() => role = s.first),
              ),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: InputDecoration(labelText: tr('الاسم', 'Name'))),
              TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: tr('الموبايل (للدخول)', 'Mobile (login)'))),
              TextField(controller: pw, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: tr('كلمة السر', 'Password'))),
              if (role == 'reception')
                SwitchListTile(contentPadding: EdgeInsets.zero, value: fin, onChanged: (v) => setS(() => fin = v),
                    title: Text(tr('يشوف حسابات المركز كاملة', 'Full access to accounts')),
                    subtitle: Text(tr('من غيرها يسجل الدخل بس', 'Otherwise records income only'))),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('إضافة', 'Add'))),
            ])),
          )),
    );
    if (go != true || !mounted) return;
    if (normalizeEgPhone(phone.text) == null || pw.text.length < 8 || name.text.trim().length < 2) {
      showMessage(context, tr('اكتب الاسم ورقم موبايل صحيح وكلمة سر 8 حروف', 'Name, valid mobile and 8-char password'), error: true);
      return;
    }
    final ok = await runBusy(context, () async => rpc('center_add_staff', {
          'p_center': widget.centerId, 'p_full_name': name.text.trim(), 'p_phone': normalizeEgPhone(phone.text),
          'p_password': pw.text, 'p_role': role, 'p_can_finance': fin}));
    if (!ok || !mounted) return;
    final p = normalizeEgPhone(phone.text)!;
    await showCredentialsDialog(context, name: name.text.trim(), login: displayPhone(p), password: pw.text, phoneForWhatsApp: p);
    setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('موظفين المركز', 'Center staff'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add_rounded),
          label: Text(tr('موظف جديد', 'New staff'))),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => rpcList('center_staff', {'p_center': widget.centerId}),
        builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
          for (final s in list)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: UserAvatar(url: s['avatar_url'] as String?, name: s['name'] as String?, radius: 20),
                title: Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${centerRoleLabel(s['role'] as String?)} • ${displayPhone(s['phone'] as String?)}'
                    '${s['status'] == 'left' ? ' • ${tr('موقوف', 'disabled')}' : ''}'),
                trailing: s['role'] == 'owner'
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'password') {
                            final pw = generatePassword();
                            final ok = await runBusy(context, () async => rpc('center_reset_staff_password',
                                {'p_center': widget.centerId, 'p_user': s['user_id'], 'p_password': pw}));
                            if (ok && context.mounted) {
                              await showCredentialsDialog(context, name: s['name'] as String? ?? '',
                                  login: displayPhone(s['phone'] as String?), password: pw, phoneForWhatsApp: s['phone'] as String?);
                            }
                            return;
                          }
                          final ok = await runBusy(context, () async => rpc('center_update_staff', {
                                'p_center': widget.centerId, 'p_user': s['user_id'],
                                'p_can_finance': v == 'finance' ? s['can_finance'] != true : s['can_finance'] == true,
                                'p_active': v == 'toggle' ? s['status'] == 'left' : s['status'] != 'left'}));
                          if (ok) setState(() => _key++);
                        },
                        itemBuilder: (c) => [
                          PopupMenuItem(value: 'finance', child: Text(s['can_finance'] == true
                              ? tr('منع الحسابات الكاملة', 'Remove accounts access') : tr('السماح بالحسابات الكاملة', 'Allow accounts access'))),
                          PopupMenuItem(value: 'password', child: Text(tr('كلمة سر جديدة', 'New password'))),
                          PopupMenuItem(value: 'toggle', child: Text(s['status'] == 'left' ? tr('تفعيل', 'Enable') : tr('إيقاف', 'Disable'))),
                        ],
                      ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ===========================================================================
// Center info
// ===========================================================================
class CenterInfoScreen extends StatefulWidget {
  const CenterInfoScreen({super.key, required this.centerId});
  final String centerId;
  @override
  State<CenterInfoScreen> createState() => _CenterInfoScreenState();
}

class _CenterInfoScreenState extends State<CenterInfoScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _area = TextEditingController();
  Map<String, dynamic>? _c;
  late final Future<void> _loaded = () async {
    _c = Map<String, dynamic>.from(await supa.from('centers').select().eq('id', widget.centerId).single());
    _name.text = _c!['name'] as String? ?? '';
    _phone.text = _c!['phone'] as String? ?? '';
    _address.text = _c!['address'] as String? ?? '';
    _area.text = _c!['area'] as String? ?? '';
  }();

  Future<void> _save() async {
    final ok = await runBusy(context, () async => rpc('update_center', {
          'p_center': widget.centerId, 'p_name': _name.text.trim(), 'p_phone': _phone.text.trim(), 'p_address': _address.text.trim(),
          'p_governorate': _c?['governorate_id'], 'p_city': _c?['city_id'], 'p_area': _area.text.trim(),
          'p_lat': _c?['lat'], 'p_lng': _c?['lng'], 'p_logo_url': _c?['logo_url']}),
        success: tr('تم الحفظ ✓', 'Saved ✓'));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('بيانات المركز', 'Center info'))),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          return ListView(padding: const EdgeInsets.all(16), children: [
            TextField(controller: _name, decoration: InputDecoration(labelText: tr('اسم المركز', 'Center name'))),
            const SizedBox(height: 10),
            TextField(controller: _phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: tr('تليفون المركز', 'Phone'))),
            const SizedBox(height: 10),
            TextField(controller: _address, decoration: InputDecoration(labelText: tr('العنوان', 'Address'))),
            const SizedBox(height: 10),
            TextField(controller: _area, decoration: InputDecoration(labelText: tr('المنطقة', 'Area'))),
            const SizedBox(height: 10),
            InfoBanner(icon: Icons.info_outline, text: tr('الاسم والعنوان بيتحدثوا كمان في عيادة كل دكتور في المركز، وبيظهروا للمرضى في الحجز والروشتة.',
                'Name and address also update each doctor’s center clinic shown to patients.')),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: Text(tr('حفظ', 'Save'))),
          ]);
        },
      ),
    );
  }
}

// ===========================================================================
// Doctor side: my centers, invitations, earnings, open a center
// ===========================================================================
class DoctorCentersScreen extends StatefulWidget {
  const DoctorCentersScreen({super.key});
  @override
  State<DoctorCentersScreen> createState() => _DoctorCentersScreenState();
}

class _DoctorCentersScreenState extends State<DoctorCentersScreen> {
  int _key = 0;

  Future<void> _create() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('مركز طبي جديد', 'New medical center')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('اسم المركز', 'Center name'))),
          TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('تليفون المركز', 'Phone'))),
          TextField(controller: address, decoration: InputDecoration(labelText: tr('العنوان', 'Address'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('إنشاء', 'Create'))),
        ],
      ),
    );
    if (go != true || name.text.trim().length < 2 || !mounted) return;
    final ok = await runBusy(context, () async => rpc('create_center', {
          'p_name': name.text.trim(), 'p_phone': phone.text.trim(), 'p_address': address.text.trim()}),
        success: tr('المركز اتعمل ✓ ضيف الأطباء والموظفين', 'Center created ✓ — add doctors and staff'));
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(tr('المراكز الطبية', 'Medical centers'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_business_rounded),
          label: Text(tr('افتح مركز', 'Open a center'))),
      body: FutureView<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
        key: ValueKey(_key),
        load: () async {
          final r = await Future.wait([
            rpcList('my_centers'),
            rpcList('doctor_center_earnings', {'p_from': _iso(DateTime(now.year, now.month, 1)), 'p_to': _iso(now)}),
          ]);
          return (r[0], r[1]);
        },
        builder: (context, data, reload) {
          final (mine, earn) = data;
          final runs = mine.where((c) => c['role'] == 'owner' || c['role'] == 'manager').toList();
          final works = mine.where((c) => c['role'] == 'doctor').toList();
          return RefreshList(onRefresh: reload, children: [
            InfoBanner(icon: Icons.local_hospital_outlined,
                text: tr('لو بتشتغل في مركز فيه أكتر من دكتور، أو عندك مركز: السكرتارية تنظم حجوزات كل الأطباء، ويتحسب دخل كل دكتور ونسبته، والصافي النهائي للمركز.',
                    'Centers with several doctors: reception runs every doctor’s bookings, each doctor’s income and share are tracked, and the center sees its net.')),
            const SizedBox(height: 12),
            for (final c in works.where((c) => c['status'] == 'invited'))
              Card(
                color: lighten(Tone.orange, 0.85),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${tr('دعوة من', 'Invitation from')} ${c['name']}', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87)),
                    Text('${tr('نسبتك', 'Your share')} ${_pct.format(_n(c['share_percent']))}٪ • ${c['owner_name'] ?? ''}',
                        style: const TextStyle(color: Colors.black87)),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: () async {
                          if (await runBusy(context, () async => rpc('center_respond_invite', {'p_center': c['center_id'], 'p_accept': false}))) {
                            setState(() => _key++);
                          }
                        },
                        child: Text(tr('اعتذار', 'Decline')),
                      ),
                      FilledButton(
                        onPressed: () async {
                          if (await runBusy(context, () async => rpc('center_respond_invite', {'p_center': c['center_id'], 'p_accept': true}),
                              success: tr('انضميت للمركز ✓', 'Joined ✓'))) {
                            setState(() => _key++);
                          }
                        },
                        child: Text(tr('موافق', 'Accept')),
                      ),
                    ]),
                  ]),
                ),
              ),
            if (runs.isNotEmpty) SectionTitle(tr('مراكز بتديرها', 'Centers you run')),
            for (final c in runs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon3D(Icons.local_hospital_rounded, color: Tone.indigo, size: 44),
                  title: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${centerRoleLabel(c['role'] as String?)} • ${c['doctors']} ${tr('دكتور', 'doctors')}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CenterHome(
                      centerId: c['center_id'] as String, name: c['name'] as String? ?? '', role: c['role'] as String,
                      canFinance: true, standalone: false))),
                ),
              ),
            if (works.any((c) => c['status'] == 'active')) SectionTitle(tr('مراكز بتشتغل فيها', 'Centers you work in')),
            for (final c in works.where((c) => c['status'] == 'active'))
              Builder(builder: (context) {
                final e = earn.where((x) => x['center_id'] == c['center_id']).firstOrNull;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon3D(Icons.apartment_rounded, color: Tone.teal, size: 44),
                    title: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${tr('نسبتك', 'Your share')} ${_pct.format(_n(c['share_percent']))}٪'
                        '${e != null ? '\n${tr('الشهر ده', 'This month')}: ${e['cases']} ${tr('حالة', 'cases')} • ${tr('نصيبك', 'your share')} ${money(_n(e['my_share']))}' : ''}'),
                    isThreeLine: e != null,
                  ),
                );
              }),
            if (mine.isEmpty)
              EmptyView(icon: Icons.apartment_rounded, title: tr('مش منضم لأي مركز', 'No centers yet'),
                  subtitle: tr('افتح مركزك، أو استنى دعوة من مركز بتشتغل فيه.', 'Open your center or wait for an invitation.')),
          ]);
        },
      ),
    );
  }
}

/// When a staff account works for several centers, pick one.
class CenterPicker extends StatelessWidget {
  const CenterPicker({super.key, required this.centers});
  final List<Map<String, dynamic>> centers;
  @override
  Widget build(BuildContext context) {
    if (centers.length == 1) {
      final c = centers.first;
      return CenterHome(centerId: c['center_id'] as String, name: c['name'] as String? ?? '', role: c['role'] as String? ?? 'reception',
          canFinance: c['can_finance'] == true);
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('اختار المركز', 'Choose a center'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final c in centers)
          Card(
            child: ListTile(
              leading: const Icon3D(Icons.local_hospital_rounded, color: Tone.indigo, size: 44),
              title: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(centerRoleLabel(c['role'] as String?)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CenterHome(
                  centerId: c['center_id'] as String, name: c['name'] as String? ?? '', role: c['role'] as String? ?? 'reception',
                  canFinance: c['can_finance'] == true, standalone: false))),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.person), label: Text(tr('حسابي', 'My account'))),
      ]),
    );
  }
}

/// Admin: open a center whose owner is not a doctor (gets a phone login).
Future<void> adminCreateCenter(BuildContext context) async {
  final name = TextEditingController();
  final owner = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final pw = TextEditingController(text: generatePassword());
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('مركز طبي جديد', 'New medical center')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: tr('اسم المركز', 'Center name'))),
        TextField(controller: address, decoration: InputDecoration(labelText: tr('العنوان', 'Address'))),
        TextField(controller: owner, decoration: InputDecoration(labelText: tr('اسم صاحب المركز / المدير', 'Owner / manager name'))),
        TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: tr('موبايله (للدخول)', 'Mobile (login)'))),
        TextField(controller: pw, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: tr('كلمة السر', 'Password'))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('إنشاء', 'Create'))),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final p = normalizeEgPhone(phone.text);
  if (p == null || pw.text.length < 8 || name.text.trim().length < 2 || owner.text.trim().length < 2) {
    showMessage(context, tr('اكتب الاسم ورقم موبايل صحيح وكلمة سر 8 حروف', 'Name, valid mobile and 8-char password'), error: true);
    return;
  }
  final ok = await runBusy(context, () async => rpc('admin_create_center', {
        'p_name': name.text.trim(), 'p_owner_name': owner.text.trim(), 'p_owner_phone': p,
        'p_password': pw.text, 'p_address': address.text.trim()}));
  if (ok && context.mounted) {
    await showCredentialsDialog(context, name: owner.text.trim(), login: displayPhone(p), password: pw.text, phoneForWhatsApp: p);
  }
}
