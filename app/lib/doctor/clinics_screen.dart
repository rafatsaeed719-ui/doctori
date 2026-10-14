import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../common/map_widgets.dart';
import '../core/l10n.dart';
import '../core/lookups.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

class ClinicsScreen extends StatefulWidget {
  const ClinicsScreen({super.key});
  @override
  State<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends State<ClinicsScreen> {
  int _key = 0;

  Future<void> _open([Map<String, dynamic>? clinic]) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ClinicEditScreen(clinic: clinic)));
    if (changed == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('عياداتي', 'My clinics'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: Text(tr('إضافة عيادة', 'Add clinic')),
      ),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => supa.from('clinics').select('*, clinic_hours(*)').eq('doctor_id', myId).order('created_at'),
        builder: (context, list, reload) => RefreshList(
          onRefresh: reload,
          children: list.isEmpty
              ? [
                  EmptyView(
                    icon: Icons.local_hospital_outlined,
                    title: tr('لا توجد عيادات', 'No clinics yet'),
                    subtitle: tr('أضف عيادتك وحدد موقعها ومواعيدها لتظهر للمرضى.', 'Add your clinic, location and hours so patients can find you.'),
                  ),
                ]
              : [
                  for (final c in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Icon(Icons.local_hospital,
                              color: c['is_active'] == true ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline),
                          title: Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            c['address'],
                            Lookups.governorateName(c['governorate_id'] as int?),
                            '${(c['clinic_hours'] as List?)?.length ?? 0} ${tr('فترة عمل', 'time slots')}',
                            if (c['lat'] == null) tr('⚠ لم يتم تحديد الموقع على الخريطة', '⚠ Map location not set'),
                            if (c['is_active'] != true) tr('(متوقفة)', '(inactive)'),
                          ].whereType<String>().where((s) => s.isNotEmpty).join('\n')),
                          isThreeLine: true,
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _open(c),
                        ),
                      ),
                    ),
                ],
        ),
      ),
    );
  }
}

class _Hour {
  _Hour(this.weekday, this.opens, this.closes);
  int weekday;
  TimeOfDay opens;
  TimeOfDay closes;
}

TimeOfDay _parse(String s) => TimeOfDay(hour: int.parse(s.substring(0, 2)), minute: int.parse(s.substring(3, 5)));
String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

class ClinicEditScreen extends StatefulWidget {
  const ClinicEditScreen({super.key, this.clinic});
  final Map<String, dynamic>? clinic;
  @override
  State<ClinicEditScreen> createState() => _ClinicEditScreenState();
}

class _ClinicEditScreenState extends State<ClinicEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.clinic?['name'] as String?);
  late final _address = TextEditingController(text: widget.clinic?['address'] as String?);
  late final _area = TextEditingController(text: widget.clinic?['area'] as String?);
  late final _phone = TextEditingController(text: widget.clinic?['phone'] as String?);
  late int? _gov = widget.clinic?['governorate_id'] as int?;
  late bool _active = widget.clinic?['is_active'] as bool? ?? true;
  LatLng? _point;
  final List<_Hour> _hours = [];

  bool get _isNew => widget.clinic == null;

  @override
  void initState() {
    super.initState();
    final c = widget.clinic;
    if (c != null && c['lat'] != null && c['lng'] != null) {
      _point = LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble());
    }
    for (final h in (c?['clinic_hours'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(h as Map);
      _hours.add(_Hour(m['weekday'] as int, _parse(m['opens_at'] as String), _parse(m['closes_at'] as String)));
    }
    _hours.sort((a, b) => a.weekday != b.weekday ? a.weekday.compareTo(b.weekday) : _mins(a.opens).compareTo(_mins(b.opens)));
  }

  Future<void> _pickLocation() async {
    final p = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: _point)));
    if (p != null) setState(() => _point = p);
  }

  Future<void> _addHour() async {
    int day = 0;
    var opens = const TimeOfDay(hour: 17, minute: 0);
    var closes = const TimeOfDay(hour: 21, minute: 0);
    final add = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(tr('إضافة فترة عمل', 'Add working hours')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: day,
              decoration: InputDecoration(labelText: tr('اليوم', 'Day')),
              items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(weekdayName(i)))],
              onChanged: (v) => setS(() => day = v ?? 0),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('من', 'From')),
              trailing: Text(opens.format(c)),
              onTap: () async {
                final t = await showTimePicker(context: c, initialTime: opens);
                if (t != null) setS(() => opens = t);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('إلى', 'To')),
              trailing: Text(closes.format(c)),
              onTap: () async {
                final t = await showTimePicker(context: c, initialTime: closes);
                if (t != null) setS(() => closes = t);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('إضافة', 'Add')),
            ),
          ],
        ),
      ),
    );
    if (add != true) return;
    if (_mins(closes) <= _mins(opens)) {
      if (mounted) showMessage(context, tr('وقت النهاية لازم يكون بعد وقت البداية', 'End time must be after start time'), error: true);
      return;
    }
    setState(() {
      _hours.add(_Hour(day, opens, closes));
      _hours.sort((a, b) => a.weekday != b.weekday ? a.weekday.compareTo(b.weekday) : _mins(a.opens).compareTo(_mins(b.opens)));
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_point == null) {
      final go = await confirmDialog(context,
          title: tr('الموقع غير محدد', 'Location not set'),
          body: tr('المرضى مش هيقدروا يلاقوا العيادة على الخريطة أو يفتحوا الاتجاهات. تحفظ بدون موقع؟',
              'Patients won’t find the clinic on the map or get directions. Save without a location?'),
          confirm: tr('حفظ بدون موقع', 'Save anyway'));
      if (!go || !mounted) return;
    }
    final data = {
      'doctor_id': myId,
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'area': _area.text.trim().isEmpty ? null : _area.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'governorate_id': _gov,
      'lat': _point?.latitude,
      'lng': _point?.longitude,
      'is_active': _active,
    };
    final ok = await runBusy(context, () async {
      String id;
      if (_isNew) {
        final row = await supa.from('clinics').insert(data).select('id').single();
        id = row['id'] as String;
      } else {
        id = widget.clinic!['id'] as String;
        await supa.from('clinics').update(data).eq('id', id);
        await supa.from('clinic_hours').delete().eq('clinic_id', id);
      }
      if (_hours.isNotEmpty) {
        await supa.from('clinic_hours').insert([
          for (final h in _hours)
            {'clinic_id': id, 'weekday': h.weekday, 'opens_at': _fmt(h.opens), 'closes_at': _fmt(h.closes)},
        ]);
      }
    }, success: tr('تم حفظ العيادة', 'Clinic saved'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final yes = await confirmDialog(context,
        title: tr('حذف العيادة؟', 'Delete clinic?'),
        body: tr('هيتم حذف العيادة ومواعيدها. لو مؤقتاً مقفولة، الأفضل توقفها بدل الحذف.',
            'The clinic and its hours will be deleted. If it is only temporarily closed, deactivate it instead.'),
        confirm: tr('حذف', 'Delete'),
        danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async {
      await supa.from('clinics').delete().eq('id', widget.clinic!['id']);
    }, success: tr('تم الحذف', 'Deleted'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? tr('عيادة جديدة', 'New clinic') : tr('تعديل العيادة', 'Edit clinic')),
        actions: [
          if (!_isNew) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline, color: cs.error)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _name, validator: requiredField,
              decoration: InputDecoration(labelText: tr('اسم العيادة *', 'Clinic name *'))),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _gov,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('المحافظة *', 'Governorate *')),
            items: [for (final g in Lookups.governorates) DropdownMenuItem<int?>(value: g['id'] as int, child: Text(trField(g, 'name')))],
            validator: (v) => v == null ? tr('اختر المحافظة', 'Choose a governorate') : null,
            onChanged: (v) => setState(() => _gov = v),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _area,
              decoration: InputDecoration(labelText: tr('المنطقة / الحي', 'Area / district'))),
          const SizedBox(height: 12),
          TextFormField(controller: _address, validator: requiredField, maxLines: 2,
              decoration: InputDecoration(labelText: tr('العنوان بالتفصيل *', 'Full address *'),
                  hintText: tr('الشارع، رقم العقار، الدور، علامة مميزة', 'Street, building, floor, landmark'))),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('تليفون العيادة', 'Clinic phone'))),
          SectionTitle(tr('الموقع على الخريطة', 'Map location')),
          if (_point != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 160,
                child: FlutterMap(
                  key: ValueKey(_point),
                  options: MapOptions(
                    initialCenter: _point!,
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    osmTiles(),
                    MarkerLayer(markers: [
                      Marker(point: _point!, width: 40, height: 40, alignment: Alignment.topCenter,
                          child: Icon(Icons.location_on, color: cs.error, size: 40)),
                    ]),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickLocation,
            icon: const Icon(Icons.map_outlined),
            label: Text(_point == null ? tr('تحديد الموقع على الخريطة', 'Set location on map') : tr('تعديل الموقع', 'Change location')),
          ),
          SectionTitle(tr('مواعيد العمل', 'Working hours')),
          if (_hours.isEmpty) Text(tr('لم تضف مواعيد بعد.', 'No hours added yet.')),
          for (final h in _hours)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(weekdayName(h.weekday)),
                subtitle: Text('${h.opens.format(context)} - ${h.closes.format(context)}'),
                trailing: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => _hours.remove(h))),
              ),
            ),
          OutlinedButton.icon(onPressed: _addHour, icon: const Icon(Icons.add), label: Text(tr('إضافة فترة عمل', 'Add hours'))),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: Text(tr('العيادة تعمل حالياً', 'Clinic is active')),
            subtitle: Text(tr('لو قفلتها، مش هتظهر للمرضى.', 'When off, it is hidden from patients.')),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: Text(tr('حفظ العيادة', 'Save clinic'))),
        ]),
      ),
    );
  }
}
