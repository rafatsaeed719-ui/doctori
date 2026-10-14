import 'package:flutter/material.dart';

import '../common/settings_screen.dart';
import '../core/l10n.dart';
import '../core/lookups.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'clinics_screen.dart';
import 'doctor_profile_screen.dart';
import 'patients_requests_screens.dart';
import 'verification_screen.dart';

class DoctorHome extends StatefulWidget {
  const DoctorHome({super.key, required this.onContextChanged});
  final VoidCallback onContextChanged;
  @override
  State<DoctorHome> createState() => _DoctorHomeState();
}

class _DoctorHomeState extends State<DoctorHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Dashboard(goTo: (i) => setState(() => _tab = i)),
      const DoctorRequestsScreen(),
      const DoctorPatientsScreen(),
      const ClinicsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard),
              label: tr('الرئيسية', 'Home')),
          NavigationDestination(icon: const Icon(Icons.inbox_outlined), selectedIcon: const Icon(Icons.inbox),
              label: tr('الطلبات', 'Requests')),
          NavigationDestination(icon: const Icon(Icons.people_outline), selectedIcon: const Icon(Icons.people),
              label: tr('مرضاي', 'Patients')),
          NavigationDestination(icon: const Icon(Icons.local_hospital_outlined), selectedIcon: const Icon(Icons.local_hospital),
              label: tr('عياداتي', 'Clinics')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person),
              label: tr('حسابي', 'Account')),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.goTo});
  final void Function(int) goTo;

  Future<Map<String, dynamic>> _load() async {
    final doc = await supa.from('doctors').select().eq('id', myId).single();
    final clinics = await supa.from('clinics').select('id').eq('doctor_id', myId);
    final verifs = await supa.from('doctor_verifications').select('id, decision').eq('doctor_id', myId);
    final requests = await rpcList('doctor_incoming_requests');
    final patients = await rpcList('doctor_my_patients');
    return {
      'doctor': doc,
      'clinics': clinics.length,
      'submitted': verifs.isNotEmpty,
      'awaiting_review': verifs.any((v) => v['decision'] == null),
      'requests': requests.length,
      'patients': patients.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(AppState.context['full_name'] != null
          ? '${tr('د.', 'Dr.')} ${AppState.context['full_name']}'
          : tr('لوحة الطبيب', 'Doctor dashboard'))),
      body: FutureView<Map<String, dynamic>>(
        load: _load,
        builder: (context, data, reload) {
          final doc = Map<String, dynamic>.from(data['doctor'] as Map);
          final status = doc['status'] as String;
          final profileDone = doc['specialty_id'] != null && (doc['license_number'] as String?)?.isNotEmpty == true;
          final clinics = data['clinics'] as int;
          final submitted = data['submitted'] as bool;
          return RefreshList(onRefresh: reload, children: [
            _statusBanner(context, status, data['awaiting_review'] as bool),
            if (status != 'verified') ...[
              SectionTitle(tr('خطوات تفعيل حسابك', 'Steps to activate your account')),
              _step(context, 1, tr('أكمل بياناتك المهنية (التخصص ورقم الترخيص)', 'Complete your professional info (specialty, licence)'),
                  profileDone, () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorProfileScreen()));
                reload();
              }),
              _step(context, 2, tr('أضف عيادة واحدة على الأقل وحدد موقعها', 'Add at least one clinic with its location'),
                  clinics > 0, () => goTo(3)),
              _step(context, 3, tr('ارفع مستندات الترخيص للمراجعة', 'Upload licence documents for review'),
                  submitted, () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen()));
                reload();
              }),
            ],
            SectionTitle(tr('نظرة سريعة', 'Overview')),
            Row(children: [
              Expanded(child: _stat(context, Icons.inbox, '${data['requests']}', tr('طلبات جديدة', 'New requests'), () => goTo(1))),
              const SizedBox(width: 12),
              Expanded(child: _stat(context, Icons.people, '${data['patients']}', tr('مرضى', 'Patients'), () => goTo(2))),
              const SizedBox(width: 12),
              Expanded(child: _stat(context, Icons.local_hospital, '$clinics', tr('عيادات', 'Clinics'), () => goTo(3))),
            ]),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile(
                value: doc['accepting_new'] == true,
                title: Text(tr('أستقبل مرضى جدد', 'Accepting new patients')),
                subtitle: Text(tr('لو قفلتها، المرضى يقدروا يشوفوك لكن مش هيقدروا يبعتوا طلب انضمام.',
                    'When off, patients can see you but cannot send join requests.')),
                onChanged: (v) async {
                  final ok = await runBusy(context, () async {
                    await supa.from('doctors').update({'accepting_new': v}).eq('id', myId);
                  });
                  if (ok) reload();
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(Icons.badge_outlined, color: cs.primary),
                title: Text(tr('بياناتي المهنية', 'Professional profile')),
                subtitle: Text(Lookups.specialtyName(doc['specialty_id'] as int?)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorProfileScreen()));
                  reload();
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(Icons.verified_outlined, color: cs.primary),
                title: Text(tr('مستندات التوثيق', 'Verification documents')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen()));
                  reload();
                },
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _statusBanner(BuildContext context, String status, bool awaiting) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      'verified' => InfoBanner(icon: Icons.verified, color: Colors.green.shade700,
          text: tr('حسابك موثّق ويظهر للمرضى في البحث.', 'Your account is verified and visible to patients.')),
      'rejected' => InfoBanner(icon: Icons.error_outline, color: cs.error,
          text: tr('لم تتم الموافقة على التوثيق. راجع ملاحظات الإدارة في شاشة المستندات وأعد الإرسال.',
              'Verification was declined. Check the admin notes in Documents and resubmit.')),
      'suspended' => InfoBanner(icon: Icons.block, color: cs.error,
          text: tr('حسابك المهني معلّق حالياً. تواصل مع إدارة المنصة.', 'Your professional account is suspended. Contact the platform.')),
      _ => InfoBanner(icon: Icons.hourglass_top, color: Colors.orange.shade800,
          text: awaiting
              ? tr('مستنداتك قيد المراجعة. هيظهر حسابك للمرضى بعد التوثيق.', 'Your documents are under review. You will appear to patients after verification.')
              : tr('حسابك لا يظهر للمرضى بعد. أكمل الخطوات بالأسفل.', 'You are not visible to patients yet. Complete the steps below.')),
    };
  }

  Widget _step(BuildContext context, int n, String text, bool done, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: done ? Colors.green.shade700 : cs.primaryContainer,
            child: done ? const Icon(Icons.check, color: Colors.white) : Text('$n'),
          ),
          title: Text(text),
          trailing: done ? null : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String value, String label, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(children: [
            Icon(icon, color: cs.primary),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
