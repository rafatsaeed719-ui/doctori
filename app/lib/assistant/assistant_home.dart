import 'package:flutter/material.dart';

import '../common/settings_screen.dart';
import '../core/avatar.dart';
import '../core/backgrounds.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../doctor/add_patient_screen.dart';
import '../doctor/bookings_screen.dart';
import '../doctor/finance_screen.dart';
import '../doctor/med_reviews_screen.dart';
import '../doctor/rx_screens.dart';
import '../doctor/patients_requests_screens.dart';

/// Home for a doctor's assistant: only the tools the doctor allowed.
class AssistantHome extends StatelessWidget {
  const AssistantHome({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: AppState.ctx,
      builder: (context, ctx, _) {
        final of = (ctx['assistant_of'] as Map?)?.cast<String, dynamic>();
        final look = specialtyLook(of?['specialty_en'] as String?);
        final tt = Theme.of(context).textTheme;
        void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
        final tiles = <Widget>[
          if (can('bookings'))
            Tile3D(icon: Icons.event_note_rounded, color: Tone.blue, label: tr('الحجوزات', 'Bookings'),
                subtitle: tr('التقويم والتأكيد', 'Calendar & confirm'), onTap: () => open(const BookingsScreen())),
          if (can('patients'))
            Tile3D(icon: Icons.inbox_rounded, color: Tone.orange, label: tr('طلبات الانضمام', 'Join requests'),
                onTap: () => open(const DoctorRequestsScreen())),
          if (can('patients') || can('medical'))
            Tile3D(icon: Icons.people_alt_rounded, color: Tone.teal, label: tr('المرضى', 'Patients'),
                subtitle: can('medical') ? tr('والملف الطبي', 'and medical files') : null,
                onTap: () => open(const DoctorPatientsScreen())),
          if (can('finance'))
            Tile3D(icon: Icons.account_balance_wallet_rounded, color: Tone.green, label: tr('رصيد العيادة', 'Clinic balance'),
                subtitle: tr('الدخل والمصروفات', 'Income & expenses'), onTap: () => open(const FinanceScreen())),
          if (can('medical'))
            Tile3D(icon: Icons.receipt_long_rounded, color: look.accent, label: tr('الروشتات', 'Prescriptions'),
                onTap: () => open(const DoctorRxScreen())),
          if (can('medical'))
            Tile3D(icon: Icons.medication_liquid_rounded, color: Tone.purple, label: tr('أدوية للمراجعة', 'Medicines to review'),
                onTap: () => open(const MedReviewsScreen())),
          if (can('add_patients'))
            Tile3D(icon: Icons.person_add_alt_1_rounded, color: Tone.green, label: tr('إضافة مريض', 'Add patient'),
                onTap: () => open(const AddPatientScreen())),
          Tile3D(icon: Icons.person_rounded, color: Tone.pink, label: tr('حسابي', 'My account'),
              onTap: () => open(const SettingsScreen())),
        ];
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: PatternBackground(
            look: look,
            child: SafeArea(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                GlassCard(
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => changeMyAvatar(context),
                      child: UserAvatar(url: ctx['avatar_url'] as String?, name: ctx['full_name'] as String?,
                          radius: 30, ring: look.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('أهلاً 👋', 'Hello 👋'), style: tt.bodyMedium),
                        Text(ctx['full_name'] as String? ?? '', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                        Text('${tr('مساعد د.', 'Assistant to Dr.')} ${of?['doctor_name'] ?? ''}',
                            style: tt.bodyMedium?.copyWith(color: darken(look.accent, 0.1), fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                if (of == null)
                  InfoBanner(icon: Icons.link_off, text: tr('الحساب ده مش مربوط بطبيب حالياً.', 'This account is not linked to a doctor.'))
                else if (of['doctor_status'] != 'verified')
                  InfoBanner(icon: Icons.hourglass_top, color: Colors.orange.shade800,
                      text: tr('حساب الطبيب لسه مش مفعّل، فبعض الأدوات مش هتشتغل.', 'The doctor is not verified yet; some tools are disabled.')),
                const SizedBox(height: 8),
                TileGrid(children: tiles),
              ]),
            ),
          ),
        );
      },
    );
  }
}
