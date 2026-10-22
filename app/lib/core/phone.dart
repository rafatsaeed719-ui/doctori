import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';
import 'widgets.dart';

/// Phone accounts (created by a clinic or the admin) sign in with a hidden internal
/// email built from the phone number. No message is ever sent to it.
const phoneLoginDomain = 'phone.doctori.app';

/// Egyptian mobile → 2010XXXXXXXX, or null when invalid. Mirrors normalize_eg_phone() in the database.
String? normalizeEgPhone(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('0020')) d = d.substring(2);
  if (RegExp(r'^01[0125]\d{8}$').hasMatch(d)) return '2$d';
  if (RegExp(r'^201[0125]\d{8}$').hasMatch(d)) return d;
  return null;
}

String phoneLoginEmail(String normalized) => 'p$normalized@$phoneLoginDomain';

bool isPhoneLogin(String? email) => email?.endsWith('@$phoneLoginDomain') ?? false;

/// 201012345678 → 01012345678
String displayPhone(String? normalized) {
  if (normalized == null || normalized.isEmpty) return '';
  return normalized.startsWith('20') ? '0${normalized.substring(2)}' : normalized;
}

/// Turns what the user typed in the login box (email or phone) into the email Supabase expects.
String? loginEmailFrom(String input) {
  final v = input.trim();
  if (v.contains('@')) return v.toLowerCase();
  final p = normalizeEgPhone(v);
  return p == null ? null : phoneLoginEmail(p);
}

String? phoneValidator(String? v) =>
    normalizeEgPhone(v ?? '') == null ? tr('اكتب رقم موبايل مصري صحيح (11 رقم)', 'Enter a valid Egyptian mobile (11 digits)') : null;

String? passwordValidator(String? v) =>
    (v == null || v.length < 8) ? tr('كلمة السر لازم 8 حروف أو أرقام على الأقل', 'At least 8 characters') : null;

/// Easy-to-read password without confusing characters (no 0/O, 1/l).
String generatePassword() {
  const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Shows the new account's login details with copy and WhatsApp share.
Future<void> showCredentialsDialog(BuildContext context,
    {required String name, required String login, required String password, String? phoneForWhatsApp}) {
  final text = tr(
    'أهلاً $name\nتم إنشاء حسابك على تطبيق دكتوري.\nرقم الدخول: $login\nكلمة السر: $password\nتقدر تغيّر كلمة السر من «حسابي» بعد الدخول.',
    'Hello $name\nYour Doctori account is ready.\nLogin: $login\nPassword: $password\nYou can change the password from “My account”.',
  );
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
      title: Text(tr('تم إنشاء الحساب', 'Account created')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('سلّم البيانات دي لصاحب الحساب:', 'Give these details to the account owner:')),
        const SizedBox(height: 12),
        SelectableText('${tr('الدخول', 'Login')}: $login\n${tr('كلمة السر', 'Password')}: $password',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.8)),
      ]),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(tr('نسخ', 'Copy')),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (c.mounted) showMessage(c, tr('تم النسخ', 'Copied'));
          },
        ),
        if (phoneForWhatsApp != null)
          TextButton.icon(
            icon: const Icon(Icons.chat),
            label: Text(tr('واتساب', 'WhatsApp')),
            onPressed: () => launchUrl(
              Uri.parse('https://wa.me/$phoneForWhatsApp?text=${Uri.encodeComponent(text)}'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(c),
          child: Text(tr('تم', 'Done')),
        ),
      ],
    ),
  );
}

/// A password field with a "generate" button, used when creating accounts for others.
class NewPasswordField extends StatefulWidget {
  const NewPasswordField({super.key, required this.controller});
  final TextEditingController controller;
  @override
  State<NewPasswordField> createState() => _NewPasswordFieldState();
}

class _NewPasswordFieldState extends State<NewPasswordField> {
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        textDirection: TextDirection.ltr,
        validator: passwordValidator,
        decoration: InputDecoration(
          labelText: tr('كلمة السر (8 على الأقل)', 'Password (min 8)'),
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: TextButton(
            onPressed: () => setState(() => widget.controller.text = generatePassword()),
            child: Text(tr('توليد', 'Generate')),
          ),
        ),
      );
}

/// Opens WhatsApp with a ready message to an Egyptian mobile (any format), or tells the user the number is missing.
Future<void> openWhatsApp(BuildContext context, String? phone, String text) async {
  final p = normalizeEgPhone(phone ?? '');
  if (p == null) {
    showMessage(context, tr('رقم موبايل المريض مش متسجل أو غير صحيح.', 'The patient’s mobile number is missing or invalid.'),
        error: true);
    return;
  }
  final ok = await launchUrl(Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showMessage(context, tr('تعذر فتح واتساب', 'Could not open WhatsApp'), error: true);
}
