import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/avatar.dart';
import '../core/backgrounds.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../patient/meds_screen.dart' show medForms, medFormInfo;

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String rxEveryLabel(int? h) => switch (h) {
      4 => 'كل 4 ساعات',
      6 => 'كل 6 ساعات',
      8 => 'كل 8 ساعات (3 مرات يومياً)',
      12 => 'كل 12 ساعة (مرتين يومياً)',
      24 => 'مرة واحدة يومياً',
      _ => 'عند اللزوم',
    };

String _date(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  return '${d.day}/${d.month}/${d.year}';
}

// ===========================================================================
// PDF (A5) — styled by the doctor's specialty colour and symbols
// ===========================================================================
Future<Uint8List> _emojiPng(String e, {int size = 120}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final tp = TextPainter(text: TextSpan(text: e, style: TextStyle(fontSize: size * 0.78)), textDirection: TextDirection.ltr)
    ..layout();
  tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
  final img = await rec.endRecording().toImage(size, size);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

PdfColor _pc(Color c) => PdfColor.fromInt(c.toARGB32());

Future<Uint8List> buildRxPdf(Map<String, dynamic> rx, Map<String, dynamic> header) async {
  final look = specialtyLook(header['specialty_en'] as String?);
  final accent = _pc(look.accent);
  final soft = _pc(lighten(look.accent, 0.88));
  final dark = _pc(darken(look.accent, 0.35));
  final settings = Map<String, dynamic>.from(header['settings'] as Map? ?? const {});
  final clinics = (header['clinics'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final clinic = clinics.where((c) => c['id'] == rx['clinic_id']).firstOrNull ?? clinics.firstOrNull;
  final items = (rx['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  final regular = await PdfGoogleFonts.cairoRegular();
  final bold = await PdfGoogleFonts.cairoBold();
  final symbols = [for (final e in look.emojis.take(4)) pw.MemoryImage(await _emojiPng(e))];
  pw.ImageProvider? logo;
  final logoUrl = settings['logo_url'] as String?;
  if (logoUrl != null && logoUrl.isNotEmpty) {
    try {
      logo = await networkImage(logoUrl);
    } catch (_) {}
  }
  if (logo == null && (header['avatar_url'] as String?)?.isNotEmpty == true) {
    try {
      logo = await networkImage(header['avatar_url'] as String);
    } catch (_) {}
  }

  final doc = pw.Document(title: 'Rx', author: header['doctor_name'] as String?);
  pw.TextStyle st(double size, {bool b = false, PdfColor? color}) =>
      pw.TextStyle(font: b ? bold : regular, fontSize: size, color: color ?? PdfColors.grey900);

  doc.addPage(pw.Page(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(22),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      buildBackground: (ctx) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Stack(children: [
          // faint specialty symbols scattered behind the text
          for (var i = 0; i < 9; i++)
            pw.Positioned(
              left: 30.0 + (i % 3) * 140 + (i ~/ 3 % 2) * 50,
              top: 190.0 + (i ~/ 3) * 120,
              child: pw.Opacity(opacity: 0.06, child: pw.Image(symbols[i % symbols.length], width: 70)),
            ),
          pw.Positioned(
            left: 0, right: 0, bottom: 0,
            child: pw.Container(height: 8, color: accent),
          ),
        ]),
      ),
    ),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      // ---------- header ----------
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(14)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('د. ${header['doctor_name'] ?? ''}', style: st(17, b: true, color: PdfColors.white)),
              pw.Text([header['title'], header['specialty_ar']].whereType<String>().where((s) => s.isNotEmpty).join(' — '),
                  style: st(10.5, color: PdfColors.white)),
              if ((settings['header_line'] as String?)?.isNotEmpty == true)
                pw.Text(settings['header_line'] as String, style: st(9, color: PdfColors.white)),
            ]),
          ),
          pw.SizedBox(width: 8),
          pw.Container(
            width: 58,
            height: 58,
            padding: const pw.EdgeInsets.all(4),
            decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle),
            child: pw.ClipOval(child: logo != null ? pw.Image(logo, fit: pw.BoxFit.cover) : pw.Image(symbols.first)),
          ),
        ]),
      ),
      pw.SizedBox(height: 10),
      // ---------- patient ----------
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(color: soft, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text('الاسم: ${rx['patient_name'] ?? ''}', style: st(10.5, b: true))),
          if ((rx['patient_age'] as String?)?.isNotEmpty == true) pw.Text('السن: ${rx['patient_age']}   ', style: st(10)),
          pw.Text('التاريخ: ${_date(rx['created_at'] as String? ?? DateTime.now().toIso8601String())}', style: st(10)),
        ]),
      ),
      if ((rx['diagnosis'] as String?)?.isNotEmpty == true) ...[
        pw.SizedBox(height: 6),
        pw.Text('التشخيص: ${rx['diagnosis']}', style: st(10.5)),
      ],
      pw.SizedBox(height: 8),
      pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Text('Rx', style: pw.TextStyle(font: bold, fontSize: 28, color: accent)),
      ),
      // ---------- medicines ----------
      for (var i = 0; i < items.length; i++)
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 7),
          padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(right: pw.BorderSide(color: accent, width: 3)),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [
              pw.Text('${i + 1}. ', style: st(12, b: true, color: accent)),
              pw.Expanded(child: pw.Text('${items[i]['name'] ?? ''}', style: st(12, b: true))),
              if (items[i]['form'] != null) pw.Text(medFormInfo(items[i]['form'] as String?).$2, style: st(9, color: dark)),
            ]),
            pw.Text(
              [
                if ((items[i]['dose'] as String?)?.isNotEmpty == true) items[i]['dose'],
                rxEveryLabel((items[i]['every_hours'] as num?)?.toInt()),
                if (items[i]['days'] != null && '${items[i]['days']}'.isNotEmpty) 'لمدة ${items[i]['days']} يوم',
              ].join(' — '),
              style: st(10),
            ),
            if ((items[i]['instructions'] as String?)?.isNotEmpty == true)
              pw.Text('${items[i]['instructions']}', style: st(9.5, color: PdfColors.grey700)),
          ]),
        ),
      if ((rx['notes'] as String?)?.isNotEmpty == true) ...[
        pw.SizedBox(height: 4),
        pw.Text('ملاحظات: ${rx['notes']}', style: st(10)),
      ],
      if (rx['next_visit'] != null) ...[
        pw.SizedBox(height: 4),
        pw.Text('ميعاد الاستشارة / المتابعة: ${_date(rx['next_visit'] as String?)}', style: st(10.5, b: true, color: dark)),
      ],
      pw.Spacer(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Column(children: [
          pw.Container(width: 110, height: 0.8, color: PdfColors.grey600),
          pw.Text('توقيع الطبيب', style: st(8.5, color: PdfColors.grey700)),
        ]),
      ]),
      pw.SizedBox(height: 6),
      // ---------- footer: clinic and contact ----------
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(color: soft, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (clinic != null)
            pw.Text(
              '${clinic['name'] ?? ''}: ${[clinic['address'], clinic['area'], clinic['city'], clinic['governorate']].whereType<String>().where((s) => s.isNotEmpty).join('، ')}',
              style: st(9, b: true, color: dark),
            ),
          pw.Text(
            [
              if ((clinic?['phone'] as String?)?.isNotEmpty == true) 'تليفون العيادة: ${clinic!['phone']}',
              if ((settings['phone'] as String?)?.isNotEmpty == true) 'للحجز: ${settings['phone']}',
              if ((settings['whatsapp'] as String?)?.isNotEmpty == true) 'واتساب: ${settings['whatsapp']}',
            ].join('   •   '),
            style: st(8.5),
          ),
          if ((settings['footer_line'] as String?)?.isNotEmpty == true) pw.Text(settings['footer_line'] as String, style: st(8.5)),
        ]),
      ),
    ]),
  ));
  return doc.save();
}

/// Full-screen preview with print and share (WhatsApp, email, save as PDF).
class RxPreviewScreen extends StatelessWidget {
  const RxPreviewScreen({super.key, required this.rx, this.header});
  final Map<String, dynamic> rx;
  final Map<String, dynamic>? header;

  Future<Map<String, dynamic>> _header() async {
    if (header != null) return header!;
    final h = await rpc('rx_header', {'p_doctor': rx['doctor_id']});
    return Map<String, dynamic>.from(h as Map);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('الروشتة', 'Prescription'))),
      body: FutureView<Map<String, dynamic>>(
        load: _header,
        builder: (context, h, _) => PdfPreview(
          build: (_) => buildRxPdf(rx, h),
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          allowPrinting: true,
          allowSharing: true,
          pdfFileName: 'roshetta_${(rx['patient_name'] as String? ?? '').replaceAll(' ', '_')}.pdf',
          onError: (context, e) => ErrorView(
            message: tr('تعذر تجهيز الروشتة. تأكد من الإنترنت أول مرة (لتحميل الخط العربي).',
                'Could not prepare the prescription. Connect to the internet the first time (to load the Arabic font).'),
            details: '$e',
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Composer
// ===========================================================================
class _Item {
  final name = TextEditingController();
  final dose = TextEditingController();
  final days = TextEditingController();
  final instructions = TextEditingController();
  String? form;
  int? every = 8;
  Map<String, dynamic> toJson() => {
        'name': name.text.trim(),
        if (form != null) 'form': form,
        'dose': dose.text.trim(),
        if (every != null) 'every_hours': every,
        if (int.tryParse(days.text.trim()) != null) 'days': int.parse(days.text.trim()),
        'instructions': instructions.text.trim(),
      };
}

class RxComposer extends StatefulWidget {
  const RxComposer({super.key, this.patientId, this.patientName});
  final String? patientId;
  final String? patientName;
  @override
  State<RxComposer> createState() => _RxComposerState();
}

class _RxComposerState extends State<RxComposer> {
  late String? _patientId = widget.patientId;
  late final _name = TextEditingController(text: widget.patientName);
  final _age = TextEditingController();
  final _diagnosis = TextEditingController();
  final _notes = TextEditingController();
  final _items = [_Item()];
  String? _clinic;
  DateTime? _next;
  bool _addToMeds = true;
  Map<String, dynamic>? _header;

  @override
  void initState() {
    super.initState();
    rpc('rx_header', {'p_doctor': actingDoctorId()}).then((h) {
      if (!mounted || h is! Map) return;
      setState(() {
        _header = Map<String, dynamic>.from(h);
        final clinics = _header!['clinics'] as List? ?? const [];
        if (clinics.isNotEmpty) _clinic = (clinics.first as Map)['id'] as String?;
      });
    }).catchError((_) {});
  }

  Future<void> _pickPatient() async {
    List<Map<String, dynamic>> patients;
    try {
      patients = await rpcList('doctor_my_patients', {'p_doctor': actingDoctorId()});
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    final p = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.65),
          child: patients.isEmpty
              ? Padding(padding: const EdgeInsets.all(24), child: Text(tr('مفيش مرضى في العيادة لسه.', 'No patients yet.')))
              : ListView(shrinkWrap: true, children: [
                  for (final x in patients)
                    ListTile(
                      leading: UserAvatar(url: x['avatar_url'] as String?, name: x['patient_name'] as String?, radius: 18),
                      title: Text(x['patient_name'] ?? ''),
                      subtitle: Text(displayPhone(x['phone'] as String?)),
                      onTap: () => Navigator.pop(c, x),
                    ),
                ]),
        ),
      ),
    );
    if (p == null) return;
    setState(() {
      _patientId = p['patient_id'] as String;
      _name.text = p['patient_name'] as String? ?? '';
      if (p['age'] != null) _age.text = '${p['age']}';
    });
  }

  Future<void> _save() async {
    final items = [for (final i in _items) if (i.name.text.trim().isNotEmpty) i.toJson()];
    if (items.isEmpty) {
      showMessage(context, tr('اكتب دوا واحد على الأقل', 'Add at least one medicine'), error: true);
      return;
    }
    if (_patientId == null && _name.text.trim().length < 2) {
      showMessage(context, tr('اكتب اسم المريض', 'Enter the patient name'), error: true);
      return;
    }
    String? id;
    final ok = await runBusy(context, () async {
      id = await rpc('create_prescription', {
        'p_patient': _patientId,
        'p_patient_name': _name.text.trim(),
        'p_items': items,
        'p_diagnosis': _diagnosis.text.trim(),
        'p_notes': _notes.text.trim(),
        'p_clinic': _clinic,
        'p_next_visit': _next == null ? null : _iso(_next!),
        'p_add_to_meds': _addToMeds,
        'p_patient_age': _age.text.trim(),
        'p_doctor': actingDoctorId(),
      }) as String?;
    }, success: _patientId != null ? tr('الروشتة وصلت للمريض ✓', 'Prescription sent to the patient ✓') : null);
    if (!ok || !mounted) return;
    final rx = {
      'id': id,
      'doctor_id': actingDoctorId(),
      'patient_id': _patientId,
      'patient_name': _name.text.trim(),
      'patient_age': _age.text.trim(),
      'clinic_id': _clinic,
      'diagnosis': _diagnosis.text.trim(),
      'items': items,
      'notes': _notes.text.trim(),
      'next_visit': _next == null ? null : _iso(_next!),
      'created_at': DateTime.now().toIso8601String(),
    };
    await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RxPreviewScreen(rx: rx, header: _header)));
  }

  @override
  Widget build(BuildContext context) {
    final clinics = (_header?['clinics'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final accent = specialtyLook(_header?['specialty_en'] as String?).accent;
    return Scaffold(
      appBar: AppBar(title: Text(tr('روشتة جديدة', 'New prescription'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 110), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    readOnly: _patientId != null,
                    decoration: InputDecoration(
                      labelText: tr('اسم المريض', 'Patient name'),
                      prefixIcon: _patientId != null ? const Icon(Icons.verified_user_rounded, color: Tone.green) : null,
                      suffixIcon: _patientId != null && widget.patientId == null
                          ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
                                _patientId = null;
                                _name.clear();
                              }))
                          : null,
                    ),
                  ),
                ),
                if (widget.patientId == null) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(tooltip: tr('من مرضاي', 'From my patients'), onPressed: _pickPatient,
                      icon: const Icon(Icons.people_alt_rounded)),
                ],
              ]),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(width: 110, child: TextField(controller: _age, decoration: InputDecoration(labelText: tr('السن', 'Age')))),
                const SizedBox(width: 8),
                if (clinics.length > 1)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _clinic,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('العيادة', 'Clinic')),
                      items: [for (final c in clinics) DropdownMenuItem(value: c['id'] as String, child: Text('${c['name']}'))],
                      onChanged: (v) => setState(() => _clinic = v),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _diagnosis, decoration: InputDecoration(labelText: tr('التشخيص', 'Diagnosis'))),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Row(children: [
            Text('Rx', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: accent)),
            const SizedBox(width: 8),
            Text(tr('الأدوية', 'Medicines'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ]),
        ),
        for (var i = 0; i < _items.length; i++) _itemCard(i, accent),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => setState(() => _items.add(_Item())),
          icon: const Icon(Icons.add),
          label: Text(tr('دوا كمان', 'Another medicine')),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(controller: _notes, maxLines: 2, maxLength: 1500,
                  decoration: InputDecoration(labelText: tr('ملاحظات / تعليمات عامة', 'Notes'))),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_repeat_rounded),
                title: Text(tr('ميعاد الاستشارة / المتابعة', 'Next visit')),
                subtitle: Text(_next == null ? tr('مش محدد', 'Not set') : formatDate(_next!.toIso8601String())),
                trailing: _next == null ? null : IconButton(onPressed: () => setState(() => _next = null), icon: const Icon(Icons.close)),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) setState(() => _next = d);
                },
              ),
              if (_patientId != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _addToMeds,
                  onChanged: (v) => setState(() => _addToMeds = v),
                  title: Text(tr('ضيف الأدوية لـ«علاجي» عند المريض', 'Add to the patient’s «My treatment»')),
                  subtitle: Text(tr('والتذكير بالمواعيد يشتغل على موبايله', 'with dose reminders on their phone')),
                ),
            ]),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _save,
            icon: Icon(_patientId != null ? Icons.send_rounded : Icons.print_rounded),
            label: Text(_patientId != null ? tr('إرسال للمريض وطباعة', 'Send & print') : tr('حفظ وطباعة', 'Save & print')),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(int i, Color accent) {
    final it = _items[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            CircleAvatar(radius: 14, backgroundColor: accent,
                child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(controller: it.name, decoration: InputDecoration(labelText: tr('اسم الدوا', 'Medicine name'))),
            ),
            if (_items.length > 1)
              IconButton(onPressed: () => setState(() => _items.removeAt(i)), icon: const Icon(Icons.delete_outline)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final f in medForms)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text('${medFormInfo(f).$1} ${medFormInfo(f).$2}'),
                    selected: it.form == f,
                    onSelected: (v) => setState(() => it.form = v ? f : null),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: it.dose,
                decoration: InputDecoration(labelText: tr('الجرعة', 'Dose'), hintText: tr('قرص / 5 مل', '1 tab / 5 ml')))),
            const SizedBox(width: 8),
            SizedBox(width: 90, child: TextField(controller: it.days, keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('أيام', 'Days')))),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            initialValue: it.every,
            decoration: InputDecoration(labelText: tr('كل قد إيه', 'How often')),
            items: [
              for (final h in [4, 6, 8, 12, 24]) DropdownMenuItem<int?>(value: h, child: Text(rxEveryLabel(h))),
              DropdownMenuItem<int?>(value: null, child: Text(rxEveryLabel(null))),
            ],
            onChanged: (v) => setState(() => it.every = v),
          ),
          const SizedBox(height: 8),
          TextField(controller: it.instructions,
              decoration: InputDecoration(labelText: tr('تعليمات', 'Instructions'), hintText: tr('بعد الأكل', 'after meals'))),
        ]),
      ),
    );
  }
}

// ===========================================================================
// Lists
// ===========================================================================
/// [patientId] = doctor viewing one patient; [doctorAll] = doctor's recent prescriptions; neither = my own (patient).
class PrescriptionsView extends StatefulWidget {
  const PrescriptionsView({super.key, this.patientId, this.patientName, this.doctorAll = false});
  final String? patientId;
  final String? patientName;
  final bool doctorAll;
  @override
  State<PrescriptionsView> createState() => _PrescriptionsViewState();
}

class _PrescriptionsViewState extends State<PrescriptionsView> {
  int _key = 0;
  bool get _doctor => widget.patientId != null || widget.doctorAll;

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await rpc('list_prescriptions', {
      'p_patient': widget.patientId,
      'p_doctor': _doctor ? actingDoctorId() : null,
    });
    return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _new() async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => RxComposer(patientId: widget.patientId, patientName: widget.patientName)));
    setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureView<List<Map<String, dynamic>>>(
      key: ValueKey(_key),
      load: _load,
      builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
        if (list.isEmpty)
          EmptyView(icon: Icons.receipt_long_rounded, title: tr('مفيش روشتات', 'No prescriptions'),
              subtitle: _doctor ? null : tr('الروشتات اللي يكتبهالك الدكتور هتظهر هنا وتقدر تطبعها أو تبعتها.',
                  'Prescriptions from your doctor appear here to print or share.')),
        for (final rx in list) _RxTile(rx: rx, showPatient: _doctor, showDoctor: !_doctor),
      ]),
    );
    if (!_doctor) return body;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: can('medical')
          ? FloatingActionButton.extended(heroTag: 'rx', onPressed: _new,
              icon: const Icon(Icons.edit_note_rounded), label: Text(tr('روشتة جديدة', 'New prescription')))
          : null,
      body: body,
    );
  }
}

class _RxTile extends StatelessWidget {
  const _RxTile({required this.rx, required this.showPatient, required this.showDoctor});
  final Map<String, dynamic> rx;
  final bool showPatient;
  final bool showDoctor;

  @override
  Widget build(BuildContext context) {
    final accent = specialtyLook(rx['specialty_en'] as String?).accent;
    final items = (rx['items'] as List? ?? const []);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Icon3D(null, color: accent, size: 46, emoji: 'Rx'),
        title: Text(
          [
            if (showPatient) rx['patient_name'],
            if (showDoctor) '${tr('د.', 'Dr.')} ${rx['doctor_name'] ?? ''}',
            if ((rx['diagnosis'] as String?)?.isNotEmpty == true) rx['diagnosis'],
          ].whereType<String>().join(' — '),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${formatDate(rx['created_at'] as String?)} • '
            '${items.map((e) => (e as Map)['name']).whereType<String>().join('، ')}',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.print_rounded),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RxPreviewScreen(rx: rx))),
      ),
    );
  }
}

/// Doctor: write a prescription, see recent ones, and set up the prescription look.
class DoctorRxScreen extends StatelessWidget {
  const DoctorRxScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('الروشتات', 'Prescriptions')), actions: [
        if (!isAssistant)
          IconButton(
            tooltip: tr('شكل الروشتة واللوجو', 'Prescription look & logo'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RxSettingsScreen())),
            icon: const Icon(Icons.palette_outlined),
          ),
      ]),
      body: const PrescriptionsView(doctorAll: true),
    );
  }
}

/// Patient: «روشتاتي».
class MyPrescriptionsScreen extends StatelessWidget {
  const MyPrescriptionsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('روشتاتي', 'My prescriptions'))),
        body: const PrescriptionsView(),
      );
}

// ===========================================================================
// Prescription look: logo + contact lines
// ===========================================================================
class RxSettingsScreen extends StatefulWidget {
  const RxSettingsScreen({super.key});
  @override
  State<RxSettingsScreen> createState() => _RxSettingsScreenState();
}

class _RxSettingsScreenState extends State<RxSettingsScreen> {
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _headerLine = TextEditingController();
  final _footerLine = TextEditingController();
  String? _logo;
  Map<String, dynamic>? _header;
  late final Future<void> _loaded = _load();

  Future<void> _load() async {
    final h = Map<String, dynamic>.from(await rpc('rx_header') as Map);
    final s = Map<String, dynamic>.from(h['settings'] as Map? ?? const {});
    _header = h;
    _logo = s['logo_url'] as String?;
    _phone.text = s['phone'] as String? ?? h['public_phone'] as String? ?? '';
    _whatsapp.text = s['whatsapp'] as String? ?? '';
    _headerLine.text = s['header_line'] as String? ?? '';
    _footerLine.text = s['footer_line'] as String? ?? '';
  }

  Map<String, dynamic> get _settings => {
        if (_logo != null) 'logo_url': _logo,
        'phone': _phone.text.trim(),
        'whatsapp': _whatsapp.text.trim(),
        'header_line': _headerLine.text.trim(),
        'footer_line': _footerLine.text.trim(),
      };

  Future<void> _pickLogo() async {
    final x = await ImagePickerHelper.pick(context);
    if (x == null || !mounted) return;
    await runBusy(context, () async {
      final path = '$myId/rx_logo_${DateTime.now().millisecondsSinceEpoch}.png';
      await supa.storage.from('avatars').uploadBinary(path, x, fileOptions: const FileOptions(contentType: 'image/png'));
      setState(() => _logo = supa.storage.from('avatars').getPublicUrl(path));
    });
  }

  Future<void> _save({bool preview = false}) async {
    final ok = await runBusy(context, () async {
      await rpc('set_rx_settings', {'p_settings': _settings});
    }, success: preview ? null : tr('تم الحفظ ✓', 'Saved ✓'));
    if (!ok || !mounted) return;
    if (preview) {
      final h = {...?_header, 'settings': _settings};
      Navigator.push(context, MaterialPageRoute(builder: (_) => RxPreviewScreen(header: h, rx: {
            'patient_name': tr('اسم المريض', 'Patient name'),
            'patient_age': '35',
            'diagnosis': tr('مثال للتشخيص', 'Sample diagnosis'),
            'items': [
              {'name': 'Panadol Extra', 'form': 'tablet', 'dose': 'قرص', 'every_hours': 8, 'days': 5, 'instructions': 'بعد الأكل'},
              {'name': 'Vitamin C 1000', 'form': 'sachet', 'dose': 'كيس', 'every_hours': 24, 'days': 10},
            ],
            'created_at': DateTime.now().toIso8601String(),
          })));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('شكل الروشتة', 'Prescription look'))),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!));
          final look = specialtyLook(_header?['specialty_en'] as String?);
          return ListView(padding: const EdgeInsets.all(16), children: [
            InfoBanner(icon: Icons.palette_outlined, color: look.accent,
                text: tr('ألوان ورسومات الروشتة بتتظبط لوحدها حسب تخصصك. ضيف لوجو العيادة وأرقام التواصل، وعنوان العيادة بيتاخد من «عياداتي».',
                    'Colours and symbols follow your specialty. Add your clinic logo and contacts; the address comes from «My clinics».')),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: _pickLogo,
                child: Column(children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: lighten(look.accent, 0.8),
                    backgroundImage: _logo != null ? NetworkImage(_logo!) : null,
                    child: _logo == null ? Text(look.emojis.first, style: const TextStyle(fontSize: 40)) : null,
                  ),
                  const SizedBox(height: 6),
                  Text(_logo == null ? tr('اضغط لإضافة لوجو العيادة', 'Tap to add the clinic logo') : tr('تغيير اللوجو', 'Change logo'),
                      style: TextStyle(color: look.accent, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            TextField(controller: _headerLine, maxLength: 120,
                decoration: InputDecoration(labelText: tr('سطر تحت الاسم', 'Line under your name'),
                    hintText: tr('مثلاً: دكتوراه العلاج الطبيعي — جامعة القاهرة', 'e.g. PhD, Cairo University'))),
            TextField(controller: _phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: tr('رقم الحجز', 'Booking phone'))),
            const SizedBox(height: 12),
            TextField(controller: _whatsapp, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: tr('واتساب', 'WhatsApp'))),
            const SizedBox(height: 12),
            TextField(controller: _footerLine, maxLength: 150,
                decoration: InputDecoration(labelText: tr('سطر في آخر الروشتة', 'Footer line'),
                    hintText: tr('مثلاً: المواعيد يومياً من 5 إلى 10 مساءً عدا الجمعة', 'e.g. daily 5–10 pm except Friday'))),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _save(preview: true), icon: const Icon(Icons.visibility_rounded),
                label: Text(tr('حفظ ومعاينة', 'Save & preview'))),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: Text(tr('حفظ', 'Save'))),
          ]);
        },
      ),
    );
  }
}

/// Picks a logo from the gallery and re-encodes it as a small PNG (max 400 px).
class ImagePickerHelper {
  static Future<Uint8List?> pick(BuildContext context) async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800);
      if (x == null) return null;
      final codec = await ui.instantiateImageCodec(await x.readAsBytes(), targetWidth: 400);
      final frame = await codec.getNextFrame();
      final bd = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (_) {
      if (context.mounted) showMessage(context, tr('تعذر فتح الصور', 'Could not open photos'), error: true);
      return null;
    }
  }
}
