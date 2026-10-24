import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/lookups.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

class DoctorProfileScreen extends StatelessWidget {
  /// [doctorId] null = the signed-in doctor; set when the admin edits another doctor.
  const DoctorProfileScreen({super.key, this.doctorId});
  final String? doctorId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(doctorId == null ? tr('بياناتي المهنية', 'Professional profile') : tr('البيانات المهنية', 'Professional info'))),
      body: FutureView<Map<String, dynamic>>(
        live: false,
        load: () => supa.from('doctors').select().eq('id', doctorId ?? myId).single(),
        builder: (context, doc, reload) => _Form(doc: doc),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.doc});
  final Map<String, dynamic> doc;
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _form = GlobalKey<FormState>();
  late int? _specialty = widget.doc['specialty_id'] as int?;
  late int? _sub = widget.doc['sub_specialty_id'] as int?;
  late final _title = TextEditingController(text: widget.doc['title'] as String?);
  late final _bio = TextEditingController(text: widget.doc['bio'] as String?);
  late final _qual = TextEditingController(text: widget.doc['qualifications'] as String?);
  late final _years = TextEditingController(text: widget.doc['years_experience']?.toString());
  late final _license = TextEditingController(text: widget.doc['license_number'] as String?);
  late final _phone = TextEditingController(text: widget.doc['public_phone'] as String?);

  bool get _verified => widget.doc['status'] == 'verified';

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final licenseChanged = (_license.text.trim()) != (widget.doc['license_number'] as String? ?? '');
    if (_verified && licenseChanged && widget.doc['id'] == myId) {
      final yes = await confirmDialog(context,
          title: tr('تغيير رقم الترخيص', 'Change licence number'),
          body: tr('تغيير رقم الترخيص هيرجّع حسابك للمراجعة، ومش هتظهر للمرضى لحد ما الإدارة توثّقه تاني.',
              'Changing the licence number sends your account back to review; you will be hidden from patients until re-verified.'),
          confirm: tr('متابعة', 'Continue'),
          danger: true);
      if (!yes || !mounted) return;
    }
    final ok = await runBusy(context, () async {
      await supa.from('doctors').update({
        'specialty_id': _specialty,
        'sub_specialty_id': _sub,
        'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        'qualifications': _qual.text.trim().isEmpty ? null : _qual.text.trim(),
        'years_experience': int.tryParse(_years.text.trim()),
        'license_number': _license.text.trim(),
        'public_phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      }).eq('id', widget.doc['id'] as String);
    }, success: tr('تم الحفظ', 'Saved'));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final specs = Lookups.specialties;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<int?>(
          initialValue: _specialty,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('التخصص *', 'Specialty *')),
          items: [for (final s in specs) DropdownMenuItem<int?>(value: s['id'] as int, child: Text(trField(s, 'name')))],
          validator: (v) => v == null ? tr('اختر التخصص', 'Choose a specialty') : null,
          onChanged: (v) => setState(() => _specialty = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: _sub,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('تخصص فرعي (اختياري)', 'Sub-specialty (optional)')),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(tr('لا يوجد', 'None'))),
            for (final s in specs) DropdownMenuItem<int?>(value: s['id'] as int, child: Text(trField(s, 'name'))),
          ],
          onChanged: (v) => setState(() => _sub = v),
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _title,
            decoration: InputDecoration(labelText: tr('اللقب المهني', 'Title'), hintText: tr('أخصائي / استشاري / أستاذ', 'Specialist / Consultant / Professor'))),
        const SizedBox(height: 12),
        TextFormField(
          controller: _license,
          decoration: InputDecoration(labelText: tr('رقم الترخيص / القيد بالنقابة *', 'Licence / syndicate number *')),
          validator: requiredField,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _years,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('سنوات الخبرة', 'Years of experience')),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final n = int.tryParse(v.trim());
            return (n == null || n < 0 || n > 70) ? tr('رقم غير صحيح', 'Invalid number') : null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _qual, maxLines: 3,
            decoration: InputDecoration(labelText: tr('المؤهلات والشهادات', 'Qualifications'))),
        const SizedBox(height: 12),
        TextFormField(controller: _bio, maxLines: 4, maxLength: 2000,
            decoration: InputDecoration(labelText: tr('نبذة عنك وعن خدماتك', 'About you and your services'))),
        const SizedBox(height: 4),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('رقم يظهر للمرضى (اختياري)', 'Phone shown to patients (optional)')),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: Text(tr('حفظ', 'Save'))),
      ]),
    );
  }
}
