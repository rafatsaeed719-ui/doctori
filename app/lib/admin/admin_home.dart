import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/settings_screen.dart';
import '../core/avatar.dart';
import '../core/backgrounds.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/lookups.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'users_screens.dart';

/// Phase-1 admin tools inside the app: stats, doctor verification, platform settings.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Stats(goTo: _go),
      const AdminUsersScreen(),
      const _Doctors(),
      const _PlatformSettings(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.space_dashboard_outlined),
              selectedIcon: navIcon3D(Icons.space_dashboard_rounded, Tone.indigo), label: tr('اللوحة', 'Dashboard')),
          NavigationDestination(icon: const Icon(Icons.people_outline),
              selectedIcon: navIcon3D(Icons.people_rounded, Tone.blue), label: tr('المستخدمين', 'Users')),
          NavigationDestination(icon: const Icon(Icons.verified_user_outlined),
              selectedIcon: navIcon3D(Icons.verified_user_rounded, Tone.green), label: tr('التوثيق', 'Verify')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined),
              selectedIcon: navIcon3D(Icons.settings_rounded, Tone.purple), label: tr('الإعدادات', 'Settings')),
          NavigationDestination(icon: const Icon(Icons.person_outline),
              selectedIcon: navIcon3D(Icons.person_rounded, Tone.pink), label: tr('حسابي', 'Account')),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.goTo});
  final void Function(int) goTo;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PatternBackground(
        look: adminLook,
        child: SafeArea(
          child: FutureView<Map<String, dynamic>>(
            load: () async => Map<String, dynamic>.from(await rpc('admin_stats') as Map),
            builder: (context, s, reload) {
              Widget stat(IconData i, Color c, String label, Object? v, {VoidCallback? onTap}) => GestureDetector(
                    onTap: onTap,
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Icon3D(i, color: c, size: 46),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${v ?? 0}',
                                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: darken(c, 0.15))),
                            Text(label, maxLines: 2, style: const TextStyle(fontSize: 12.5, height: 1.3)),
                          ]),
                        ),
                      ]),
                    ),
                  );
              return RefreshList(
                onRefresh: reload,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [lighten(Tone.indigo, 0.1), darken(Tone.indigo, 0.25)],
                      ),
                      boxShadow: [BoxShadow(color: Tone.indigo.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
                    ),
                    child: ValueListenableBuilder<Map<String, dynamic>>(
                      valueListenable: AppState.ctx,
                      builder: (context, ctx, _) => Row(children: [
                        GestureDetector(
                          onTap: () => changeMyAvatar(context),
                          child: UserAvatar(url: ctx['avatar_url'] as String?, name: ctx['full_name'] as String?,
                              radius: 30, ring: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr('لوحة الإدارة', 'Admin dashboard'),
                                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                            Text(ctx['full_name'] as String? ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: tt.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                            ValueListenableBuilder<String>(
                              valueListenable: AppState.appName,
                              builder: (_, n, __) => Text('${tr('منصة', 'Platform')} $n',
                                  style: const TextStyle(color: Colors.white70)),
                            ),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                          child: Image.asset('assets/logo.png', width: 38, height: 38),
                        ),
                      ]),
                    ),
                  ),
                  SectionTitle(tr('نظرة عامة', 'Overview')),
                  LayoutBuilder(builder: (context, c) {
                    final w = (c.maxWidth - 12) / 2;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(width: w, child: stat(Icons.hourglass_top_rounded, Tone.orange,
                          tr('أطباء بانتظار التوثيق', 'Awaiting review'), s['doctors_pending'], onTap: () => goTo(2))),
                      SizedBox(width: w, child: stat(Icons.verified_rounded, Tone.green,
                          tr('أطباء موثّقون', 'Verified doctors'), s['doctors_verified'], onTap: () => goTo(1))),
                      SizedBox(width: w, child: stat(Icons.people_alt_rounded, Tone.blue,
                          tr('المرضى', 'Patients'), s['patients'], onTap: () => goTo(1))),
                      SizedBox(width: w, child: stat(Icons.link_rounded, Tone.teal,
                          tr('متابعات نشطة', 'Active care links'), s['active_links'])),
                      SizedBox(width: w, child: stat(Icons.inbox_rounded, Tone.pink,
                          tr('طلبات انضمام معلقة', 'Pending requests'), s['pending_requests'])),
                    ]);
                  }),
                  SectionTitle(tr('إجراءات سريعة', 'Quick actions')),
                  TileGrid(children: [
                    Tile3D(icon: Icons.person_add_alt_1_rounded, color: Tone.green, label: tr('إضافة حساب', 'Add account'),
                        subtitle: tr('دكتور أو مريض أو مدير', 'Doctor, patient or admin'),
                        onTap: () async {
                          final added = await Navigator.push<bool>(
                              context, MaterialPageRoute(builder: (_) => const AdminCreateUserScreen()));
                          if (added == true) reload();
                        }),
                    Tile3D(icon: Icons.people_rounded, color: Tone.blue, label: tr('المستخدمين', 'Users'),
                        subtitle: tr('بحث وتعديل وحذف', 'Search, edit, delete'), onTap: () => goTo(1)),
                    Tile3D(icon: Icons.verified_user_rounded, color: Tone.orange, label: tr('توثيق الأطباء', 'Verify doctors'),
                        badge: (s['doctors_pending'] as num?)?.toInt(), onTap: () => goTo(2)),
                    Tile3D(icon: Icons.category_rounded, color: Tone.purple, label: tr('التخصصات والإعدادات', 'Specialties & settings'),
                        onTap: () => goTo(3)),
                  ]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Doctors extends StatefulWidget {
  const _Doctors();
  @override
  State<_Doctors> createState() => _DoctorsState();
}

class _DoctorsState extends State<_Doctors> {
  String? _status = 'pending';
  int _key = 0;

  static String statusLabel(String? s) => switch (s) {
        'pending' => tr('بانتظار التوثيق', 'Pending'),
        'verified' => tr('موثّق', 'Verified'),
        'rejected' => tr('مرفوض', 'Rejected'),
        'suspended' => tr('معلّق', 'Suspended'),
        _ => tr('الكل', 'All'),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('توثيق الأطباء', 'Doctor verification'))),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final s in ['pending', 'verified', 'rejected', 'suspended', null])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(statusLabel(s)),
                  selected: _status == s,
                  onSelected: (_) => setState(() {
                    _status = s;
                    _key++;
                  }),
                ),
              ),
          ]),
        ),
        Expanded(
          child: FutureView<List<Map<String, dynamic>>>(
            key: ValueKey('$_status-$_key'),
            load: () async {
              final res = await rpc('admin_list_doctors', {'p_status': _status});
              return (res as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            },
            builder: (context, list, reload) => RefreshList(
              onRefresh: reload,
              children: list.isEmpty
                  ? [EmptyView(icon: Icons.inbox_outlined, title: tr('لا يوجد أطباء في هذه القائمة', 'No doctors here'))]
                  : [
                      for (final d in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: ListTile(
                              title: Text(d['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([
                                d['specialty_ar'] ?? tr('بدون تخصص', 'No specialty'),
                                '${tr('ترخيص', 'Licence')}: ${d['license_number'] ?? '-'}',
                                '${(d['documents'] as List?)?.length ?? 0} ${tr('مستند', 'docs')} · ${d['clinics_count']} ${tr('عيادة', 'clinics')}',
                              ].join('\n')),
                              isThreeLine: true,
                              trailing: StatusChip(statusLabel(d['status'] as String?),
                                  color: d['status'] == 'verified' ? Colors.green.shade700 : Colors.orange.shade800),
                              onTap: () async {
                                final changed = await Navigator.push<bool>(
                                    context, MaterialPageRoute(builder: (_) => _DoctorReview(d: d)));
                                if (changed == true) reload();
                              },
                            ),
                          ),
                        ),
                    ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _DoctorReview extends StatelessWidget {
  const _DoctorReview({required this.d});
  final Map<String, dynamic> d;

  Future<void> _openDoc(BuildContext context, String path) async {
    try {
      final url = await supa.storage.from('verification-docs').createSignedUrl(path, 300);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _decide(BuildContext context, String decision) async {
    final notes = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(switch (decision) {
          'verified' => tr('توثيق الطبيب', 'Verify doctor'),
          'rejected' => tr('رفض التوثيق', 'Reject verification'),
          _ => tr('تعليق الحساب المهني', 'Suspend professional account'),
        }),
        content: TextField(controller: notes, maxLines: 3,
            decoration: InputDecoration(labelText: decision == 'verified'
                ? tr('ملاحظات (اختياري)', 'Notes (optional)')
                : tr('السبب (يظهر للطبيب)', 'Reason (shown to the doctor)'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(c, true), child: Text(tr('تأكيد', 'Confirm'))),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('admin_review_doctor', {
        'p_doctor': d['id'],
        'p_decision': decision,
        'p_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
    }, success: tr('تم الحفظ وتسجيل العملية', 'Saved and logged'));
    if (ok && context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final docs = (d['documents'] as List? ?? const []).cast<String>();
    final cs = Theme.of(context).colorScheme;
    Widget row(String k, Object? v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
            Expanded(child: Text('${v ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(d['full_name'] ?? '')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              row(tr('الإيميل', 'Email'), d['email']),
              row(tr('التخصص', 'Specialty'), d['specialty_ar']),
              row(tr('اللقب', 'Title'), d['title']),
              row(tr('رقم الترخيص', 'Licence no.'), d['license_number']),
              row(tr('الخبرة', 'Experience'), d['years_experience']),
              row(tr('المؤهلات', 'Qualifications'), d['qualifications']),
              row(tr('العيادات', 'Clinics'), d['clinics_count']),
              row(tr('ملاحظة الطبيب', 'Doctor note'), d['note']),
              row(tr('الحالة', 'Status'), _DoctorsState.statusLabel(d['status'] as String?)),
            ]),
          ),
        ),
        SectionTitle(tr('المستندات', 'Documents')),
        if (docs.isEmpty) Text(tr('لم يرفع الطبيب مستندات بعد.', 'No documents uploaded yet.')),
        for (final p in docs)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(p.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image, color: cs.primary),
              title: Text(p.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(tr('يفتح برابط مؤقت لمدة 5 دقائق', 'Opens with a 5-minute link')),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openDoc(context, p),
            ),
          ),
        const SizedBox(height: 16),
        InfoBanner(icon: Icons.fact_check_outlined,
            text: tr('تأكد من مطابقة الاسم ورقم الترخيص مع المستندات قبل التوثيق. كل قرار يُسجّل في سجل التدقيق.',
                'Match the name and licence number with the documents before verifying. Every decision is audit-logged.')),
        const SizedBox(height: 16),
        if (d['status'] != 'verified')
          FilledButton.icon(onPressed: () => _decide(context, 'verified'), icon: const Icon(Icons.verified),
              label: Text(tr('توثيق الطبيب', 'Verify doctor'))),
        const SizedBox(height: 10),
        if (d['status'] == 'pending')
          OutlinedButton.icon(onPressed: () => _decide(context, 'rejected'), icon: const Icon(Icons.close),
              label: Text(tr('رفض التوثيق', 'Reject'))),
        if (d['status'] == 'verified')
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            onPressed: () => _decide(context, 'suspended'),
            icon: const Icon(Icons.block),
            label: Text(tr('تعليق الحساب المهني', 'Suspend professional account')),
          ),
      ]),
    );
  }
}

class _PlatformSettings extends StatefulWidget {
  const _PlatformSettings();
  @override
  State<_PlatformSettings> createState() => _PlatformSettingsState();
}

class _PlatformSettingsState extends State<_PlatformSettings> {
  int _key = 0;

  Future<void> _editAppName(Map<String, dynamic>? current) async {
    final ar = TextEditingController(text: current?['ar'] as String? ?? 'دكتوري');
    final en = TextEditingController(text: current?['en'] as String? ?? 'Doctori');
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('اسم التطبيق', 'App name')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ar, decoration: InputDecoration(labelText: tr('بالعربي', 'Arabic'))),
          const SizedBox(height: 12),
          TextField(controller: en, decoration: InputDecoration(labelText: tr('بالإنجليزي', 'English'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ', 'Save'))),
        ],
      ),
    );
    if (go != true || !mounted) return;
    if (ar.text.trim().isEmpty || en.text.trim().isEmpty) {
      showMessage(context, tr('الاسم مطلوب باللغتين', 'Name is required in both languages'), error: true);
      return;
    }
    final ok = await runBusy(context, () async {
      await supa.from('app_settings')
          .update({'value': {'ar': ar.text.trim(), 'en': en.text.trim()}, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('key', 'app_name');
      await AppState.loadAppName();
    }, success: tr('تم تحديث اسم التطبيق', 'App name updated'));
    if (ok) setState(() => _key++);
  }

  Future<void> _addSpecialty() async {
    final ar = TextEditingController();
    final en = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('تخصص جديد', 'New specialty')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ar, decoration: InputDecoration(labelText: tr('الاسم بالعربي', 'Arabic name'))),
          const SizedBox(height: 12),
          TextField(controller: en, decoration: InputDecoration(labelText: tr('الاسم بالإنجليزي', 'English name'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(c, true), child: Text(tr('إضافة', 'Add'))),
        ],
      ),
    );
    if (go != true || !mounted) return;
    if (ar.text.trim().isEmpty || en.text.trim().isEmpty) {
      showMessage(context, tr('الاسم مطلوب باللغتين', 'Name is required in both languages'), error: true);
      return;
    }
    final ok = await runBusy(context, () async {
      await supa.from('specialties').insert({'name_ar': ar.text.trim(), 'name_en': en.text.trim(), 'sort_order': 100});
      await Lookups.ensure(force: true);
    }, success: tr('تمت الإضافة', 'Added'));
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('إعدادات المنصة', 'Platform settings'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSpecialty,
        icon: const Icon(Icons.add),
        label: Text(tr('تخصص جديد', 'New specialty')),
      ),
      body: FutureView<(Map<String, dynamic>?, List<Map<String, dynamic>>)>(
        key: ValueKey(_key),
        load: () async {
          final name = await supa.from('app_settings').select('value').eq('key', 'app_name').maybeSingle();
          final specs = await supa.from('specialties').select().order('sort_order');
          final v = name?['value'];
          return (v is Map ? Map<String, dynamic>.from(v) : null, specs);
        },
        builder: (context, data, reload) {
          final (appName, specs) = data;
          return RefreshList(onRefresh: reload, children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(tr('اسم التطبيق', 'App name')),
                subtitle: Text('${appName?['ar'] ?? 'دكتوري'} / ${appName?['en'] ?? 'Doctori'}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editAppName(appName),
              ),
            ),
            SectionTitle(tr('التخصصات الطبية', 'Medical specialties')),
            for (final s in specs)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: SwitchListTile(
                  title: Text('${s['name_ar']} · ${s['name_en']}'),
                  value: s['is_active'] == true,
                  onChanged: (v) async {
                    final ok = await runBusy(context, () async {
                      await supa.from('specialties').update({'is_active': v}).eq('id', s['id']);
                      await Lookups.ensure(force: true);
                    });
                    if (ok) reload();
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}
