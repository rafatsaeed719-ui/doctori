import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Doctor creates a patient account (mobile + password) that is already linked to the clinic.
/// No confirmation and no SMS: the doctor hands the login details to the patient.
class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});
  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController(text: generatePassword());
  String? _gender;
  DateTime? _birth;
  bool _agreed = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_agreed) {
      showMessage(context, tr('لازم تأكد إن المريض موافق على فتح الحساب ومشاركة ملفه معاك.',
          'Confirm the patient agreed to the account and to sharing their file with you.'), error: true);
      return;
    }
    final phone = normalizeEgPhone(_phone.text)!;
    final ok = await runBusy(context, () async {
      await rpc('doctor_create_patient', {
        'p_full_name': _name.text.trim(),
        'p_phone': phone,
        'p_password': _password.text,
        'p_gender': _gender,
        'p_doctor': actingDoctorId(),
        'p_birth_date': _birth == null
            ? null
            : '${_birth!.year}-${_birth!.month.toString().padLeft(2, '0')}-${_birth!.day.toString().padLeft(2, '0')}',
      });
    });
    if (!ok || !mounted) return;
    await showCredentialsDialog(context,
        name: _name.text.trim(), login: displayPhone(phone), password: _password.text, phoneForWhatsApp: phone);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('إضافة مريض للعيادة', 'Add patient to clinic'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          InfoBanner(
            icon: Icons.info_outline,
            text: tr('هيتعمل حساب للمريض برقم موبايله وكلمة السر، ويبقى مضاف لعيادتك على طول. مفيش رسائل هتتبعت؛ انت اللي هتديله البيانات.',
                'An account is created with the patient’s mobile and password, already in your clinic. No message is sent; you hand over the details.'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: tr('اسم المريض بالكامل *', 'Patient full name *')),
            validator: (v) => (v == null || v.trim().length < 2) ? tr('اكتب الاسم', 'Enter the name') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: tr('رقم الموبايل * (هيدخل بيه)', 'Mobile number * (used to log in)'),
                prefixIcon: const Icon(Icons.phone_android), hintText: '01xxxxxxxxx'),
            validator: phoneValidator,
          ),
          const SizedBox(height: 12),
          NewPasswordField(controller: _password),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _gender,
            decoration: InputDecoration(labelText: tr('النوع', 'Gender')),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(tr('غير محدد', 'Not set'))),
              DropdownMenuItem<String?>(value: 'male', child: Text(genderLabel('male'))),
              DropdownMenuItem<String?>(value: 'female', child: Text(genderLabel('female'))),
            ],
            onChanged: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            title: Text(tr('تاريخ الميلاد', 'Date of birth')),
            subtitle: Text(_birth == null ? tr('غير محدد', 'Not set') : formatDate(_birth!.toIso8601String())),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _birth ?? DateTime(1990),
                  firstDate: DateTime(1910), lastDate: DateTime.now());
              if (d != null) setState(() => _birth = d);
            },
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(tr('المريض موافق على فتح الحساب ومشاركة ملفه الطبي معي.',
                'The patient agrees to this account and to sharing their medical file with me.')),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.person_add),
              label: Text(tr('إنشاء الحساب', 'Create account'))),
        ]),
      ),
    );
  }
}
