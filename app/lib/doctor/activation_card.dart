import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Reads the admin's WhatsApp number from the platform settings.
Future<String?> adminWhatsApp() async {
  try {
    final row = await supa.from('app_settings').select('value').eq('key', 'admin_whatsapp').maybeSingle();
    final v = row?['value'];
    return v is String && v.isNotEmpty ? v : null;
  } catch (_) {
    return null;
  }
}

/// Doctor-side activation: ask for a code on WhatsApp, then enter it.
class ActivationCard extends StatelessWidget {
  const ActivationCard({super.key, required this.doctor, required this.onActivated});
  final Map<String, dynamic> doctor;
  final Future<void> Function() onActivated;

  Future<void> _requestCode(BuildContext context) async {
    final number = await adminWhatsApp();
    if (number == null) {
      if (context.mounted) {
        showMessage(context, tr('رقم واتساب الإدارة غير متاح حالياً.', 'Admin WhatsApp number is not set.'), error: true);
      }
      return;
    }
    final ctx = AppState.context;
    final phone = displayPhone(ctx['phone'] as String?);
    final specialty = ctx['specialty_ar'] ?? '';
    final license = doctor['license_number'] ?? '';
    final text = [
      'السلام عليكم، أنا د. ${ctx['full_name'] ?? ''}',
      if ('$specialty'.isNotEmpty) 'التخصص: $specialty',
      if (phone.isNotEmpty) 'رقم الموبايل: $phone',
      if ('$license'.isNotEmpty) 'رقم الترخيص: $license',
      'سجلت في تطبيق دكتوري وبرجاء إرسال كود التفعيل.',
    ].join('\n');
    final ok = await launchUrl(Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showMessage(context, tr('تعذر فتح واتساب.', 'Could not open WhatsApp.'), error: true);
    }
  }

  Future<void> _enterCode(BuildContext context) async {
    final ctl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon3D(Icons.key_rounded, color: Tone.amber, size: 52),
        title: Text(tr('كود التفعيل', 'Activation code')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLength: 6,
          style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(hintText: '------', counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('تفعيل', 'Activate')),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    Map<String, dynamic>? result;
    final done = await runBusy(context, () async {
      final r = await rpc('doctor_activate_with_code', {'p_code': ctl.text.trim()});
      result = r is Map ? Map<String, dynamic>.from(r) : null;
    });
    if (!done || !context.mounted) return;
    if (result?['ok'] == true) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon3D(Icons.verified_rounded, color: Tone.green, size: 60),
          title: Text(tr('تم تفعيل حسابك 🎉', 'Account activated 🎉')),
          content: Text(tr('حسابك دلوقتي ظاهر للمرضى في البحث، وتقدر تستقبل طلبات وتضيف مرضى.',
              'You are now visible to patients and can receive requests and add patients.')),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('يلا بينا', 'Let’s go')))],
        ),
      );
      await refreshMyContext();
      await onActivated();
    } else {
      final left = result?['attempts_left'];
      showMessage(context,
          tr('الكود غلط. فاضل $left محاولات.', 'Wrong code. $left attempts left.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon3D(Icons.verified_user_rounded, color: Tone.green, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('فعّل حسابك', 'Activate your account'),
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              Text(tr('اطلب الكود من الإدارة على واتساب، وبعدين اكتبه هنا.',
                  'Ask the admin for a code on WhatsApp, then enter it here.'),
                  style: tt.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
          onPressed: () => _requestCode(context),
          icon: const Icon(Icons.chat_rounded),
          label: Text(tr('① اطلب كود التفعيل على واتساب', '① Request code on WhatsApp')),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _enterCode(context),
          icon: const Icon(Icons.key_rounded),
          label: Text(tr('② عندي الكود، فعّل حسابي', '② I have the code — activate')),
        ),
      ]),
    );
  }
}
