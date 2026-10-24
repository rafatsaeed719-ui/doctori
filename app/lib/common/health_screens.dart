import 'package:flutter/material.dart';

import '../core/live_sync.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

const bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
const _allergyHints = ['بنسلين', 'أسبرين', 'سلفا', 'بيض', 'لبن', 'فول سوداني', 'مأكولات بحرية', 'لاتكس'];
const _chronicHints = ['سكر', 'ضغط', 'قلب', 'ربو', 'غدة درقية', 'كلى', 'كبد', 'صرع', 'روماتيزم'];

List<String> _list(dynamic v) => (v as List? ?? const []).map((e) => '$e').toList();

/// Compact card at the top of a patient's file: blood type, allergies (red), chronic diseases.
class HealthCard extends StatefulWidget {
  const HealthCard({super.key, required this.patientId});
  final String? patientId;
  @override
  State<HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends State<HealthCard> with LiveReload<HealthCard> {
  @override
  void onLiveChange() => _load();

  Map<String, dynamic>? _h;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await rpc('get_health', {'p_patient': widget.patientId});
      if (mounted) setState(() => _h = Map<String, dynamic>.from(r as Map));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final h = _h;
    if (h == null) return const SizedBox.shrink();
    final allergies = _list(h['allergies']);
    final chronic = _list(h['chronic']);
    final empty = h['empty'] == true || (h['blood_type'] == null && allergies.isEmpty && chronic.isEmpty);
    return InkWell(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => HealthForm(patientId: widget.patientId)));
        _load();
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: allergies.isNotEmpty ? Tone.red.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: allergies.isNotEmpty ? Tone.red.withValues(alpha: 0.4) : Colors.transparent),
        ),
        child: empty
            ? Row(children: [
                const Icon(Icons.health_and_safety_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('البيانات الطبية الأساسية مش متسجلة — اضغط لإضافتها', 'Basic health data not filled — tap to add'))),
              ])
            : Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (h['blood_type'] != null) StatusChip('🩸 ${h['blood_type']}', color: Tone.red),
                for (final a in allergies) StatusChip('⚠️ ${tr('حساسية', 'Allergy')}: $a', color: Tone.red),
                for (final c in chronic) StatusChip(c, color: Tone.indigo),
                if (h['smoker'] == true) StatusChip(tr('مدخن', 'Smoker'), color: Colors.brown),
                if (h['pregnant'] == true) StatusChip(tr('حامل', 'Pregnant'), color: Tone.pink),
                const Icon(Icons.chevron_right, size: 18),
              ]),
      ),
    );
  }
}

class HealthForm extends StatefulWidget {
  const HealthForm({super.key, this.patientId});
  final String? patientId;
  @override
  State<HealthForm> createState() => _HealthFormState();
}

class _HealthFormState extends State<HealthForm> {
  String? _blood;
  final _allergies = <String>{};
  final _chronic = <String>{};
  final _meds = TextEditingController();
  final _surgeries = TextEditingController();
  final _family = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _eName = TextEditingController();
  final _ePhone = TextEditingController();
  bool? _smoker;
  bool? _pregnant;
  String? _gender;
  late final Future<void> _loaded = _load();

  Future<void> _load() async {
    final h = Map<String, dynamic>.from(await rpc('get_health', {'p_patient': widget.patientId}) as Map);
    _blood = h['blood_type'] as String?;
    _allergies.addAll(_list(h['allergies']));
    _chronic.addAll(_list(h['chronic']));
    _meds.text = h['medications'] as String? ?? '';
    _surgeries.text = h['past_surgeries'] as String? ?? '';
    _family.text = h['family_history'] as String? ?? '';
    _height.text = h['height_cm']?.toString() ?? '';
    _weight.text = h['weight_kg']?.toString() ?? '';
    _eName.text = h['emergency_name'] as String? ?? '';
    _ePhone.text = h['emergency_phone'] as String? ?? '';
    _smoker = h['smoker'] as bool?;
    _pregnant = h['pregnant'] as bool?;
    _gender = h['gender'] as String?;
  }

  Future<void> _save() async {
    final ok = await runBusy(context, () async {
      await rpc('save_health', {
        'p_patient': widget.patientId,
        'p_data': {
          'blood_type': _blood ?? '',
          'allergies': _allergies.toList(),
          'chronic': _chronic.toList(),
          'medications': _meds.text,
          'past_surgeries': _surgeries.text,
          'family_history': _family.text,
          'smoker': _smoker,
          'pregnant': _pregnant,
          'height_cm': _height.text.trim(),
          'weight_kg': _weight.text.trim(),
          'emergency_name': _eName.text,
          'emergency_phone': _ePhone.text,
        },
      });
    }, success: tr('اتحفظ ✓', 'Saved ✓'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _tags(String title, Set<String> set, List<String> hints, Color color) {
    final add = TextEditingController();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in {...hints, ...set})
              FilterChip(
                label: Text(x),
                selected: set.contains(x),
                selectedColor: color.withValues(alpha: 0.2),
                onSelected: (v) => setState(() => v ? set.add(x) : set.remove(x)),
              ),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: add, decoration: InputDecoration(hintText: tr('حاجة تانية…', 'Other…')))),
            IconButton(
              onPressed: () {
                if (add.text.trim().isNotEmpty) setState(() => set.add(add.text.trim()));
              },
              icon: const Icon(Icons.add_circle_rounded),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('البيانات الطبية الأساسية', 'Basic health data'))),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!));
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
            InfoBanner(icon: Icons.health_and_safety_outlined,
                text: tr('البيانات دي بتظهر لدكاترتك أول ما يفتحوا ملفك، خصوصاً الحساسية — ممكن تنقذ حياتك.',
                    'Your doctors see this first, especially allergies — it can save your life.')),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('فصيلة الدم', 'Blood type'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final b in bloodTypes)
                      ChoiceChip(label: Text(b), selected: _blood == b, onSelected: (v) => setState(() => _blood = v ? b : null)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _height, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                        decoration: InputDecoration(labelText: tr('الطول', 'Height'), suffixText: 'cm'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _weight, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                        decoration: InputDecoration(labelText: tr('الوزن', 'Weight'), suffixText: 'kg'))),
                  ]),
                ]),
              ),
            ),
            _tags(tr('⚠️ عندك حساسية من؟', '⚠️ Allergies'), _allergies, _allergyHints, Tone.red),
            _tags(tr('أمراض مزمنة', 'Chronic conditions'), _chronic, _chronicHints, Tone.indigo),
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  TextField(controller: _meds, maxLines: 2, decoration: InputDecoration(labelText: tr('أدوية بتاخدها باستمرار', 'Regular medicines'))),
                  const SizedBox(height: 8),
                  TextField(controller: _surgeries, maxLines: 2, decoration: InputDecoration(labelText: tr('عمليات عملتها قبل كده', 'Past surgeries'))),
                  const SizedBox(height: 8),
                  TextField(controller: _family, maxLines: 2,
                      decoration: InputDecoration(labelText: tr('أمراض في العيلة (أب، أم، إخوات)', 'Family history'))),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _smoker == true,
                      onChanged: (v) => setState(() => _smoker = v), title: Text(tr('مدخن', 'Smoker'))),
                  if (_gender != 'male')
                    SwitchListTile(contentPadding: EdgeInsets.zero, value: _pregnant == true,
                        onChanged: (v) => setState(() => _pregnant = v), title: Text(tr('حامل حالياً', 'Pregnant now'))),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('رقم طوارئ (حد من أهلك)', 'Emergency contact'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  TextField(controller: _eName, decoration: InputDecoration(labelText: tr('الاسم', 'Name'))),
                  TextField(controller: _ePhone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: tr('الموبايل', 'Mobile'))),
                ]),
              ),
            ),
          ]);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: Text(tr('حفظ', 'Save'))),
        ),
      ),
    );
  }
}
