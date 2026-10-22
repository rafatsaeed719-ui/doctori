import 'package:flutter/material.dart';

import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../patient/meds_screen.dart';

/// Medicines patients photographed and sent: the doctor opens each one and sets the dose.
class MedReviewsScreen extends StatefulWidget {
  const MedReviewsScreen({super.key});
  @override
  State<MedReviewsScreen> createState() => _MedReviewsScreenState();
}

class _MedReviewsScreenState extends State<MedReviewsScreen> {
  int _key = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('أدوية للمراجعة', 'Medicines to review'))),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => rpcList('doctor_pending_med_reviews', {'p_doctor': actingDoctorId()}),
        builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
          if (list.isEmpty)
            EmptyView(
              icon: Icons.medication_liquid_rounded,
              title: tr('مفيش أدوية مستنية مراجعة', 'Nothing to review'),
              subtitle: tr('لما مريض يصوّر دوا ويبعتهولك هيظهر هنا عشان تحدد الجرعة.',
                  'When a patient photographs a medicine for you, it shows here.'),
            ),
          for (final m in list)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final saved = await Navigator.push<bool>(context, MaterialPageRoute(
                      builder: (_) => MedicationForm(patientId: m['patient_id'] as String, prescribe: true, review: m)));
                  if (saved == true) setState(() => _key++);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (m['photo_path'] != null) MedPhoto(path: m['photo_path'] as String, size: 90),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          UserAvatar(url: m['patient_avatar'] as String?, name: m['patient_name'] as String?, radius: 14),
                          const SizedBox(width: 6),
                          Expanded(child: Text(m['patient_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w900))),
                        ]),
                        const SizedBox(height: 4),
                        Text('${medFormInfo(m['form'] as String?).$1} ${m['name'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        if ((m['instructions'] as String?)?.isNotEmpty == true)
                          Text('«${m['instructions']}»', maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(formatDate(m['created_at'] as String?), style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 6),
                        Text(tr('اضغط لتحديد الجرعة ←', 'Tap to set the dose →'),
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
