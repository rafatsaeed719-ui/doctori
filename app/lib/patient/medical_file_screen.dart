import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

const _bucket = 'medical-files';
const _maxBytes = 50 * 1024 * 1024;

String _mimeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic')) return 'image/heic';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.mp4')) return 'video/mp4';
  if (n.endsWith('.mov')) return 'video/quicktime';
  if (n.endsWith('.3gp')) return 'video/3gpp';
  if (n.endsWith('.webm')) return 'video/webm';
  if (n.endsWith('.pdf')) return 'application/pdf';
  return 'application/octet-stream';
}

(IconData, Color) _kindLook(String? kind) => switch (kind) {
      'image' => (Icons.image_rounded, Tone.blue),
      'video' => (Icons.videocam_rounded, Tone.pink),
      'file' => (Icons.picture_as_pdf_rounded, Tone.red),
      _ => (Icons.notes_rounded, Tone.teal),
    };

/// A patient's medical file. [patientId] null = my own file (can add/delete);
/// otherwise a doctor/assistant viewing a linked patient (read-only, shows only what is shared).
class MedicalFileScreen extends StatefulWidget {
  const MedicalFileScreen({super.key, this.patientId, this.embedded = false});
  final String? patientId;
  final bool embedded;
  @override
  State<MedicalFileScreen> createState() => _MedicalFileScreenState();
}

class _MedicalFileScreenState extends State<MedicalFileScreen> {
  int _key = 0;
  bool get _mine => widget.patientId == null;

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await rpc('list_medical_entries', {'p_patient': widget.patientId});
    return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _open(Map<String, dynamic> e) async {
    try {
      final url = await supa.storage.from(_bucket).createSignedUrl(e['storage_path'] as String, 600);
      if (!mounted) return;
      if (e['kind'] == 'image') {
        await showDialog<void>(
          context: context,
          builder: (c) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))),
              TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('إغلاق', 'Close'))),
            ]),
          ),
        );
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (err) {
      if (mounted) showMessage(context, friendlyError(err), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final yes = await confirmDialog(context,
        title: tr('حذف من الملف؟', 'Delete from file?'),
        body: tr('هيتم حذف العنصر نهائياً.', 'This item will be deleted permanently.'),
        confirm: tr('حذف', 'Delete'),
        danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async {
      final path = e['storage_path'] as String?;
      if (path != null) await supa.storage.from(_bucket).remove([path]);
      await supa.from('medical_entries').delete().eq('id', e['id']);
    }, success: tr('تم الحذف', 'Deleted'));
    if (ok) setState(() => _key++);
  }

  Future<void> _add() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TileGrid(children: [
            Tile3D(icon: Icons.notes_rounded, color: Tone.teal, label: tr('ملاحظة مكتوبة', 'Written note'),
                onTap: () => Navigator.pop(c, 'note')),
            Tile3D(icon: Icons.image_rounded, color: Tone.blue, label: tr('صورة', 'Photo'),
                subtitle: tr('روشتة، تحليل، أشعة', 'Prescription, lab, scan'), onTap: () => Navigator.pop(c, 'image')),
            Tile3D(icon: Icons.videocam_rounded, color: Tone.pink, label: tr('فيديو', 'Video'),
                subtitle: tr('حتى 50 ميجا', 'Up to 50 MB'), onTap: () => Navigator.pop(c, 'video')),
            Tile3D(icon: Icons.picture_as_pdf_rounded, color: Tone.red, label: tr('ملف PDF', 'PDF file'),
                subtitle: tr('تقرير أو تحليل', 'Report or lab'), onTap: () => Navigator.pop(c, 'file')),
          ]),
        ),
      ),
    );
    if (kind == null || !mounted) return;

    PlatformFile? file;
    if (kind != 'note') {
      try {
        final picked = await FilePicker.pickFiles(
          type: switch (kind) { 'image' => FileType.image, 'video' => FileType.video, _ => FileType.custom },
          allowedExtensions: kind == 'file' ? ['pdf'] : null,
        );
        if (picked.isEmpty) return;
        file = picked.first;
      } catch (e) {
        if (mounted) showMessage(context, friendlyError(e), error: true);
        return;
      }
    }
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => _EntryForm(kind: kind, file: file)));
    if (saved == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureView<List<Map<String, dynamic>>>(
      key: ValueKey(_key),
      load: _load,
      builder: (context, list, reload) => RefreshList(
        onRefresh: reload,
        children: [
          if (_mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InfoBanner(
                icon: Icons.lock_outline,
                text: tr('ملفك محفوظ في مساحة خاصة. الدكتور يشوف منه بس على حسب المشاركة اللي اخترتها.',
                    'Your file is private. Doctors see it only according to the sharing you chose.'),
              ),
            ),
          if (list.isEmpty)
            EmptyView(
              icon: Icons.folder_open_rounded,
              title: _mine ? tr('ملفك الطبي فاضي', 'Your medical file is empty') : tr('لا يوجد شيء مشترك', 'Nothing shared'),
              subtitle: _mine ? tr('ضيف روشتاتك وتحاليلك وصورك وملاحظاتك من زرار الإضافة.', 'Add prescriptions, labs, photos and notes.') : null,
            ),
          for (final e in list) _EntryCard(e: e, onOpen: () => _open(e), onDelete: _mine ? () => _delete(e) : null),
        ],
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(tr('ملفي الطبي', 'My medical file'))),
      floatingActionButton: _mine
          ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: Text(tr('إضافة', 'Add')))
          : null,
      body: body,
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.e, required this.onOpen, this.onDelete});
  final Map<String, dynamic> e;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _kindLook(e['kind'] as String?);
    final isNote = e['kind'] == 'note';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isNote ? null : onOpen,
          onLongPress: onDelete,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon3D(icon, color: color, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((e['title'] as String?)?.isNotEmpty == true)
                    Text(e['title'], style: const TextStyle(fontWeight: FontWeight.w800)),
                  if ((e['body'] as String?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(e['body'], style: const TextStyle(height: 1.5)),
                    ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    Text(formatDate(e['created_at'] as String?), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    if (e['shared_with_name'] != null)
                      StatusChip('${tr('لـ د.', 'To Dr.')} ${e['shared_with_name']}', color: Tone.teal),
                    if (!isNote) StatusChip(tr('اضغط للفتح', 'Tap to open'), color: color),
                  ]),
                ]),
              ),
              if (onDelete != null)
                IconButton(icon: Icon(Icons.delete_outline, color: cs.error), onPressed: onDelete),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Title / text / optional "send to one doctor" before saving a new item.
class _EntryForm extends StatefulWidget {
  const _EntryForm({required this.kind, this.file});
  final String kind;
  final PlatformFile? file;
  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _sharedWith;
  late final Future<List<Map<String, dynamic>>> _doctors = rpcList('patient_my_doctors');

  Future<void> _save() async {
    if (widget.kind == 'note' && _body.text.trim().isEmpty) {
      showMessage(context, tr('اكتب الملاحظة', 'Write the note'), error: true);
      return;
    }
    final ok = await runBusy(context, () async {
      String? path;
      String? mime;
      int? size;
      if (widget.file != null) {
        final bytes = await widget.file!.readAsBytes();
        if (bytes.length > _maxBytes) throw Exception('payload too large');
        final safe = widget.file!.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        path = '$myId/${DateTime.now().millisecondsSinceEpoch}_$safe';
        mime = _mimeFor(widget.file!.name);
        size = bytes.length;
        await supa.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
      }
      await supa.from('medical_entries').insert({
        'patient_id': myId,
        'created_by': myId,
        'kind': widget.kind,
        'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
        'body': _body.text.trim().isEmpty ? null : _body.text.trim(),
        'storage_path': path,
        'mime_type': mime,
        'size_bytes': size,
        'shared_with': _sharedWith,
      });
    }, success: tr('تمت الإضافة لملفك', 'Added to your file'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _kindLook(widget.kind);
    return Scaffold(
      appBar: AppBar(title: Text(tr('إضافة للملف الطبي', 'Add to medical file'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.file != null)
          Card(
            child: ListTile(
              leading: Icon3D(icon, color: color, size: 42),
              title: Text(widget.file!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: tr('العنوان', 'Title'),
            hintText: tr('مثلاً: تحليل سكر تراكمي', 'e.g. HbA1c test'),
          ),
        ),
        TextField(
          controller: _body,
          maxLines: widget.kind == 'note' ? 6 : 3,
          maxLength: 5000,
          decoration: InputDecoration(
            labelText: widget.kind == 'note' ? tr('الملاحظة *', 'Note *') : tr('وصف (اختياري)', 'Description (optional)'),
            hintText: widget.kind == 'note' ? tr('مثلاً: الضغط 130/85 الصبح، صداع خفيف', 'e.g. BP 130/85, mild headache') : null,
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _doctors,
          builder: (context, snap) {
            final docs = snap.data ?? const [];
            if (docs.isEmpty) return const SizedBox.shrink();
            return DropdownButtonFormField<String?>(
              initialValue: _sharedWith,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('مين يشوفه؟', 'Who can see it?'),
                helperText: tr('الأطباء اللي مشاركين ملفك كله هيشوفوه في كل الأحوال', 'Doctors with full access always see it'),
              ),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(tr('حسب المشاركة مع كل طبيب', 'Per each doctor’s sharing'))),
                for (final d in docs)
                  DropdownMenuItem<String?>(
                      value: d['doctor_id'] as String, child: Text('${tr('أبعته لـ د.', 'Send to Dr.')} ${d['doctor_name']}')),
              ],
              onChanged: (v) => setState(() => _sharedWith = v),
            );
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: Text(tr('حفظ', 'Save'))),
      ]),
    );
  }
}
