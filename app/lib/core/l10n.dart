import 'package:flutter/material.dart';

/// Arabic-first bilingual text. Every UI string is written as tr('عربي', 'English'),
/// so a missing translation can never happen.
class L10n {
  static final locale = ValueNotifier<Locale>(const Locale('ar'));
  static bool get isAr => locale.value.languageCode == 'ar';
  static void set(String code) {
    final next = code == 'en' ? 'en' : 'ar';
    if (locale.value.languageCode != next) locale.value = Locale(next);
  }
}

String tr(String ar, String en) => L10n.isAr ? ar : en;

/// Picks name_ar / name_en (or any *_ar / *_en pair) from a row.
String trField(Map<String, dynamic>? row, String base) {
  if (row == null) return '';
  final ar = row['${base}_ar'] ?? row[base];
  final en = row['${base}_en'] ?? ar;
  return ((L10n.isAr ? ar : en) ?? '').toString();
}

const _weekdaysAr = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const _weekdaysEn = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/// 0 = Sunday, matching the database.
String weekdayName(int d) => (L10n.isAr ? _weekdaysAr : _weekdaysEn)[d.clamp(0, 6)];

/// '17:00:00' → '5:00 م' / '5:00 PM'
String formatTime(String? hhmmss) {
  if (hhmmss == null || hhmmss.length < 5) return '';
  final h = int.tryParse(hhmmss.substring(0, 2)) ?? 0;
  final m = hhmmss.substring(3, 5);
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final suffix = h < 12 ? tr('ص', 'AM') : tr('م', 'PM');
  return '$h12:$m $suffix';
}

String formatDate(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

String genderLabel(String? g) => switch (g) {
      'male' => tr('ذكر', 'Male'),
      'female' => tr('أنثى', 'Female'),
      _ => '',
    };

String scopeLabel(String? s) => switch (s) {
      'full' => tr('كل ملفي الطبي', 'My full medical file'),
      'own_uploads' => tr('ما أرسله لهذا الطبيب فقط', 'Only what I send to this doctor'),
      _ => tr('لا توجد مشاركة', 'No sharing'),
    };
