import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/map_widgets.dart';
import '../core/l10n.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

class DoctorDetailsScreen extends StatelessWidget {
  const DoctorDetailsScreen({super.key, required this.doctorId});
  final String doctorId;

  Future<Map<String, dynamic>?> _load() async {
    final res = await rpc('get_doctor_public', {'p_doctor': doctorId});
    return res is Map ? Map<String, dynamic>.from(res) : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('ملف الطبيب', 'Doctor profile'))),
      body: FutureView<Map<String, dynamic>?>(
        load: _load,
        builder: (context, d, reload) {
          if (d == null) {
            return EmptyView(icon: Icons.person_off, title: tr('هذا الطبيب غير متاح حالياً', 'This doctor is not available'));
          }
          return _DoctorBody(d: d);
        },
      ),
    );
  }
}

class _DoctorBody extends StatelessWidget {
  const _DoctorBody({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final clinics = (d['clinics'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final accepting = d['accepting_new'] == true;
    final count = d['rating_count'] as int? ?? 0;
    final years = d['years_experience'];
    final phone = d['public_phone'] as String?;

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: cs.primaryContainer,
                  child: Text((d['full_name'] as String? ?? '?').characters.first,
                      style: TextStyle(fontSize: 32, color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Text('${tr('د.', 'Dr.')} ${d['full_name'] ?? ''}', textAlign: TextAlign.center,
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text([L10n.isAr ? d['specialty'] : (d['specialty_en'] ?? d['specialty']), d['title']]
                        .whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    textAlign: TextAlign.center, style: tt.titleSmall?.copyWith(color: cs.primary)),
                const SizedBox(height: 10),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
                  if (count > 0)
                    StatusChip('★ ${((d['rating_avg'] as num?) ?? 0).toStringAsFixed(1)} ($count)', color: Colors.amber.shade800),
                  if (years != null) StatusChip(tr('خبرة $years سنة', '$years yrs experience'), color: cs.primary),
                  StatusChip(accepting ? tr('يستقبل مرضى جدد', 'Accepting patients') : tr('لا يستقبل حالياً', 'Not accepting'),
                      color: accepting ? Colors.green.shade700 : cs.outline),
                ]),
              ]),
            ),
          ),
          if ((d['bio'] as String?)?.isNotEmpty == true) ...[
            SectionTitle(tr('عن الطبيب', 'About')),
            Text(d['bio'], style: const TextStyle(height: 1.6)),
          ],
          if ((d['qualifications'] as String?)?.isNotEmpty == true) ...[
            SectionTitle(tr('المؤهلات', 'Qualifications')),
            Text(d['qualifications'], style: const TextStyle(height: 1.6)),
          ],
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.call),
              label: Text(phone, textDirection: TextDirection.ltr),
            ),
          ],
          SectionTitle(tr('العيادات ومواعيد العمل', 'Clinics & hours')),
          if (clinics.isEmpty) Text(tr('لم يضف الطبيب عيادات بعد.', 'No clinics added yet.')),
          for (final c in clinics) _ClinicCard(c: c),
          const SizedBox(height: 12),
          InfoBanner(
            icon: Icons.info_outline,
            text: tr('الانضمام لعيادة الطبيب مجاني. الطبيب يراجع طلبك، وبعد قبوله فقط يقدر يشوف البيانات اللي وافقت على مشاركتها.',
                'Joining is free. The doctor reviews your request; only after acceptance can they see what you agreed to share.'),
          ),
        ]),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: accepting ? () => _join(context, clinics) : null,
            icon: const Icon(Icons.how_to_reg),
            label: Text(accepting ? tr('الانضمام إلى عيادة الطبيب', 'Join this doctor’s clinic')
                : tr('الطبيب لا يستقبل مرضى جدداً', 'Not accepting new patients')),
          ),
        ),
      ),
    ]);
  }

  Future<void> _join(BuildContext context, List<Map<String, dynamic>> clinics) async {
    String? clinicId = clinics.length == 1 ? clinics.first['id'] as String : null;
    String scope = 'full';
    final message = TextEditingController();
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('طلب انضمام', 'Join request'), style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (clinics.length > 1)
                DropdownButtonFormField<String?>(
                  initialValue: clinicId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('العيادة (اختياري)', 'Clinic (optional)')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(tr('أي عيادة', 'Any clinic'))),
                    for (final cl in clinics) DropdownMenuItem<String?>(value: cl['id'] as String, child: Text(cl['name'] ?? '')),
                  ],
                  onChanged: (v) => setS(() => clinicId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: message,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(labelText: tr('رسالة للطبيب (اختياري)', 'Message to the doctor (optional)'),
                    hintText: tr('مثلاً: متابعة ضغط بعد كشف سابق', 'e.g. blood pressure follow-up')),
              ),
              Text(tr('ماذا يرى الطبيب بعد القبول؟', 'What can the doctor see after accepting?'),
                  style: Theme.of(c).textTheme.titleSmall),
              RadioGroup<String>(
                groupValue: scope,
                onChanged: (v) => setS(() => scope = v ?? 'full'),
                child: Column(children: [
                  RadioListTile<String>(
                    value: 'full',
                    contentPadding: EdgeInsets.zero,
                    title: Text(scopeLabel('full')),
                    subtitle: Text(tr('الأمراض والحساسية والأدوية وكل المرفقات', 'Conditions, allergies, medications and all files')),
                  ),
                  RadioListTile<String>(
                    value: 'own_uploads',
                    contentPadding: EdgeInsets.zero,
                    title: Text(scopeLabel('own_uploads')),
                    subtitle: Text(tr('يمكنك تغيير ذلك في أي وقت', 'You can change this anytime')),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('إرسال الطلب', 'Send request'))),
            ]),
          ),
        ),
      ),
    );
    if (send != true || !context.mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('request_join', {
        'p_doctor': d['id'],
        'p_clinic': clinicId,
        'p_message': message.text.trim().isEmpty ? null : message.text.trim(),
        'p_scope': scope,
      });
    }, success: tr('تم إرسال طلبك. هيوصلك إشعار لما الطبيب يرد.', 'Request sent. You will be notified when the doctor replies.'));
    if (ok && context.mounted) Navigator.pop(context);
  }
}

class _ClinicCard extends StatelessWidget {
  const _ClinicCard({required this.c});
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hours = (c['hours'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final lat = (c['lat'] as num?)?.toDouble();
    final lng = (c['lng'] as num?)?.toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name'] ?? '', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.place_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(child: Text([c['address'], c['area']].whereType<String>().where((s) => s.isNotEmpty).join('، '))),
            ]),
            if (hours.isNotEmpty) ...[
              const Divider(height: 20),
              for (final h in hours)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(width: 90, child: Text(weekdayName(h['weekday'] as int), style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${formatTime(h['opens_at'] as String?)} - ${formatTime(h['closes_at'] as String?)}'),
                  ]),
                ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              if (lat != null && lng != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openDirections(context, lat, lng),
                    icon: const Icon(Icons.directions),
                    label: Text(tr('الاتجاهات', 'Directions')),
                  ),
                ),
              if (lat != null && lng != null && (c['phone'] as String?)?.isNotEmpty == true) const SizedBox(width: 8),
              if ((c['phone'] as String?)?.isNotEmpty == true)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: c['phone'] as String)),
                    icon: const Icon(Icons.call),
                    label: Text(tr('اتصال', 'Call')),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
