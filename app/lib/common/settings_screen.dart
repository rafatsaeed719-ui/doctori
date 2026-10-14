import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/l10n.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Account & privacy screen shared by every role.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('حسابي', 'My account'))),
      body: FutureView<Map<String, dynamic>>(
        load: () => supa.from('profiles').select().eq('id', myId).single(),
        builder: (context, p, reload) => _Body(profile: p, reload: reload),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.profile, required this.reload});
  final Map<String, dynamic> profile;
  final Future<void> Function() reload;

  String get _role => switch (profile['role']) {
        'doctor' => tr('طبيب', 'Doctor'),
        'admin' => tr('مدير المنصة', 'Platform admin'),
        _ => tr('مريض', 'Patient'),
      };

  Future<void> _setLanguage(BuildContext context, String code) async {
    try {
      await supa.from('profiles').update({'locale': code}).eq('id', myId);
    } catch (_) {/* language still switches locally */}
    L10n.set(code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshList(onRefresh: reload, children: [
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: CircleAvatar(radius: 26, child: Text((profile['full_name'] as String? ?? '?').characters.first,
              style: const TextStyle(fontSize: 22))),
          title: Text(profile['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${profile['email'] ?? ''}\n$_role'),
          isThreeLine: true,
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final changed = await Navigator.push<bool>(
                context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)));
            if (changed == true) reload();
          },
        ),
      ),
      SectionTitle(tr('اللغة', 'Language')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {L10n.isAr ? 'ar' : 'en'},
            onSelectionChanged: (s) => _setLanguage(context, s.first),
          ),
        ),
      ),
      SectionTitle(tr('الخصوصية والأمان', 'Privacy & security')),
      Card(
        child: Column(children: [
          ListTile(
            leading: Icon(Icons.shield_outlined, color: cs.primary),
            title: Text(tr('من يرى بياناتي؟', 'Who can see my data?')),
            subtitle: Text(tr('فقط الأطباء الذين قبلوا طلب انضمامك، وفي حدود المشاركة التي اخترتها. تقدر تغيّرها أو تلغيها من «أطبائي».',
                'Only doctors who accepted your request, within the sharing you chose. Change or revoke it from “My doctors”.')),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.lock_reset, color: cs.primary),
            title: Text(tr('تغيير كلمة السر', 'Change password')),
            onTap: () => _changePassword(context),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      InfoBanner(
        icon: Icons.emergency_outlined,
        color: cs.error,
        text: tr('التطبيق ليس بديلاً عن الطوارئ. في الحالات الطارئة اتصل بالإسعاف 123 أو توجه لأقرب مستشفى.',
            'This app is not for emergencies. In an emergency call 123 or go to the nearest hospital.'),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: cs.error),
        onPressed: () async {
          final yes = await confirmDialog(context,
              title: tr('تسجيل الخروج؟', 'Log out?'), body: tr('هتحتاج تدخل بالإيميل وكلمة السر تاني.', 'You will need to log in again.'),
              confirm: tr('خروج', 'Log out'));
          if (yes) await supa.auth.signOut();
        },
        icon: const Icon(Icons.logout),
        label: Text(tr('تسجيل الخروج', 'Log out')),
      ),
    ]);
  }

  Future<void> _changePassword(BuildContext context) async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('كلمة سر جديدة', 'New password')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: p1, obscureText: true, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('كلمة السر الجديدة', 'New password'))),
          const SizedBox(height: 12),
          TextField(controller: p2, obscureText: true, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('تأكيد كلمة السر', 'Confirm password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ', 'Save'))),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    if (p1.text.length < 8 || p1.text != p2.text) {
      showMessage(context, tr('كلمة السر لازم 8 حروف على الأقل ومتطابقة', 'Password must be 8+ characters and match'), error: true);
      return;
    }
    await runBusy(context, () => supa.auth.updateUser(UserAttributes(password: p1.text)),
        success: tr('تم تغيير كلمة السر', 'Password changed'));
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile['full_name'] as String?);
  late final _phone = TextEditingController(text: widget.profile['phone'] as String?);
  late String? _gender = widget.profile['gender'] as String?;
  late DateTime? _birth = DateTime.tryParse(widget.profile['birth_date'] as String? ?? '');

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final ok = await runBusy(context, () async {
      await supa.from('profiles').update({
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'gender': _gender,
        'birth_date': _birth == null
            ? null
            : '${_birth!.year}-${_birth!.month.toString().padLeft(2, '0')}-${_birth!.day.toString().padLeft(2, '0')}',
      }).eq('id', myId);
    }, success: tr('تم الحفظ', 'Saved'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('بياناتي الشخصية', 'Personal info'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _name,
              validator: (v) => (v == null || v.trim().length < 2) ? tr('اكتب اسمك', 'Enter your name') : null,
              decoration: InputDecoration(labelText: tr('الاسم بالكامل', 'Full name'))),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('رقم الموبايل', 'Mobile number'))),
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
              final d = await showDatePicker(
                context: context,
                initialDate: _birth ?? DateTime(1990),
                firstDate: DateTime(1910),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _birth = d);
            },
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(tr('حفظ', 'Save'))),
        ]),
      ),
    );
  }
}
