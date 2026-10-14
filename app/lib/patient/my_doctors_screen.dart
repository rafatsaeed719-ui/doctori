import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'doctor_details_screen.dart';

class MyDoctorsScreen extends StatelessWidget {
  const MyDoctorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('أطبائي', 'My doctors'))),
      body: FutureView<List<Map<String, dynamic>>>(
        load: () => rpcList('patient_my_doctors'),
        builder: (context, docs, reload) => RefreshList(
          onRefresh: reload,
          children: docs.isEmpty
              ? [
                  EmptyView(
                    icon: Icons.medical_services_outlined,
                    title: tr('لم تنضم لأي عيادة بعد', 'You haven’t joined any clinic yet'),
                    subtitle: tr('ابحث عن طبيبك من تبويب البحث وأرسل طلب انضمام.', 'Find your doctor in Search and send a join request.'),
                  ),
                ]
              : [
                  for (final d in docs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(child: Text((d['doctor_name'] as String? ?? '?').characters.first)),
                          title: Text('${tr('د.', 'Dr.')} ${d['doctor_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${trField(d, 'specialty')}\n${tr('المشاركة', 'Sharing')}: ${scopeLabel(d['scope'] as String?)}'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.more_vert),
                          onTap: () => _actions(context, d, reload),
                        ),
                      ),
                    ),
                ],
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context, Map<String, dynamic> d, Future<void> Function() reload) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.person), title: Text(tr('ملف الطبيب', 'Doctor profile')),
              onTap: () => Navigator.pop(c, 'profile')),
          ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(tr('تغيير ما يراه الطبيب', 'Change what the doctor sees')),
              onTap: () => Navigator.pop(c, 'scope')),
          ListTile(
            leading: Icon(Icons.link_off, color: Theme.of(c).colorScheme.error),
            title: Text(tr('إلغاء الارتباط بالطبيب', 'Unlink from this doctor'),
                style: TextStyle(color: Theme.of(c).colorScheme.error)),
            onTap: () => Navigator.pop(c, 'end'),
          ),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'profile':
        Navigator.push(context, MaterialPageRoute(builder: (_) => DoctorDetailsScreen(doctorId: d['doctor_id'] as String)));
      case 'scope':
        final current = d['scope'] as String? ?? 'full';
        final next = current == 'full' ? 'own_uploads' : 'full';
        final yes = await confirmDialog(context,
            title: tr('تغيير المشاركة', 'Change sharing'),
            body: tr('المشاركة الحالية: ${scopeLabel(current)}\nالجديدة: ${scopeLabel(next)}',
                'Current: ${scopeLabel(current)}\nNew: ${scopeLabel(next)}'),
            confirm: tr('تغيير', 'Change'));
        if (yes && context.mounted) {
          final ok = await runBusy(context, () async {
            await rpc('set_consent_scope', {'p_link': d['link_id'], 'p_scope': next});
          }, success: tr('تم تحديث المشاركة', 'Sharing updated'));
          if (ok) reload();
        }
      case 'end':
        final yes = await confirmDialog(context,
            title: tr('إلغاء الارتباط؟', 'Unlink?'),
            body: tr('الطبيب هيفقد الوصول لملفك فوراً. هيفضل محتفظ فقط بالملاحظات اللي كتبها هو كسجل مهني. تقدر ترجع تبعت طلب انضمام بعدين.',
                'The doctor loses access to your file immediately and keeps only the notes they wrote, as their professional record. You can request to join again later.'),
            confirm: tr('إلغاء الارتباط', 'Unlink'),
            danger: true);
        if (yes && context.mounted) {
          final ok = await runBusy(context, () async {
            await rpc('end_care_link', {'p_link': d['link_id']});
          }, success: tr('تم إلغاء الارتباط', 'Unlinked'));
          if (ok) reload();
        }
    }
  }
}
