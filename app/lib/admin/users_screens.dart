import 'package:flutter/material.dart';

import '../common/settings_screen.dart';
import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/lookups.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../doctor/clinics_screen.dart';
import '../doctor/doctor_profile_screen.dart';

String roleLabel(String? r) => switch (r) {
      'doctor' => tr('طبيب', 'Doctor'),
      'admin' => tr('مدير', 'Admin'),
      'patient' => tr('مريض', 'Patient'),
      _ => tr('الكل', 'All'),
    };

String userLogin(Map<String, dynamic> u) =>
    u['login_kind'] == 'phone' ? displayPhone(u['phone'] as String?) : (u['email'] as String? ?? '');

/// Admin: every account on the platform, with search, role filter and "add account".
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String? _role;
  String _query = '';
  int _key = 0;
  final _search = TextEditingController();

  void _refresh() => setState(() => _key++);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('المستخدمين', 'Users'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AdminCreateUserScreen()));
          if (added == true) _refresh();
        },
        icon: const Icon(Icons.person_add),
        label: Text(tr('إضافة حساب', 'Add account')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('بحث بالاسم أو الموبايل أو الإيميل', 'Search by name, mobile or email'),
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: (v) => setState(() {
              _query = v.trim();
              _key++;
            }),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final r in [null, 'patient', 'doctor', 'admin'])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(roleLabel(r)),
                  selected: _role == r,
                  onSelected: (_) => setState(() {
                    _role = r;
                    _key++;
                  }),
                ),
              ),
          ]),
        ),
        Expanded(
          child: FutureView<List<Map<String, dynamic>>>(
            key: ValueKey('$_role|$_query|$_key'),
            load: () async {
              final res = await rpc('admin_list_users', {'p_role': _role, 'p_query': _query.isEmpty ? null : _query});
              return (res as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            },
            builder: (context, list, reload) => RefreshList(
              onRefresh: reload,
              children: list.isEmpty
                  ? [EmptyView(icon: Icons.people_outline, title: tr('لا يوجد مستخدمين', 'No users found'))]
                  : [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(tr('${list.length} حساب', '${list.length} accounts'),
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                      for (final u in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              leading: UserAvatar(
                                url: u['avatar_url'] as String?,
                                name: u['full_name'] as String?,
                                radius: 24,
                                ring: u['is_suspended'] == true
                                    ? cs.error
                                    : switch (u['role']) {
                                        'doctor' => Tone.teal,
                                        'admin' => Tone.indigo,
                                        _ => Tone.blue,
                                      },
                              ),
                              title: Text(u['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([
                                roleLabel(u['role'] as String?),
                                userLogin(u),
                                if (u['is_suspended'] == true) tr('معلّق', 'Suspended'),
                              ].where((s) => s.isNotEmpty).join(' · ')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                final changed = await Navigator.push<bool>(
                                    context, MaterialPageRoute(builder: (_) => AdminUserDetailScreen(user: u)));
                                if (changed == true) _refresh();
                              },
                            ),
                          ),
                        ),
                    ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Admin creates a patient, doctor or admin account (mobile or email + password), already confirmed.
class AdminCreateUserScreen extends StatefulWidget {
  const AdminCreateUserScreen({super.key});
  @override
  State<AdminCreateUserScreen> createState() => _AdminCreateUserScreenState();
}

class _AdminCreateUserScreenState extends State<AdminCreateUserScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController(text: generatePassword());
  final _license = TextEditingController();
  String _role = 'doctor';
  int? _specialty;
  bool _verified = true;

  String? _loginValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.contains('@')) {
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : tr('إيميل غير صحيح', 'Invalid email');
    }
    return phoneValidator(t);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final raw = _login.text.trim();
    final isEmail = raw.contains('@');
    final login = isEmail ? raw.toLowerCase() : normalizeEgPhone(raw)!;
    final ok = await runBusy(context, () async {
      await rpc('admin_create_user', {
        'p_full_name': _name.text.trim(),
        'p_login': login,
        'p_password': _password.text,
        'p_role': _role,
        'p_specialty': _role == 'doctor' ? _specialty : null,
        'p_license': _role == 'doctor' ? _license.text.trim() : null,
        'p_verified': _verified,
      });
    });
    if (!ok || !mounted) return;
    await showCredentialsDialog(context,
        name: _name.text.trim(),
        login: isEmail ? login : displayPhone(login),
        password: _password.text,
        phoneForWhatsApp: isEmail ? null : login);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('إضافة حساب', 'Add account'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'doctor', icon: const Icon(Icons.medical_services), label: Text(tr('طبيب', 'Doctor'))),
              ButtonSegment(value: 'patient', icon: const Icon(Icons.person), label: Text(tr('مريض', 'Patient'))),
              ButtonSegment(value: 'admin', icon: const Icon(Icons.admin_panel_settings), label: Text(tr('مدير', 'Admin'))),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          if (_role == 'admin') ...[
            const SizedBox(height: 12),
            InfoBanner(icon: Icons.warning_amber, color: Colors.orange.shade800,
                text: tr('المدير له كل الصلاحيات على المنصة. أضف فقط من تثق فيه.', 'Admins have full control. Only add people you trust.')),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: tr('الاسم بالكامل *', 'Full name *')),
            validator: (v) => (v == null || v.trim().length < 2) ? tr('اكتب الاسم', 'Enter the name') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _login,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: tr('رقم الموبايل أو الإيميل * (للدخول)', 'Mobile or email * (to log in)'),
              hintText: '01xxxxxxxxx',
              prefixIcon: const Icon(Icons.login),
            ),
            validator: _loginValidator,
          ),
          const SizedBox(height: 12),
          NewPasswordField(controller: _password),
          if (_role == 'doctor') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _specialty,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('التخصص', 'Specialty')),
              items: [for (final s in Lookups.specialties) DropdownMenuItem<int?>(value: s['id'] as int, child: Text(trField(s, 'name')))],
              onChanged: (v) => setState(() => _specialty = v),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _license,
                decoration: InputDecoration(labelText: tr('رقم الترخيص / القيد', 'Licence number'))),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _verified,
              onChanged: (v) => setState(() => _verified = v),
              title: Text(tr('موثّق ويظهر للمرضى فوراً', 'Verified and visible to patients now')),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.person_add), label: Text(tr('إنشاء الحساب', 'Create account'))),
        ]),
      ),
    );
  }
}

/// Admin: one account — edit, password, doctor tools, suspend, delete.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({super.key, required this.user});
  final Map<String, dynamic> user;
  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late Map<String, dynamic> u = Map<String, dynamic>.from(widget.user);
  bool _changed = false;

  String get _id => u['id'] as String;
  bool get _isMe => _id == myId;

  void _mark() => _changed = true;

  Future<void> _resetPassword() async {
    final pw = generatePassword();
    final yes = await confirmDialog(context,
        title: tr('كلمة سر جديدة', 'New password'),
        body: tr('هيتم تعيين كلمة سر جديدة: $pw\nالقديمة هتبطل تشتغل.', 'New password will be: $pw\nThe old one stops working.'),
        confirm: tr('تعيين', 'Set'));
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('admin_set_password', {'p_user': _id, 'p_password': pw});
    });
    if (ok && mounted) {
      await showCredentialsDialog(context,
          name: u['full_name'] as String? ?? '',
          login: userLogin(u),
          password: pw,
          phoneForWhatsApp: u['login_kind'] == 'phone' ? u['phone'] as String? : null);
    }
  }

  Future<void> _toggleSuspend() async {
    final suspend = u['is_suspended'] != true;
    final yes = await confirmDialog(context,
        title: suspend ? tr('تعليق الحساب؟', 'Suspend account?') : tr('إعادة تفعيل الحساب؟', 'Reactivate account?'),
        body: suspend
            ? tr('صاحب الحساب مش هيقدر يستخدم التطبيق لحد ما تفعّله تاني.', 'The user cannot use the app until reactivated.')
            : tr('صاحب الحساب هيقدر يستخدم التطبيق تاني.', 'The user can use the app again.'),
        confirm: suspend ? tr('تعليق', 'Suspend') : tr('تفعيل', 'Reactivate'),
        danger: suspend);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('admin_set_suspended', {'p_user': _id, 'p_suspended': suspend});
    });
    if (ok) setState(() {
      u['is_suspended'] = suspend;
      _mark();
    });
  }

  Future<void> _review(String decision) async {
    final ok = await runBusy(context, () async {
      await rpc('admin_review_doctor', {'p_doctor': _id, 'p_decision': decision});
    }, success: tr('تم', 'Done'));
    if (ok) setState(() {
      u['doctor_status'] = decision;
      _mark();
    });
  }

  Future<void> _delete() async {
    final yes = await confirmDialog(context,
        title: tr('حذف الحساب نهائياً؟', 'Delete account permanently?'),
        body: tr('هيتم حذف «${u['full_name']}» وكل بياناته (العيادات، الارتباطات، الطلبات). مفيش تراجع.',
            'This deletes “${u['full_name']}” and all their data (clinics, links, requests). This cannot be undone.'),
        confirm: tr('حذف نهائي', 'Delete'),
        danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('admin_delete_user', {'p_user': _id});
    }, success: tr('تم حذف الحساب', 'Account deleted'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDoctor = u['role'] == 'doctor';
    final status = u['doctor_status'] as String?;
    Widget action(IconData i, String t, VoidCallback onTap, {Color? color}) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(leading: Icon(i, color: color ?? cs.primary), title: Text(t, style: TextStyle(color: color)),
              trailing: const Icon(Icons.chevron_right), onTap: onTap),
        );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(u['full_name'] ?? '')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  StatusChip(roleLabel(u['role'] as String?), color: cs.primary),
                  if (isDoctor && status != null)
                    StatusChip(switch (status) {
                      'verified' => tr('موثّق', 'Verified'),
                      'rejected' => tr('مرفوض', 'Rejected'),
                      'suspended' => tr('معلّق مهنياً', 'Suspended'),
                      _ => tr('بانتظار التوثيق', 'Pending'),
                    }, color: status == 'verified' ? Colors.green.shade700 : Colors.orange.shade800),
                  if (u['is_suspended'] == true) StatusChip(tr('الحساب معلّق', 'Account suspended'), color: cs.error),
                ]),
                const SizedBox(height: 12),
                SelectableText('${tr('الدخول', 'Login')}: ${userLogin(u)}', textDirection: TextDirection.ltr),
                if (u['created_by_name'] != null) Text('${tr('أنشأه', 'Created by')}: ${u['created_by_name']}'),
                Text('${tr('تاريخ التسجيل', 'Joined')}: ${formatDate(u['created_at'] as String?)}'),
              ]),
            ),
          ),
          SectionTitle(tr('الحساب', 'Account')),
          action(Icons.edit_outlined, tr('تعديل البيانات الشخصية', 'Edit personal info'), () async {
            final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: u)));
            if (changed == true) {
              final fresh = await supa.from('profiles').select().eq('id', _id).maybeSingle();
              if (fresh != null && mounted) {
                setState(() {
                  u['full_name'] = fresh['full_name'];
                  u['phone'] = fresh['phone'];
                  u['gender'] = fresh['gender'];
                  u['birth_date'] = fresh['birth_date'];
                  _mark();
                });
              }
            }
          }),
          action(Icons.lock_reset, tr('تعيين كلمة سر جديدة', 'Set a new password'), _resetPassword),
          if (isDoctor) ...[
            SectionTitle(tr('الطبيب', 'Doctor')),
            action(Icons.badge_outlined, tr('البيانات المهنية (التخصص، الترخيص...)', 'Professional info'), () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => DoctorProfileScreen(doctorId: _id)));
              _mark();
            }),
            action(Icons.local_hospital_outlined, tr('العيادات ومواعيدها', 'Clinics & hours'), () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ClinicsScreen(doctorId: _id)));
              _mark();
            }),
            if (status != 'verified')
              action(Icons.verified, tr('توثيق الطبيب (يظهر للمرضى)', 'Verify doctor'), () => _review('verified'),
                  color: Colors.green.shade700),
            if (status == 'verified')
              action(Icons.block, tr('إيقاف الظهور للمرضى', 'Hide from patients (suspend)'), () => _review('suspended'),
                  color: Colors.orange.shade800),
          ],
          if (!_isMe) ...[
            SectionTitle(tr('إجراءات', 'Actions')),
            action(u['is_suspended'] == true ? Icons.play_circle_outline : Icons.pause_circle_outline,
                u['is_suspended'] == true ? tr('إعادة تفعيل الحساب', 'Reactivate account') : tr('تعليق الحساب', 'Suspend account'),
                _toggleSuspend,
                color: u['is_suspended'] == true ? null : Colors.orange.shade800),
            action(Icons.delete_forever, tr('حذف الحساب نهائياً', 'Delete account'), _delete, color: cs.error),
          ],
        ]),
      ),
    );
  }
}
