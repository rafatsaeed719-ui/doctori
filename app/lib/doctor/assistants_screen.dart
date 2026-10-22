import 'package:flutter/material.dart';

import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// The four permissions a doctor can give an assistant.
class _Perm {
  const _Perm(this.key, this.icon, this.color, this.ar, this.en, this.descAr, this.descEn);
  final String key;
  final IconData icon;
  final Color color;
  final String ar, en, descAr, descEn;
}

const _perms = [
  _Perm('bookings', Icons.event_note_rounded, Tone.blue, 'الحجوزات', 'Bookings',
      'يشوف التقويم ويأكد ويلغي ويحجز للمرضى', 'Sees the calendar, confirms, cancels, books'),
  _Perm('patients', Icons.people_alt_rounded, Tone.teal, 'المرضى والطلبات', 'Patients & requests',
      'يشوف قائمة المرضى ويقبل أو يرفض طلبات الانضمام', 'Sees patients, accepts or declines requests'),
  _Perm('add_patients', Icons.person_add_alt_1_rounded, Tone.green, 'إضافة مرضى', 'Add patients',
      'يعمل حسابات مرضى جديدة برقم الموبايل', 'Creates patient accounts by mobile'),
  _Perm('medical', Icons.medication_rounded, Tone.purple, 'الملف الطبي والعلاج', 'Medical file & treatment',
      'يشوف ملفات المرضى ويكتب علاج باسمك — صلاحية حساسة', 'Sees medical files and prescribes in your name — sensitive'),
  _Perm('finance', Icons.account_balance_wallet_rounded, Tone.amber, 'رصيد العيادة', 'Clinic balance',
      'يسجل دخل الحالات والمصروفات ويشوف الرصيد', 'Records income and expenses and sees the balance'),
];

class AssistantsScreen extends StatefulWidget {
  const AssistantsScreen({super.key});
  @override
  State<AssistantsScreen> createState() => _AssistantsScreenState();
}

class _AssistantsScreenState extends State<AssistantsScreen> {
  int _key = 0;

  Future<void> _add() async {
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const _AssistantForm()));
    if (added == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('المساعدين', 'Assistants'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: Text(tr('إضافة مساعد', 'Add assistant')),
      ),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () async {
          final r = await rpc('doctor_list_assistants');
          return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        },
        builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
          InfoBanner(
            icon: Icons.groups_rounded,
            text: tr('المساعد بيدخل برقم موبايله وكلمة السر اللي تعملها، وبيشوف بس اللي انت سمحتله بيه. تقدر تغيّر صلاحياته أو تمسحه في أي وقت.',
                'Assistants log in with the mobile and password you set, and only see what you allow. Change or remove anytime.'),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty) EmptyView(icon: Icons.badge_outlined, title: tr('مفيش مساعدين لسه', 'No assistants yet')),
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: UserAvatar(url: a['avatar_url'] as String?, name: a['full_name'] as String?, radius: 24),
                  title: Text(a['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 4, runSpacing: 4, children: [
                      Text(displayPhone(a['phone'] as String?), textDirection: TextDirection.ltr),
                      for (final p in _perms)
                        if (a['can_${p.key}'] == true) StatusChip(tr(p.ar, p.en), color: p.color),
                    ]),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final changed = await Navigator.push<bool>(
                        context, MaterialPageRoute(builder: (_) => _AssistantForm(existing: a)));
                    if (changed == true) setState(() => _key++);
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _AssistantForm extends StatefulWidget {
  const _AssistantForm({this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<_AssistantForm> createState() => _AssistantFormState();
}

class _AssistantFormState extends State<_AssistantForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController(text: generatePassword());
  late final Map<String, bool> _on = {
    for (final p in _perms) p.key: widget.existing == null ? p.key == 'bookings' : widget.existing!['can_${p.key}'] == true,
  };
  bool get _isNew => widget.existing == null;

  Future<void> _save() async {
    if (_isNew && !_form.currentState!.validate()) return;
    final ok = await runBusy(context, () async {
      String? assistantId = widget.existing?['assistant_id'] as String?;
      if (_isNew) {
        final r = await rpc('doctor_create_assistant', {
          'p_full_name': _name.text.trim(),
          'p_phone': normalizeEgPhone(_phone.text),
          'p_password': _password.text,
          'p_bookings': _on['bookings'],
          'p_patients': _on['patients'],
          'p_add_patients': _on['add_patients'],
          'p_medical': _on['medical'],
        });
        assistantId = (r as Map)['assistant_id'] as String?;
      } else {
        await rpc('doctor_update_assistant', {
          'p_assistant': widget.existing!['assistant_id'],
          'p_bookings': _on['bookings'],
          'p_patients': _on['patients'],
          'p_add_patients': _on['add_patients'],
          'p_medical': _on['medical'],
        });
      }
      if (assistantId != null && (_on['finance'] == true || !_isNew)) {
        await rpc('set_assistant_finance', {'p_assistant': assistantId, 'p_on': _on['finance'] == true});
      }
    }, success: _isNew ? null : tr('تم حفظ الصلاحيات', 'Permissions saved'));
    if (!ok || !mounted) return;
    if (_isNew) {
      final phone = normalizeEgPhone(_phone.text)!;
      await showCredentialsDialog(context,
          name: _name.text.trim(), login: displayPhone(phone), password: _password.text, phoneForWhatsApp: phone);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _resetPassword() async {
    final pw = generatePassword();
    final ok = await runBusy(context, () async {
      await rpc('doctor_reset_assistant_password', {'p_assistant': widget.existing!['assistant_id'], 'p_password': pw});
    });
    if (ok && mounted) {
      await showCredentialsDialog(context,
          name: widget.existing!['full_name'] as String? ?? '',
          login: displayPhone(widget.existing!['phone'] as String?),
          password: pw,
          phoneForWhatsApp: widget.existing!['phone'] as String?);
    }
  }

  Future<void> _remove() async {
    final yes = await confirmDialog(context,
        title: tr('حذف المساعد؟', 'Remove assistant?'),
        body: tr('حسابه هيتمسح ومش هيقدر يدخل تاني.', 'Their account is deleted and they can no longer log in.'),
        confirm: tr('حذف', 'Remove'),
        danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('doctor_remove_assistant', {'p_assistant': widget.existing!['assistant_id']});
    }, success: tr('تم حذف المساعد', 'Assistant removed'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? tr('مساعد جديد', 'New assistant') : widget.existing!['full_name'] ?? ''),
        actions: [
          if (!_isNew) IconButton(onPressed: _remove, icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_isNew) ...[
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('اسم المساعد *', 'Assistant name *')),
              validator: (v) => (v == null || v.trim().length < 2) ? tr('اكتب الاسم', 'Enter the name') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('رقم الموبايل * (هيدخل بيه)', 'Mobile * (to log in)'),
                  hintText: '01xxxxxxxxx', prefixIcon: const Icon(Icons.phone_android)),
              validator: phoneValidator,
            ),
            const SizedBox(height: 12),
            NewPasswordField(controller: _password),
          ] else
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_reset),
                title: Text(tr('كلمة سر جديدة للمساعد', 'New password for assistant')),
                subtitle: Text(displayPhone(widget.existing!['phone'] as String?), textDirection: TextDirection.ltr),
                onTap: _resetPassword,
              ),
            ),
          SectionTitle(tr('الصلاحيات', 'Permissions')),
          for (final p in _perms)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile(
                secondary: Icon3D(p.icon, color: p.color, size: 40),
                title: Text(tr(p.ar, p.en), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(tr(p.descAr, p.descEn)),
                value: _on[p.key] ?? false,
                onChanged: (v) => setState(() => _on[p.key] = v),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(_isNew ? tr('إنشاء حساب المساعد', 'Create assistant account') : tr('حفظ الصلاحيات', 'Save permissions')),
          ),
        ]),
      ),
    );
  }
}
