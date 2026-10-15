import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n.dart';

SupabaseClient get supa => Supabase.instance.client;
String get myId => supa.auth.currentUser!.id;

/// Calls a database function and returns its JSON result.
Future<dynamic> rpc(String fn, [Map<String, dynamic>? params]) =>
    supa.rpc(fn, params: params).timeout(const Duration(seconds: 25));

Future<List<Map<String, dynamic>>> rpcList(String fn, [Map<String, dynamic>? params]) async {
  final res = await rpc(fn, params);
  if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  return const [];
}

/// Shared app-wide state (role context and the admin-editable app name).
class AppState {
  static final appName = ValueNotifier<String>('دكتوري');

  /// The signed-in user's context (role, name, avatar, specialty…). Listen to rebuild headers.
  static final ctx = ValueNotifier<Map<String, dynamic>>(const {});
  static Map<String, dynamic> get context => ctx.value;
  static set context(Map<String, dynamic> v) => ctx.value = v;

  /// Merge a few fields (e.g. a new avatar_url) and notify listeners.
  static void updateContext(Map<String, dynamic> changes) => ctx.value = {...ctx.value, ...changes};

  static Future<void> loadAppName() async {
    try {
      final row = await supa.from('app_settings').select('value').eq('key', 'app_name').maybeSingle();
      final v = row?['value'];
      if (v is Map) {
        final name = (L10n.isAr ? v['ar'] : v['en']) ?? v['ar'];
        if (name is String && name.trim().isNotEmpty) appName.value = name;
      }
    } catch (_) {/* keep default */}
  }
}

/// Turns any server / network error into a clear message for the user.
String friendlyError(Object e) {
  if (e is SocketException || e is TimeoutException || e.toString().contains('ClientException')) {
    return tr('لا يوجد اتصال بالإنترنت أو السيرفر لا يستجيب. حاول مرة أخرى.',
        'No internet connection or the server is not responding. Please try again.');
  }
  final msg = switch (e) {
    AuthException a => a.message,
    PostgrestException p => p.message,
    StorageException s => s.message,
    _ => e.toString(),
  };
  final m = msg.toLowerCase();
  const map = <String, (String, String)>{
    'invalid login credentials': ('الإيميل أو كلمة السر غير صحيحة.', 'Wrong email or password.'),
    'email not confirmed': ('لم يتم تأكيد الإيميل بعد. افتح الرسالة التي وصلتك واضغط رابط التأكيد.',
        'Email not confirmed yet. Open the message we sent you and tap the link.'),
    'user already registered': ('هذا الإيميل مسجل بالفعل. سجّل الدخول أو استخدم «نسيت كلمة السر».',
        'This email is already registered. Log in or use “Forgot password”.'),
    'password should be at least': ('كلمة السر قصيرة. استخدم 8 حروف أو أرقام على الأقل.',
        'Password is too short. Use at least 8 characters.'),
    'rate limit': ('محاولات كثيرة. انتظر دقائق ثم حاول مرة أخرى.', 'Too many attempts. Wait a few minutes and try again.'),
    'a pending request already exists': ('لديك طلب قيد الانتظار لهذا الطبيب بالفعل.',
        'You already have a pending request with this doctor.'),
    'already linked to this doctor': ('أنت منضم بالفعل لعيادة هذا الطبيب.', 'You are already linked to this doctor.'),
    'doctor is not available for new patients': ('هذا الطبيب لا يستقبل مرضى جدداً حالياً.',
        'This doctor is not accepting new patients right now.'),
    'too many pending requests': ('لديك طلبات كثيرة قيد الانتظار. انتظر رد الأطباء أولاً.',
        'You have too many pending requests. Wait for doctors to reply first.'),
    'daily request limit reached': ('وصلت للحد اليومي للطلبات. حاول غداً.', 'Daily request limit reached. Try tomorrow.'),
    'request already handled': ('تم الرد على هذا الطلب بالفعل.', 'This request was already handled.'),
    'only active patients': ('هذه الخدمة للمرضى فقط.', 'This is available to patients only.'),
    'doctor account is not active': ('حسابك كطبيب لم يتم توثيقه بعد.', 'Your doctor account is not verified yet.'),
    'admin only': ('هذه العملية للمدير فقط.', 'Admins only.'),
    'verification and rating fields': ('لا يمكن تعديل حالة التوثيق أو التقييم.', 'Verification and rating cannot be edited.'),
    'row-level security': ('ليس لديك صلاحية لهذه العملية.', 'You do not have permission for this action.'),
    'permission denied': ('ليس لديك صلاحية لهذه العملية.', 'You do not have permission for this action.'),
    'no activation code yet': ('لسه ما اتبعتلكش كود تفعيل. اطلبه على واتساب الأول.',
        'No activation code yet. Request it on WhatsApp first.'),
    'activation code expired': ('الكود انتهت صلاحيته (7 أيام). اطلب كود جديد.', 'The code expired (7 days). Request a new one.'),
    'too many wrong attempts': ('محاولات غلط كتير. اطلب كود جديد من الإدارة.', 'Too many wrong attempts. Ask for a new code.'),
    'code already used': ('الكود ده اتستخدم قبل كده.', 'This code was already used.'),
    'invalid phone number': ('رقم الموبايل غير صحيح. اكتب رقم مصري 11 رقم.', 'Invalid mobile number. Use an 11-digit Egyptian number.'),
    'account already exists': ('فيه حساب مسجل بالرقم أو الإيميل ده بالفعل.', 'An account with this mobile or email already exists.'),
    'payload too large': ('الملف أكبر من الحد المسموح (10 ميجا).', 'File is larger than the 10 MB limit.'),
    'mime type': ('نوع الملف غير مسموح. المسموح: JPG وPNG وPDF.', 'File type not allowed. Use JPG, PNG or PDF.'),
  };
  for (final entry in map.entries) {
    if (m.contains(entry.key)) return tr(entry.value.$1, entry.value.$2);
  }
  if (kDebugMode) return msg;
  return tr('حدث خطأ غير متوقع. حاول مرة أخرى.', 'Something went wrong. Please try again.');
}

/// Short technical description of an error (code + message) for support screenshots.
String errorDetails(Object e) => switch (e) {
      PostgrestException p => '${p.code ?? ''} ${p.message}'.trim(),
      AuthException a => 'auth ${a.statusCode ?? ''} ${a.message}'.trim(),
      StorageException s => 'storage ${s.statusCode ?? ''} ${s.message}'.trim(),
      _ => e.toString(),
    };

/// Re-reads the signed-in user's context (e.g. after changing specialty or photo).
Future<void> refreshMyContext() async {
  try {
    final r = await rpc('get_my_context');
    if (r is Map) AppState.context = Map<String, dynamic>.from(r);
  } catch (_) {/* keep the old context */}
}
