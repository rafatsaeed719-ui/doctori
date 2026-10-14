import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget point(IconData i, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            CircleAvatar(radius: 18, backgroundColor: cs.primaryContainer, child: Icon(i, size: 20, color: cs.primary)),
            const SizedBox(width: 12),
            Expanded(child: Text(t, style: tt.bodyLarge)),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => L10n.set(L10n.isAr ? 'en' : 'ar'),
                icon: const Icon(Icons.language),
                label: Text(L10n.isAr ? 'English' : 'العربية'),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: CircleAvatar(
                radius: 52,
                backgroundColor: cs.primary,
                child: Icon(Icons.medical_services_rounded, size: 54, color: cs.onPrimary),
              ),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<String>(
              valueListenable: AppState.appName,
              builder: (_, name, __) => Text(name, textAlign: TextAlign.center,
                  style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
            ),
            const SizedBox(height: 8),
            Text(tr('طبيبك يتابع حالتك خطوة بخطوة', 'Your doctor follows your care step by step'),
                textAlign: TextAlign.center, style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 28),
            point(Icons.search_rounded, tr('ابحث عن الطبيب المناسب بالتخصص أو المنطقة أو الأقرب لك',
                'Find the right doctor by specialty, area or distance')),
            point(Icons.how_to_reg_rounded, tr('انضم لعيادته مجاناً بضغطة واحدة', 'Join their clinic for free in one tap')),
            point(Icons.lock_rounded, tr('بياناتك الطبية لا يراها إلا طبيب وافقت عليه', 'Only doctors you approve can see your medical data')),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: Text(tr('إنشاء حساب جديد', 'Create an account')),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Text(tr('تسجيل الدخول', 'Log in')),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await runBusy(context, () async {
      await supa.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    });
    if (ok && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('تسجيل الدخول', 'Log in'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: tr('الإيميل', 'Email'), prefixIcon: const Icon(Icons.email_outlined)),
            validator: (v) => (v == null || !v.contains('@')) ? tr('اكتب إيميل صحيح', 'Enter a valid email') : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _hide,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: tr('كلمة السر', 'Password'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
            validator: requiredField,
            onFieldSubmitted: (_) => _submit(),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
              child: Text(tr('نسيت كلمة السر؟', 'Forgot password?')),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _submit, child: Text(tr('دخول', 'Log in'))),
        ]),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _role = 'patient';
  bool _agreed = false;
  bool _hide = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_agreed) {
      showMessage(context, tr('لازم توافق على الشروط ومعالجة بياناتك الصحية للمتابعة.',
          'You must accept the terms and health-data processing to continue.'), error: true);
      return;
    }
    AuthResponse? res;
    final ok = await runBusy(context, () async {
      res = await supa.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: AppConfig.authRedirect,
        data: {
          'full_name': _name.text.trim(),
          'role': _role,
          'locale': L10n.isAr ? 'ar' : 'en',
          'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
    });
    if (!ok || !mounted) return;
    if (res?.session != null) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.mark_email_read_outlined, size: 40),
        title: Text(tr('تأكيد الإيميل', 'Confirm your email')),
        content: Text(tr(
          'بعتنالك رسالة على ${_email.text.trim()}.\nافتحها من نفس الموبايل واضغط رابط التأكيد، وهيفتح التطبيق تلقائياً.\nلو مش لاقيها شوف مجلد Spam.',
          'We sent a message to ${_email.text.trim()}.\nOpen it on this phone and tap the link; the app will open automatically.\nCheck Spam if you can’t find it.',
        ), style: const TextStyle(height: 1.6)),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('حسناً', 'OK')))],
      ),
    );
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('إنشاء حساب', 'Create account'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text(tr('أنا:', 'I am a:'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'patient', icon: const Icon(Icons.person), label: Text(tr('مريض', 'Patient'))),
              ButtonSegment(value: 'doctor', icon: const Icon(Icons.medical_services), label: Text(tr('طبيب', 'Doctor'))),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          if (_role == 'doctor') ...[
            const SizedBox(height: 12),
            InfoBanner(
              icon: Icons.verified_user_outlined,
              text: tr('حساب الطبيب يظهر للمرضى بعد مراجعة مستندات الترخيص من إدارة المنصة.',
                  'Doctor accounts appear to patients after the platform reviews your licence documents.'),
            ),
          ],
          const SizedBox(height: 18),
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: tr('الاسم بالكامل', 'Full name'), prefixIcon: const Icon(Icons.badge_outlined)),
            validator: (v) => (v == null || v.trim().length < 2) ? tr('اكتب اسمك', 'Enter your name') : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: tr('الإيميل', 'Email'), prefixIcon: const Icon(Icons.email_outlined)),
            validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                ? tr('اكتب إيميل صحيح', 'Enter a valid email')
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _hide,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: tr('كلمة السر (8 على الأقل)', 'Password (min 8)'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
            validator: (v) => (v == null || v.length < 8)
                ? tr('كلمة السر لازم تكون 8 حروف أو أرقام على الأقل', 'At least 8 characters')
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirm,
            obscureText: _hide,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: tr('تأكيد كلمة السر', 'Confirm password'), prefixIcon: const Icon(Icons.lock_outline)),
            validator: (v) => v != _password.text ? tr('كلمتا السر غير متطابقتين', 'Passwords do not match') : null,
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              tr('أوافق على شروط الاستخدام وسياسة الخصوصية، وعلى معالجة بياناتي الصحية لغرض المتابعة الطبية، ومشاركتها فقط مع الأطباء الذين أوافق عليهم.',
                  'I accept the terms and privacy policy, and the processing of my health data for medical follow-up, shared only with doctors I approve.'),
              style: TextStyle(fontSize: 13.5, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _submit, child: Text(tr('إنشاء الحساب', 'Create account'))),
        ]),
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();

  Future<void> _send() async {
    if (!_email.text.contains('@')) {
      showMessage(context, tr('اكتب إيميل صحيح', 'Enter a valid email'), error: true);
      return;
    }
    final ok = await runBusy(context,
        () => supa.auth.resetPasswordForEmail(_email.text.trim(), redirectTo: AppConfig.authRedirect));
    if (ok && mounted) {
      showMessage(context, tr('لو الإيميل مسجل، هتوصلك رسالة فيها رابط لتغيير كلمة السر.',
          'If this email is registered, you will receive a reset link.'));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('نسيت كلمة السر', 'Forgot password'))),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(tr('اكتب إيميلك وهنبعتلك رابط تغيير كلمة السر. افتح الرابط من نفس الموبايل.',
              'Enter your email and we will send a reset link. Open it on this phone.'),
              style: const TextStyle(height: 1.6)),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: tr('الإيميل', 'Email'), prefixIcon: const Icon(Icons.email_outlined)),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _send, child: Text(tr('إرسال الرابط', 'Send link'))),
        ]),
      );
}

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();

  Future<void> _save() async {
    if (_p1.text.length < 8) {
      showMessage(context, tr('كلمة السر لازم تكون 8 حروف أو أرقام على الأقل', 'At least 8 characters'), error: true);
      return;
    }
    if (_p1.text != _p2.text) {
      showMessage(context, tr('كلمتا السر غير متطابقتين', 'Passwords do not match'), error: true);
      return;
    }
    final ok = await runBusy(context, () => supa.auth.updateUser(UserAttributes(password: _p1.text)),
        success: tr('تم تغيير كلمة السر', 'Password changed'));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('كلمة سر جديدة', 'New password'))),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          TextField(controller: _p1, obscureText: true, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('كلمة السر الجديدة', 'New password'))),
          const SizedBox(height: 14),
          TextField(controller: _p2, obscureText: true, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('تأكيد كلمة السر', 'Confirm password'))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: Text(tr('حفظ', 'Save'))),
        ]),
      );
}
