import 'package:flutter/material.dart';

import '../common/announcements.dart';
import '../common/offers_screens.dart';
import '../common/settings_screen.dart';
import '../core/avatar.dart';
import '../core/backgrounds.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'activation_card.dart';
import 'add_patient_screen.dart';
import 'assistants_screen.dart';
import 'bookings_screen.dart';
import 'clinics_screen.dart';
import 'doctor_profile_screen.dart';
import 'finance_screen.dart';
import 'med_reviews_screen.dart';
import 'rx_screens.dart';
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

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: AppState.ctx,
      builder: (context, ctx, _) {
        final accent = specialtyLook(ctx['specialty_en'] as String?).accent;
        final pages = [
          _Dashboard(goTo: _go),
          const DoctorRequestsScreen(),
          const DoctorPatientsScreen(),
          const ClinicsScreen(),
          const SettingsScreen(),
        ];
        return Scaffold(
          body: pages[_tab],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _go,
            destinations: [
              NavigationDestination(icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: navIcon3D(Icons.dashboard_rounded, accent), label: tr('الرئيسية', 'Home')),
              NavigationDestination(icon: const Icon(Icons.inbox_outlined),
                  selectedIcon: navIcon3D(Icons.inbox_rounded, Tone.orange), label: tr('الطلبات', 'Requests')),
              NavigationDestination(icon: const Icon(Icons.people_outline),
                  selectedIcon: navIcon3D(Icons.people_rounded, Tone.teal), label: tr('مرضاي', 'Patients')),
              NavigationDestination(icon: const Icon(Icons.local_hospital_outlined),
                  selectedIcon: navIcon3D(Icons.local_hospital_rounded, Tone.blue), label: tr('عياداتي', 'Clinics')),
              NavigationDestination(icon: const Icon(Icons.person_outline),
                  selectedIcon: navIcon3D(Icons.person_rounded, Tone.pink), label: tr('حسابي', 'Account')),
            ],
          ),
        );
      },
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
    var reviews = 0;
    try {
      reviews = (await rpcList('doctor_pending_med_reviews')).length;
    } catch (_) {/* older server: no reviews yet */}
    return {
      'reviews': reviews,
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
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: AppState.ctx,
      builder: (context, ctx, _) {
        final look = specialtyLook(ctx['specialty_en'] as String?);
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: PatternBackground(
            look: look,
            child: SafeArea(
              child: FutureView<Map<String, dynamic>>(
                load: _load,
                builder: (context, data, reload) => _body(context, ctx, look, data, reload),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> ctx, SpecialtyLook look, Map<String, dynamic> data,
      Future<void> Function() reload) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final doc = Map<String, dynamic>.from(data['doctor'] as Map);
    final status = doc['status'] as String;
    final verified = status == 'verified';
    final profileDone = doc['specialty_id'] != null && (doc['license_number'] as String?)?.isNotEmpty == true;
    final clinics = data['clinics'] as int;
    final specialty = L10n.isAr ? ctx['specialty_ar'] : (ctx['specialty_en'] ?? ctx['specialty_ar']);

    Future<void> openProfile() async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorProfileScreen()));
      await refreshMyContext();
      reload();
    }

    Future<void> openVerification() async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const VerificationScreen()));
      reload();
    }

    return RefreshList(
      onRefresh: reload,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            GestureDetector(
              onTap: () => changeMyAvatar(context),
              child: Stack(clipBehavior: Clip.none, children: [
                UserAvatar(url: ctx['avatar_url'] as String?, name: ctx['full_name'] as String?, radius: 34, ring: look.accent),
                PositionedDirectional(
                  bottom: -2,
                  end: -2,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: look.accent,
                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('أهلاً دكتور 👋', 'Welcome, doctor 👋'), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                Text('${tr('د.', 'Dr.')} ${ctx['full_name'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (specialty != null)
                    StatusChip('${look.emojis.first} $specialty', color: darken(look.accent, 0.1)),
                  StatusChip(
                    verified ? tr('موثّق ✓', 'Verified ✓') : tr('بانتظار التوثيق', 'Pending'),
                    color: verified ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                ]),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        const AnnouncementsStrip(),
        if (!verified) ...[
          _statusBanner(context, status, data['awaiting_review'] as bool),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              _step(context, 1, tr('أكمل بياناتك المهنية (التخصص ورقم الترخيص)', 'Complete your professional info'),
                  profileDone, openProfile),
              _step(context, 2, tr('أضف عيادة وحدد موقعها', 'Add a clinic with its location'), clinics > 0, () => goTo(3)),
              _step(context, 3, tr('فعّل حسابك بكود من الإدارة (واتساب)', 'Activate with a code from the admin'),
                  false, () {}),
            ]),
          ),
          const SizedBox(height: 14),
          if (status != 'suspended') ...[
            ActivationCard(doctor: doc, onActivated: reload),
            const SizedBox(height: 14),
          ],
        ],
        TileGrid(children: [
          Tile3D(icon: Icons.account_balance_wallet_rounded, color: Tone.green, label: tr('رصيدي اليومي', 'Daily balance'),
              subtitle: tr('الدخل والمصروفات', 'Income & expenses'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceScreen()))),
          Tile3D(icon: Icons.campaign_rounded, color: Tone.red, label: tr('إعلاناتي وعروضي', 'My offers'),
              subtitle: tr('توصل لكل المرضى', 'Reach every patient'),
              onTap: () {
                if (!verified) {
                  showMessage(context, tr('متاح بعد تفعيل حسابك.', 'Available after activation.'), error: true);
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorOffersScreen()));
              }),
          Tile3D(icon: Icons.receipt_long_rounded, color: look.accent, label: tr('الروشتة', 'Prescription'),
              subtitle: tr('اكتب واطبع وابعت', 'Write, print, send'),
              onTap: () {
                if (!verified) {
                  showMessage(context, tr('متاح بعد تفعيل حسابك.', 'Available after activation.'), error: true);
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorRxScreen()));
              }),
          Tile3D(icon: Icons.medication_liquid_rounded, color: Tone.purple, label: tr('أدوية للمراجعة', 'Medicines to review'),
              badge: data['reviews'] as int,
              subtitle: tr('صور أدوية من المرضى', 'Photos from patients'),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const MedReviewsScreen()));
                reload();
              }),
          Tile3D(icon: Icons.event_note_rounded, color: Tone.indigo, label: tr('الحجوزات', 'Bookings'),
              subtitle: tr('التقويم والكشوفات', 'Calendar & visits'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingsScreen()))),
          Tile3D(icon: Icons.inbox_rounded, color: Tone.orange, label: tr('طلبات الانضمام', 'Join requests'),
              badge: data['requests'] as int, subtitle: tr('${data['requests']} جديد', '${data['requests']} new'),
              onTap: () => goTo(1)),
          Tile3D(icon: Icons.people_alt_rounded, color: Tone.teal, label: tr('مرضاي', 'My patients'),
              subtitle: tr('${data['patients']} مريض', '${data['patients']} patients'), onTap: () => goTo(2)),
          Tile3D(icon: Icons.person_add_alt_1_rounded, color: Tone.teal, label: tr('إضافة مريض', 'Add patient'),
              subtitle: tr('برقم الموبايل', 'By mobile number'),
              onTap: () async {
                if (!verified) {
                  showMessage(context, tr('هتقدر تضيف مرضى بعد توثيق حسابك.', 'Available after verification.'), error: true);
                  return;
                }
                final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddPatientScreen()));
                if (added == true) reload();
              }),
          Tile3D(icon: Icons.local_hospital_rounded, color: Tone.blue, label: tr('عياداتي', 'My clinics'),
              subtitle: tr('$clinics عيادة', '$clinics clinics'), onTap: () => goTo(3)),
          Tile3D(icon: Icons.badge_rounded, color: look.accent, label: tr('بياناتي المهنية', 'Professional info'),
              subtitle: tr('التخصص والخبرة', 'Specialty & experience'), onTap: openProfile),
          Tile3D(icon: Icons.groups_rounded, color: Tone.sky, label: tr('المساعدين', 'Assistants'),
              subtitle: tr('وصلاحياتهم', 'and permissions'),
              onTap: () {
                if (!verified) {
                  showMessage(context, tr('متاح بعد تفعيل حسابك.', 'Available after activation.'), error: true);
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantsScreen()));
              }),
          Tile3D(icon: Icons.verified_rounded, color: Tone.purple, label: tr('التوثيق', 'Verification'),
              subtitle: verified ? tr('موثّق', 'Verified') : tr('المستندات', 'Documents'), onTap: openVerification),
        ]),
        const SizedBox(height: 14),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: SwitchListTile(
            value: doc['accepting_new'] == true,
            secondary: Icon3D(Icons.how_to_reg_rounded, color: Tone.green, size: 40),
            title: Text(tr('أستقبل مرضى جدد', 'Accepting new patients'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('لو قفلتها، المرضى يشوفوك بس ما يقدروش يبعتوا طلب.',
                'When off, patients see you but cannot send requests.')),
            onChanged: (v) async {
              final ok = await runBusy(context, () async {
                await supa.from('doctors').update({'accepting_new': v}).eq('id', myId);
              });
              if (ok) reload();
            },
          ),
        ),
      ],
    );
  }

  Widget _statusBanner(BuildContext context, String status, bool awaiting) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      'rejected' => InfoBanner(icon: Icons.error_outline, color: cs.error,
          text: tr('لم تتم الموافقة على التوثيق. راجع ملاحظات الإدارة في «التوثيق» وأعد الإرسال.',
              'Verification was declined. Check the admin notes and resubmit.')),
      'suspended' => InfoBanner(icon: Icons.block, color: cs.error,
          text: tr('حسابك المهني معلّق حالياً. تواصل مع إدارة المنصة.', 'Your professional account is suspended.')),
      _ => InfoBanner(icon: Icons.hourglass_top, color: Colors.orange.shade800,
          text: awaiting
              ? tr('مستنداتك قيد المراجعة. هتظهر للمرضى بعد التوثيق.', 'Your documents are under review.')
              : tr('حسابك لا يظهر للمرضى بعد. أكمل الخطوات دي:', 'You are not visible yet. Complete these steps:')),
    };
  }

  Widget _step(BuildContext context, int n, String text, bool done, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: done
          ? const Icon3D(Icons.check_rounded, color: Tone.green, size: 36)
          : Icon3D(null, color: Tone.amber, size: 36, emoji: '$n'),
      title: Text(text, style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
      trailing: done ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
