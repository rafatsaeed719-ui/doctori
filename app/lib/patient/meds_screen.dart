import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/reminders.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

String _everyLabel(int h) => switch (h) {
      4 => tr('كل 4 ساعات (6 مرات يومياً)', 'Every 4 hours (6×/day)'),
      6 => tr('كل 6 ساعات (4 مرات يومياً)', 'Every 6 hours (4×/day)'),
      8 => tr('كل 8 ساعات (3 مرات يومياً)', 'Every 8 hours (3×/day)'),
      12 => tr('كل 12 ساعة (مرتين يومياً)', 'Every 12 hours (2×/day)'),
      _ => tr('مرة واحدة يومياً', 'Once a day'),
    };

const medForms = ['tablet', 'capsule', 'syrup', 'injection', 'drops', 'cream', 'inhaler', 'sachet', 'suppository', 'other'];

/// Medicine type → emoji + name, so the patient knows exactly what they are taking.
(String, String) medFormInfo(String? f) => switch (f) {
      'tablet' => ('💊', tr('أقراص', 'Tablets')),
      'capsule' => ('💊', tr('كبسولات', 'Capsules')),
      'syrup' => ('🧴', tr('شراب', 'Syrup')),
      'injection' => ('💉', tr('حقن', 'Injection')),
      'drops' => ('💧', tr('نقط', 'Drops')),
      'cream' => ('🧴', tr('كريم / مرهم', 'Cream / ointment')),
      'inhaler' => ('🌬️', tr('بخاخ', 'Inhaler / spray')),
      'sachet' => ('🥤', tr('أكياس فوار', 'Sachets')),
      'suppository' => ('💊', tr('لبوس', 'Suppository')),
      'other' => ('🩹', tr('أخرى', 'Other')),
      _ => ('💊', tr('غير محدد', 'Not set')),
    };

const _medBucket = 'medical-files';

/// Thumbnail of a medicine photo (private storage, short-lived link). Tap to enlarge.
class MedPhoto extends StatelessWidget {
  const MedPhoto({super.key, required this.path, this.size = 72});
  final String path;
  final double size;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: supa.storage.from(_medBucket).createSignedUrl(path, 3600),
      builder: (context, snap) {
        final url = snap.data;
        return GestureDetector(
          onTap: url == null
              ? null
              : () => showDialog<void>(
                    context: context,
                    builder: (c) => Dialog(
                      insetPadding: const EdgeInsets.all(12),
                      child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
                    ),
                  ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: size,
              height: size,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: url == null
                  ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
            ),
          ),
        );
      },
    );
  }
}

String _isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// «علاجي». [patientId] null = my own medicines (add, log doses, reminders).
/// With [patientId], a doctor/assistant sees the patient's medicines and can prescribe ([canPrescribe]).
class MedsScreen extends StatefulWidget {
  const MedsScreen({super.key, this.patientId, this.canPrescribe = false, this.embedded = false});
  final String? patientId;
  final bool canPrescribe;
  final bool embedded;
  @override
  State<MedsScreen> createState() => _MedsScreenState();
}

class _MedsScreenState extends State<MedsScreen> {
  int _key = 0;
  bool get _mine => widget.patientId == null;

  @override
  void initState() {
    super.initState();
    if (_mine) Reminders.askPermission();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await rpc('list_medications', {'p_patient': widget.patientId});
    final list = (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (_mine) await Reminders.sync(list);
    return list;
  }

  void _refresh() => setState(() => _key++);

  Future<void> _add() async {
    var choice = 'manual';
    if (_mine) {
      final c = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon3D(Icons.photo_camera_rounded, color: Tone.purple, size: 44),
              title: Text(tr('صوّر الدوا وابعته للدكتور', 'Photograph a medicine for your doctor'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(tr('الدكتور يشوف العلبة ويحددلك الجرعة المناسبة', 'Your doctor sees it and sets the right dose')),
              onTap: () => Navigator.pop(c, 'photo'),
            ),
            ListTile(
              leading: const Icon3D(Icons.edit_note_rounded, color: Tone.teal, size: 44),
              title: Text(tr('أضيف دوا بنفسي', 'Add a medicine myself'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(tr('أكتب الاسم والجرعة والمواعيد', 'Name, dose and times')),
              onTap: () => Navigator.pop(c, 'manual'),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (c == null || !mounted) return;
      choice = c;
    }
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => choice == 'photo'
            ? const SendMedPhotoScreen()
            : MedicationForm(patientId: widget.patientId, prescribe: !_mine)));
    if (saved == true) _refresh();
  }

  Future<void> _review(Map<String, dynamic> m) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => MedicationForm(patientId: widget.patientId, prescribe: true, review: m)));
    if (saved == true) _refresh();
  }

  Future<void> _taken(Map<String, dynamic> m) async {
    final ok = await runBusy(context, () async {
      await supa.from('medication_doses').insert({'medication_id': m['id'], 'patient_id': myId});
    }, success: tr('تمام، اتسجلت الجرعة ✓', 'Dose logged ✓'));
    if (ok) _refresh();
  }

  Future<void> _toggleReminders(Map<String, dynamic> m, bool on) async {
    final ok = await runBusy(context, () async {
      await rpc('set_med_reminders', {'p_med': m['id'], 'p_on': on});
    });
    if (ok) _refresh();
  }

  Future<void> _menu(Map<String, dynamic> m) async {
    final own = m['prescribed_by'] == null;
    final canStop = !_mine && widget.canPrescribe && m['prescribed_by'] == actingDoctorId() && m['is_active'] == true;
    if (_mine && !own) return;
    if (!_mine && !canStop) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_mine) ...[
            ListTile(
              leading: Icon(m['is_active'] == true ? Icons.pause_circle_outline : Icons.play_circle_outline),
              title: Text(m['is_active'] == true ? tr('إيقاف الدوا', 'Stop medicine') : tr('تشغيل الدوا تاني', 'Resume medicine')),
              onTap: () => Navigator.pop(c, 'toggle'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
              title: Text(tr('حذف', 'Delete'), style: TextStyle(color: Theme.of(c).colorScheme.error)),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
          if (canStop)
            ListTile(
              leading: Icon(Icons.stop_circle_outlined, color: Theme.of(c).colorScheme.error),
              title: Text(tr('إيقاف هذا العلاج', 'Stop this prescription')),
              onTap: () => Navigator.pop(c, 'stop'),
            ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final ok = await runBusy(context, () async {
      switch (action) {
        case 'toggle':
          await supa.from('medications').update({'is_active': !(m['is_active'] == true)}).eq('id', m['id']);
        case 'delete':
          await supa.from('medications').delete().eq('id', m['id']);
        case 'stop':
          await rpc('stop_prescription', {'p_med': m['id']});
      }
    });
    if (ok) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureView<List<Map<String, dynamic>>>(
      key: ValueKey(_key),
      load: _load,
      builder: (context, list, reload) {
        final waiting = list.where((m) => m['needs_review'] == true).toList();
        final active = list.where((m) => m['is_active'] == true && m['needs_review'] != true).toList();
        final stopped = list.where((m) => m['is_active'] != true && m['needs_review'] != true).toList();
        return RefreshList(onRefresh: reload, children: [
          if (_mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoBanner(
                icon: Icons.notifications_active_outlined,
                text: tr('هيجيلك إشعار برنّة في ميعاد كل جرعة، حتى لو التطبيق مقفول. ما تغيّرش جرعة الدكتور من غير ما تسأله.',
                    'You get a notification at each dose time, even when the app is closed. Never change a doctor’s dose without asking.'),
              ),
            ),
          if (list.isEmpty)
            EmptyView(
              icon: Icons.medication_rounded,
              title: tr('لا يوجد علاج مسجل', 'No medicines yet'),
              subtitle: _mine ? tr('ضيف دواك ومواعيده، أو هيظهر هنا العلاج اللي يكتبهولك الدكتور.',
                  'Add your medicine and its times, or prescriptions from your doctor appear here.') : null,
            ),
          if (waiting.isNotEmpty)
            SectionTitle(_mine ? tr('مستني الدكتور يحدد الجرعة', 'Waiting for the doctor’s dose') : tr('أدوية بعتها المريض للمراجعة', 'Sent by the patient for review')),
          for (final m in waiting)
            _MedCard(
              m: m,
              mine: _mine,
              onMenu: _mine ? () => _menu(m) : null,
              onReview: !_mine && widget.canPrescribe && m['review_doctor'] == actingDoctorId() ? () => _review(m) : null,
            ),
          if (waiting.isNotEmpty && active.isNotEmpty) SectionTitle(tr('العلاج الحالي', 'Current treatment')),
          for (final m in active)
            _MedCard(
              m: m,
              mine: _mine,
              onTaken: _mine ? () => _taken(m) : null,
              onReminders: _mine ? (v) => _toggleReminders(m, v) : null,
              onMenu: () => _menu(m),
            ),
          if (stopped.isNotEmpty) SectionTitle(tr('علاج متوقف', 'Stopped')),
          for (final m in stopped) Opacity(opacity: 0.6, child: _MedCard(m: m, mine: _mine, onMenu: () => _menu(m))),
        ]);
      },
    );
    final fab = (_mine || widget.canPrescribe)
        ? FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(_mine ? tr('إضافة دوا', 'Add medicine') : tr('وصف علاج', 'Prescribe')),
          )
        : null;
    if (widget.embedded) {
      return Scaffold(backgroundColor: Colors.transparent, floatingActionButton: fab, body: body);
    }
    return Scaffold(appBar: AppBar(title: Text(tr('علاجي', 'My treatment'))), floatingActionButton: fab, body: body);
  }
}

class _MedCard extends StatelessWidget {
  const _MedCard({required this.m, required this.mine, this.onTaken, this.onReminders, this.onMenu, this.onReview});
  final Map<String, dynamic> m;
  final bool mine;
  final VoidCallback? onTaken;
  final ValueChanged<bool>? onReminders;
  final VoidCallback? onMenu;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (m['needs_review'] == true) return _waitingCard(context);
    final every = (m['every_hours'] as num?)?.toInt() ?? 24;
    final times = Reminders.doseMinutes('${m['first_time'] ?? '09:00'}', every).map(Reminders.formatMinutes).join('  •  ');
    final fromDoctor = m['prescribed_by'] != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (m['photo_path'] != null)
                MedPhoto(path: m['photo_path'] as String, size: 50)
              else
                Icon3D(null, color: fromDoctor ? Tone.purple : Tone.teal, size: 46, emoji: medFormInfo(m['form'] as String?).$1),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m['name'] ?? '', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  if ((m['dose'] as String?)?.isNotEmpty == true) Text(m['dose']),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (m['form'] != null) StatusChip(medFormInfo(m['form'] as String?).$2, color: Tone.indigo),
                    StatusChip(fromDoctor ? '${tr('من د.', 'By Dr.')} ${m['prescriber_name'] ?? ''}' : tr('أضفته أنا', 'Added by me'),
                        color: fromDoctor ? Tone.purple : Tone.teal),
                    StatusChip(_everyLabel(every), color: Tone.blue),
                  ]),
                ]),
              ),
              if (onMenu != null) IconButton(icon: const Icon(Icons.more_vert), onPressed: onMenu),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.schedule, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(times, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 4),
            Text('${tr('من', 'From')} ${formatDate(m['start_date'] as String?)}'
                '${m['end_date'] != null ? '  ${tr('إلى', 'to')} ${formatDate(m['end_date'] as String?)}' : '  ${tr('(مستمر)', '(ongoing)')}'}',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            if ((m['instructions'] as String?)?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('📝 ${m['instructions']}', style: const TextStyle(height: 1.5)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${tr('الجرعات آخر 7 أيام', 'Doses in last 7 days')}: ${m['doses_7d'] ?? 0}'
                '${m['last_taken'] != null ? '  •  ${tr('آخر جرعة', 'Last')}: ${formatDate(m['last_taken'] as String?)}' : ''}',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
            if (mine && m['is_active'] == true) ...[
              const Divider(height: 20),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: Tone.green),
                    onPressed: onTaken,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text(tr('أخدت الجرعة', 'Took my dose')),
                  ),
                ),
                const SizedBox(width: 8),
                Column(children: [
                  Switch(value: m['reminders_on'] == true, onChanged: onReminders),
                  Text(tr('تذكير', 'Remind'), style: const TextStyle(fontSize: 11)),
                ]),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

extension on _MedCard {
  Widget _waitingCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: lighten(Tone.amber, 0.85),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (m['photo_path'] != null) MedPhoto(path: m['photo_path'] as String, size: 84)
              else Icon3D(null, color: Tone.amber, size: 56, emoji: medFormInfo(m['form'] as String?).$1),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
                  if (m['form'] != null)
                    Text('${medFormInfo(m['form'] as String?).$1} ${medFormInfo(m['form'] as String?).$2}',
                        style: const TextStyle(color: Colors.black87)),
                  const SizedBox(height: 4),
                  StatusChip(
                      mine
                          ? '⏳ ${tr('مستني د.', 'Waiting for Dr.')} ${m['review_doctor_name'] ?? ''}'
                          : tr('⏳ محتاج تحدد الجرعة', '⏳ Needs a dose'),
                      color: darken(Tone.amber, 0.4)),
                  if ((m['instructions'] as String?)?.isNotEmpty == true)
                    Padding(padding: const EdgeInsets.only(top: 6),
                        child: Text('«${m['instructions']}»', style: const TextStyle(color: Colors.black87))),
                ]),
              ),
              if (onMenu != null) IconButton(icon: const Icon(Icons.more_vert, color: Colors.black54), onPressed: onMenu),
            ]),
            if (onReview != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: Tone.purple),
                onPressed: onReview,
                icon: const Icon(Icons.medication_liquid_rounded),
                label: Text(tr('حدد الجرعة المناسبة', 'Set the right dose')),
              ),
            ] else if (mine)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(tr('أول ما الدكتور يحدد الجرعة هتلاقيها في علاجك والتذكير هيشتغل لوحده.',
                    'Once the doctor sets the dose it moves to your treatment and reminders start.'),
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Patient photographs a medicine box and sends it to one of their doctors for a dose.
class SendMedPhotoScreen extends StatefulWidget {
  const SendMedPhotoScreen({super.key});
  @override
  State<SendMedPhotoScreen> createState() => _SendMedPhotoScreenState();
}

class _SendMedPhotoScreenState extends State<SendMedPhotoScreen> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  String? _form;
  String? _doctor;
  Uint8List? _bytes;
  late final Future<List<Map<String, dynamic>>> _doctors = rpcList('patient_my_doctors');

  Future<void> _pick(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 82);
      if (x == null) return;
      final b = await x.readAsBytes();
      setState(() => _bytes = b);
    } catch (e) {
      if (mounted) showMessage(context, tr('تعذر فتح الكاميرا', 'Could not open the camera'), error: true);
    }
  }

  Future<void> _send() async {
    if (_bytes == null) {
      showMessage(context, tr('صوّر الدوا الأول', 'Take a photo first'), error: true);
      return;
    }
    if (_doctor == null) {
      showMessage(context, tr('اختار الدكتور', 'Choose the doctor'), error: true);
      return;
    }
    final ok = await runBusy(context, () async {
      final path = '$myId/med_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supa.storage.from(_medBucket).uploadBinary(path, _bytes!, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      try {
        await supa.from('medications').insert({
          'patient_id': myId,
          'name': _name.text.trim().isEmpty ? tr('دوا من صورة', 'Medicine from photo') : _name.text.trim(),
          'form': _form,
          'photo_path': path,
          'needs_review': true,
          'review_doctor': _doctor,
          'is_active': false,
          'reminders_on': false,
          'instructions': _note.text.trim().isEmpty ? null : _note.text.trim(),
        });
      } catch (e) {
        await supa.storage.from(_medBucket).remove([path]);
        rethrow;
      }
    }, success: tr('اتبعت للدكتور ✓ هيحددلك الجرعة', 'Sent ✓ — your doctor will set the dose'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('ابعت صورة الدوا للدكتور', 'Send a medicine photo'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GestureDetector(
          onTap: () => _pick(ImageSource.camera),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Tone.purple.withValues(alpha: 0.4), width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: _bytes != null
                ? Image.memory(_bytes!, fit: BoxFit.cover)
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon3D(Icons.photo_camera_rounded, color: Tone.purple, size: 64),
                    const SizedBox(height: 12),
                    Text(tr('صوّر علبة الدوا أو الشريط', 'Photograph the box or strip'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera), label: Text(tr('الكاميرا', 'Camera')))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library), label: Text(tr('من الصور', 'Gallery')))),
        ]),
        const SizedBox(height: 16),
        Text(tr('نوع الدوا', 'Medicine type'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in medForms)
            ChoiceChip(
              label: Text('${medFormInfo(f).$1} ${medFormInfo(f).$2}'),
              selected: _form == f,
              onSelected: (v) => setState(() => _form = v ? f : null),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _name, maxLength: 120,
            decoration: InputDecoration(labelText: tr('اسم الدوا (لو عارفه)', 'Medicine name (if you know it)'))),
        TextField(controller: _note, maxLines: 2, maxLength: 1000,
            decoration: InputDecoration(labelText: tr('سؤالك للدكتور', 'Your question'),
                hintText: tr('مثلاً: الصيدلي اداني ده بدل اللي كتبته، أخده إزاي؟', 'e.g. the pharmacist gave me this instead'))),
        const SizedBox(height: 8),
        Text(tr('ابعته لمين؟', 'Send to'), style: const TextStyle(fontWeight: FontWeight.w800)),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _doctors,
          builder: (context, snap) {
            if (!snap.hasData) return const LoadingView();
            final docs = snap.data!;
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: InfoBanner(icon: Icons.info_outline,
                    text: tr('لازم تكون منضم لعيادة دكتور الأول عشان تبعتله.', 'Join a doctor’s clinic first.')),
              );
            }
            return Column(children: [
              for (final d in docs)
                RadioListTile<String>(
                  value: d['doctor_id'] as String,
                  groupValue: _doctor,
                  onChanged: (v) => setState(() => _doctor = v),
                  secondary: UserAvatar(url: d['avatar_url'] as String?, name: d['doctor_name'] as String?, radius: 20),
                  title: Text('${tr('د.', 'Dr.')} ${d['doctor_name'] ?? ''}'),
                  subtitle: Text(trField(d, 'specialty')),
                ),
            ]);
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _send, icon: const Icon(Icons.send_rounded), label: Text(tr('إرسال للدكتور', 'Send to doctor'))),
      ]),
    );
  }
}

/// Add a medicine (patient) or prescribe one (doctor/assistant with medical permission).
class MedicationForm extends StatefulWidget {
  const MedicationForm({super.key, this.patientId, this.prescribe = false, this.review});
  final String? patientId;
  final bool prescribe;

  /// A medicine the patient photographed: the doctor sets its dose.
  final Map<String, dynamic>? review;
  @override
  State<MedicationForm> createState() => _MedicationFormState();
}

class _MedicationFormState extends State<MedicationForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
      text: widget.review != null && widget.review!['photo_path'] != null && (widget.review!['name'] as String?) == tr('دوا من صورة', 'Medicine from photo')
          ? ''
          : widget.review?['name'] as String?);
  final _dose = TextEditingController();
  final _instructions = TextEditingController();
  late String? _formType = widget.review?['form'] as String?;
  int _every = 8;
  TimeOfDay _first = const TimeOfDay(hour: 9, minute: 0);
  DateTime _start = DateTime.now();
  int? _days = 7; // null = ongoing

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final first = '${_first.hour.toString().padLeft(2, '0')}:${_first.minute.toString().padLeft(2, '0')}';
    final end = _days == null ? null : _isoDate(_start.add(Duration(days: _days! - 1)));
    final ok = await runBusy(context, () async {
      if (widget.review != null) {
        await rpc('review_medication', {
          'p_med': widget.review!['id'],
          'p_name': _name.text.trim(),
          'p_dose': _dose.text.trim(),
          'p_every_hours': _every,
          'p_first_time': first,
          'p_start_date': _isoDate(_start),
          'p_end_date': end,
          'p_instructions': _instructions.text.trim(),
          'p_doctor': actingDoctorId(),
          'p_form': _formType,
        });
      } else if (widget.prescribe) {
        await rpc('prescribe_medication', {
          'p_patient': widget.patientId,
          'p_name': _name.text.trim(),
          'p_dose': _dose.text.trim(),
          'p_every_hours': _every,
          'p_first_time': first,
          'p_start_date': _isoDate(_start),
          'p_end_date': end,
          'p_instructions': _instructions.text.trim(),
          'p_doctor': actingDoctorId(),
          'p_form': _formType,
        });
      } else {
        await supa.from('medications').insert({
          'patient_id': myId,
          'name': _name.text.trim(),
          'dose': _dose.text.trim().isEmpty ? null : _dose.text.trim(),
          'form': _formType,
          'every_hours': _every,
          'first_time': first,
          'start_date': _isoDate(_start),
          'end_date': end,
          'instructions': _instructions.text.trim().isEmpty ? null : _instructions.text.trim(),
        });
      }
    }, success: widget.review != null ? tr('تم ✓ الجرعة وصلت للمريض والتذكير هيشتغل عنده', 'Done ✓ — the patient gets the dose and reminders') : widget.prescribe ? tr('تم إرسال العلاج للمريض ✓', 'Prescription sent ✓') : tr('تم الحفظ ✓', 'Saved ✓'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final times = Reminders.doseMinutes('${_first.hour}:${_first.minute}', _every).map(Reminders.formatMinutes).join('  •  ');
    return Scaffold(
      appBar: AppBar(title: Text(widget.review != null
          ? tr('تحديد الجرعة', 'Set the dose')
          : (widget.prescribe ? tr('وصف علاج للمريض', 'Prescribe') : tr('إضافة دوا', 'Add medicine')))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.review != null) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.review!['photo_path'] != null) MedPhoto(path: widget.review!['photo_path'] as String, size: 110),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  (widget.review!['instructions'] as String?)?.isNotEmpty == true
                      ? '${tr('سؤال المريض', 'Patient asks')}: «${widget.review!['instructions']}»'
                      : tr('المريض صوّر الدوا ده. اضغط الصورة لتكبيرها، وحدد الاسم والجرعة والمواعيد.',
                          'The patient photographed this medicine. Tap to enlarge, then set name, dose and times.'),
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: tr('اسم الدوا *', 'Medicine name *'), prefixIcon: const Icon(Icons.medication)),
            validator: requiredField,
          ),
          const SizedBox(height: 12),
          Text(tr('نوع الدوا', 'Medicine type'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in medForms)
              ChoiceChip(
                label: Text('${medFormInfo(f).$1} ${medFormInfo(f).$2}'),
                selected: _formType == f,
                onSelected: (v) => setState(() => _formType = v ? f : null),
              ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _dose,
            decoration: InputDecoration(labelText: tr('الجرعة', 'Dose'), hintText: tr('مثلاً: قرص واحد / 5 مل', 'e.g. 1 tablet / 5 ml')),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _every,
            decoration: InputDecoration(labelText: tr('كل قد إيه؟', 'How often?')),
            items: [for (final h in [4, 6, 8, 12, 24]) DropdownMenuItem(value: h, child: Text(_everyLabel(h)))],
            onChanged: (v) => setState(() => _every = v ?? 24),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            leading: const Icon(Icons.alarm),
            title: Text(tr('ميعاد أول جرعة', 'First dose time')),
            subtitle: Text(_first.format(context)),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _first);
              if (t != null) setState(() => _first = t);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text('${tr('المواعيد', 'Times')}: $times', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            leading: const Icon(Icons.event),
            title: Text(tr('يبدأ من', 'Starts on')),
            subtitle: Text(formatDate(_start.toIso8601String())),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _start,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null) setState(() => _start = d);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _days,
            decoration: InputDecoration(labelText: tr('المدة', 'Duration')),
            items: [
              for (final d in [3, 5, 7, 10, 14, 30, 60, 90])
                DropdownMenuItem<int?>(value: d, child: Text(tr('$d يوم', '$d days'))),
              DropdownMenuItem<int?>(value: null, child: Text(tr('مستمر (بدون نهاية)', 'Ongoing'))),
            ],
            onChanged: (v) => setState(() => _days = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _instructions,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(labelText: tr('تعليمات', 'Instructions'),
                hintText: tr('مثلاً: بعد الأكل، مع كوباية مية', 'e.g. after meals, with water')),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: Icon(widget.prescribe ? Icons.send_rounded : Icons.save_rounded),
            label: Text(widget.review != null
                ? tr('إرسال الجرعة للمريض', 'Send dose to patient')
                : (widget.prescribe ? tr('إرسال للمريض', 'Send to patient') : tr('حفظ', 'Save'))),
          ),
        ]),
      ),
    );
  }
}
