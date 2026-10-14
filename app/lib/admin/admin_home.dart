import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/settings_screen.dart';
import '../core/l10n.dart';
import '../core/lookups.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Phase-1 admin tools inside the app: stats, doctor verification, platform settings.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Stats(goToDoctors: () => setState(() => _tab = 1)),
      const _Doctors(),
      const _PlatformSettings(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights),
              label: tr('الإحصائيات', 'Stats')),
          NavigationDestination(icon: const Icon(Icons.verified_user_outlined), selectedIcon: const Icon(Icons.verified_user),
              label: tr('الأطباء', 'Doctors')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings),
              label: tr('الإعدادات', 'Settings')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person),
              label: tr('حسابي', 'Account')),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.goToDoctors});
  final VoidCallback goToDoctors;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('لوحة الإدارة', 'Admin dashboard'))),
      body: FutureView<Map<String, dynamic>>(
        load: () async => Map<String, dynamic>.from(await rpc('admin_stats') as Map),
        builder: (context, s, reload) {
          Widget tile(IconData i, String label, Object? v, {VoidCallback? onTap, Color? color}) => Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(i, color: color ?? Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text('${v ?? 0}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(label),
                    ]),
                  ),
                ),
              );
          return RefreshList(onRefresh: reload, children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                tile(Icons.hourglass_top, tr('أطباء بانتظار التوثيق', 'Doctors awaiting review'), s['doctors_pending'],
                    onTap: goToDoctors, color: Colors.orange.shade800),
                tile(Icons.verified, tr('أطباء موثّقون', 'Verified doctors'), s['doctors_verified'], color: Colors.green.shade700),
                tile(Icons.people, tr('المرضى', 'Patients'), s['patients']),
                tile(Icons.link, tr('متابعات نشطة', 'Active care links'), s['active_links']),
                tile(Icons.inbox, tr('طلبات انضمام معلقة', 'Pending join requests'), s['pending_requests']),
              ],
            ),
          ]);
        },
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
