import 'package:flutter/material.dart';

import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../patient/meds_screen.dart';
import '../patient/medical_file_screen.dart';
import 'case_plan_screens.dart';

/// Doctor / assistant view of one linked patient: medical file + treatment, and account actions.
class PatientFileScreen extends StatelessWidget {
  const PatientFileScreen({super.key, required this.patient});
  final Map<String, dynamic> patient; // a row from doctor_my_patients

  String get _id => patient['patient_id'] as String;

  Future<void> _resetPassword(BuildContext context) async {
    final pw = generatePassword();
    final ok = await runBusy(context, () async {
      await rpc('doctor_reset_patient_password', {'p_patient': _id, 'p_password': pw, 'p_doctor': actingDoctorId()});
    });
    if (ok && context.mounted) {
      await showCredentialsDialog(context,
          name: patient['patient_name'] as String? ?? '',
          login: displayPhone(patient['phone'] as String?),
          password: pw,
          phoneForWhatsApp: patient['phone'] as String?);
    }
  }

  Future<void> _endCare(BuildContext context) async {
    final yes = await confirmDialog(context,
        title: tr('إنهاء المتابعة؟', 'End care?'),
        body: tr('هتفقد الوصول لملف المريض. المريض يقدر يبعت طلب جديد بعدين.',
            'You will lose access to the patient’s file. The patient can send a new request later.'),
        confirm: tr('إنهاء', 'End'),
        danger: true);
    if (!yes || !context.mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('end_care_link', {'p_link': patient['link_id']});
    }, success: tr('تم إنهاء المتابعة', 'Care ended'));
    if (ok && context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final medical = can('medical');
    final followups = medical || can('bookings');
    final tabs = <(Tab, Widget)>[
      if (medical) ...[
        (Tab(icon: const Icon(Icons.assignment_rounded), text: tr('الحالة', 'Case')), CasePlansView(patientId: _id)),
        (Tab(icon: const Icon(Icons.medication_rounded), text: tr('العلاج', 'Treatment')),
            MedsScreen(patientId: _id, canPrescribe: true, embedded: true)),
      ],
      if (followups)
        (Tab(icon: const Icon(Icons.event_repeat_rounded), text: tr('المتابعة', 'Follow-ups')),
            FollowupsView(patientId: _id, patientName: patient['patient_name'] as String?, patientPhone: patient['phone'] as String?)),
      if (medical)
        (Tab(icon: const Icon(Icons.folder_shared_rounded), text: tr('الملف الطبي', 'Medical file')),
            MedicalFileScreen(patientId: _id, embedded: true)),
    ];
    return DefaultTabController(
      length: tabs.isEmpty ? 1 : tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            UserAvatar(url: patient['avatar_url'] as String?, name: patient['patient_name'] as String?, radius: 16),
            const SizedBox(width: 8),
            Flexible(child: Text(patient['patient_name'] ?? '', overflow: TextOverflow.ellipsis)),
          ]),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => v == 'password' ? _resetPassword(context) : _endCare(context),
              itemBuilder: (c) => [
                if (patient['created_by_clinic'] == true && can('add_patients'))
                  PopupMenuItem(value: 'password', child: Text(tr('كلمة سر جديدة للمريض', 'New patient password'))),
                if (!isAssistant)
                  PopupMenuItem(value: 'end', child: Text(tr('إنهاء المتابعة', 'End care'))),
              ],
            ),
          ],
          bottom: tabs.isEmpty
              ? null
              : TabBar(isScrollable: tabs.length > 3, tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
                  tabs: [for (final t in tabs) t.$1]),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              [
                genderLabel(patient['gender'] as String?),
                if (patient['age'] != null) tr('${patient['age']} سنة', '${patient['age']} yrs'),
                displayPhone(patient['phone'] as String?),
                '${tr('المشاركة', 'Sharing')}: ${scopeLabel(patient['scope'] as String?)}',
              ].where((s) => s.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: tabs.isEmpty
                ? EmptyView(icon: Icons.lock_outline, title: tr('مش مسموحلك تشوف الملف الطبي', 'No access to medical files'),
                    subtitle: tr('اطلب من الدكتور صلاحية «الملف الطبي والعلاج».', 'Ask the doctor for the medical permission.'))
                : TabBarView(children: [for (final t in tabs) t.$2]),
          ),
        ]),
      ),
    );
  }
}
