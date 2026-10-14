import 'l10n.dart';
import 'supa.dart';

/// Cached reference lists (specialties, governorates) managed by the admin.
class Lookups {
  static List<Map<String, dynamic>> specialties = const [];
  static List<Map<String, dynamic>> governorates = const [];
  static bool _loaded = false;

  static Future<void> ensure({bool force = false}) async {
    if (_loaded && !force) return;
    specialties = await supa.from('specialties').select().eq('is_active', true).order('sort_order');
    governorates = await supa.from('governorates').select().order('id');
    _loaded = true;
  }

  static String specialtyName(int? id) {
    if (id == null) return '';
    for (final s in specialties) {
      if (s['id'] == id) return trField(s, 'name');
    }
    return '';
  }

  static String governorateName(int? id) {
    if (id == null) return '';
    for (final g in governorates) {
      if (g['id'] == id) return trField(g, 'name');
    }
    return '';
  }
}
