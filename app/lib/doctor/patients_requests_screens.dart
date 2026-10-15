import 'package:flutter/material.dart';

import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'add_patient_screen.dart';
import 'patient_file_screen.dart';

class DoctorRequestsScreen extends StatelessWidget {
  const DoctorRequestsScreen({super.key});

  Future<void> _respond(BuildContext context, Map<String, dynamic> r, bool accept, Future<void> Function() reload) async {
    String? reason;
    if (!accept) {
      final ctl = TextEditingController();
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('رفض الطلب', 'Decline request')),
          content: TextField(controller: ctl, maxLines: 2,
              decoration: InputDecoration(labelText: tr('سبب الرفض (اختياري، يظهر للمريض)', 'Reason (optional, shown to patient)'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44), backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('رفض', 'Decline')),
            ),
          ],
        ),
      );
      if (go != true) return;
      reason = ctl.text.trim().isEmpty ? null : ctl.text.trim();
    }
    if (!context.mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('respond_join', {'p_request': r['request_id'], 'p_accept': accept, 'p_reason': reason});
    }, success: accept ? tr('تم قبول المريض', 'Patient accepted') : tr('تم رفض الطلب', 'Request declined'));
    if (ok) reload();
  }

  @override
  Widget build(BuildContext context) {
    final verified = actingDoctorStatus() == 'verified';
    return Scaffold(
      appBar: AppBar(title: Text(tr('طلبات الانضمام', 'Join requests'))),
      body: FutureView<List<Map<String, dynamic>>>(
        load: () => rpcList('doctor_incoming_requests', {'p_doctor': actingDoctorId()}),
        builder: (context, list, reload) => RefreshList(
          onRefresh: reload,
          children: [
            if (!verified)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InfoBanner(icon: Icons.hourglass_top, color: Colors.orange.shade800,
                    text: tr('هتقدر تستقبل طلبات بعد توثيق حسابك.', 'You can receive requests once your account is verified.')),
              ),
            if (list.isEmpty)
              EmptyView(icon: Icons.inbox_outlined, title: tr('لا توجد طلبات جديدة', 'No new requests')),
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        UserAvatar(url: r['avatar_url'] as String?, name: r['patient_name'] as String?, radius: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(r['patient_name'] ?? '',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text([
                        genderLabel(r['gender'] as String?),
                        if (r['age'] != null) tr('${r['age']} سنة', '${r['age']} yrs'),
                        if (r['clinic_name'] != null) r['clinic_name'] as String,
                        formatDate(r['created_at'] as String?),
                      ].where((s) => s.isNotEmpty).join(' · '), style: Theme.of(context).textTheme.bodySmall),
                      if ((r['message'] as String?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Text('«${r['message']}»', style: const TextStyle(height: 1.5)),
                      ],
                      const SizedBox(height: 6),
                      Text('${tr('المشاركة المطلوبة', 'Sharing')}: ${scopeLabel(r['share_scope'] as String?)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                            onPressed: verified ? () => _respond(context, r, true, reload) : null,
                            child: Text(tr('قبول', 'Accept')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                            onPressed: verified ? () => _respond(context, r, false, reload) : null,
                            child: Text(tr('رفض', 'Decline')),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({super.key});
  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  String _filter = '';
  int _key = 0;

  Future<void> _add() async {
    if (actingDoctorStatus() != 'verified') {
      showMessage(context, tr('هتقدر تضيف مرضى بعد توثيق حسابك.', 'You can add patients once your account is verified.'), error: true);
      return;
    }
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddPatientScreen()));
    if (added == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('مرضاي', 'My patients'))),
      floatingActionButton: !can('add_patients') ? null : FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: Text(tr('إضافة مريض', 'Add patient')),
      ),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => rpcList('doctor_my_patients', {'p_doctor': actingDoctorId()}),
        builder: (context, all, reload) {
          final list = _filter.isEmpty
              ? all
              : all.where((p) => (p['patient_name'] as String? ?? '').contains(_filter)
                  || displayPhone(p['phone'] as String?).contains(_filter)).toList();
          return RefreshList(onRefresh: reload, children: [
            TextField(
              decoration: InputDecoration(hintText: tr('بحث بالاسم أو الموبايل', 'Search by name or mobile'), prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _filter = v.trim()),
            ),
            const SizedBox(height: 12),
            if (all.isEmpty)
              EmptyView(icon: Icons.people_outline, title: tr('لا يوجد مرضى بعد', 'No patients yet'),
                  subtitle: tr('المرضى يظهرون هنا بعد قبول طلبات انضمامهم.', 'Patients appear here after you accept their requests.')),
            for (final p in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: UserAvatar(url: p['avatar_url'] as String?, name: p['patient_name'] as String?, radius: 24),
                    title: Text(p['patient_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      genderLabel(p['gender'] as String?),
                      if (p['age'] != null) tr('${p['age']} سنة', '${p['age']} yrs'),
                      displayPhone(p['phone'] as String?),
                      '${tr('منذ', 'Since')} ${formatDate(p['started_at'] as String?)}',
                    ].where((s) => s.isNotEmpty).join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => PatientFileScreen(patient: p)));
                      reload();
                    },
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
