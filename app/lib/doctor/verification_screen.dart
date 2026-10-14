import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/l10n.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<PlatformFile> _files = [];
  final _note = TextEditingController();
  int _reloadKey = 0;

  static const _maxBytes = 10 * 1024 * 1024;

  Future<void> _pick() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf']);
      if (picked.isEmpty) return;
      setState(() => _files.addAll(picked));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  Future<void> _submit() async {
    if (_files.isEmpty) {
      showMessage(context, tr('اختر ملفاً واحداً على الأقل', 'Choose at least one file'), error: true);
      return;
    }
    final ok = await runBusy(context, () async {
      final paths = <String>[];
      for (final f in _files) {
        final bytes = await f.readAsBytes();
        if (bytes.length > _maxBytes) {
          throw Exception('payload too large');
        }
        final safe = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final path = '$myId/${DateTime.now().millisecondsSinceEpoch}_$safe';
        await supa.storage.from('verification-docs').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: _mime(f.name), upsert: false),
            );
        paths.add(path);
      }
      await supa.from('doctor_verifications').insert({
        'doctor_id': myId,
        'documents': paths,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
    }, success: tr('تم إرسال المستندات للمراجعة', 'Documents sent for review'));
    if (ok && mounted) {
      setState(() {
        _files.clear();
        _note.clear();
        _reloadKey++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('مستندات التوثيق', 'Verification documents'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        InfoBanner(
          icon: Icons.lock_outline,
          text: tr('ارفع صورة كارنيه النقابة أو ترخيص مزاولة المهنة وصورة البطاقة. الملفات محفوظة في مساحة خاصة ولا يراها إلا فريق المراجعة.',
              'Upload your syndicate card or practice licence and your ID. Files are stored privately and only seen by reviewers.'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.attach_file),
            label: Text(tr('اختيار ملفات (JPG / PNG / PDF، حتى 10 ميجا)', 'Choose files (JPG / PNG / PDF, up to 10 MB)'))),
        for (final f in _files)
          ListTile(
            leading: Icon(f.name.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image, color: cs.primary),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _files.remove(f))),
          ),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: 2,
            decoration: InputDecoration(labelText: tr('ملاحظة للمراجع (اختياري)', 'Note for the reviewer (optional)'))),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.upload),
            label: Text(tr('إرسال للمراجعة', 'Submit for review'))),
        SectionTitle(tr('الطلبات السابقة', 'Previous submissions')),
        FutureView<List<Map<String, dynamic>>>(
          key: ValueKey(_reloadKey),
          load: () => supa.from('doctor_verifications').select().eq('doctor_id', myId).order('submitted_at', ascending: false),
          builder: (context, list, _) => list.isEmpty
              ? Text(tr('لم ترسل مستندات بعد.', 'No submissions yet.'))
              : Column(children: [
                  for (final v in list)
                    Card(
                      child: ListTile(
                        title: Text('${formatDate(v['submitted_at'] as String?)} · ${(v['documents'] as List?)?.length ?? 0} ${tr('ملف', 'files')}'),
                        subtitle: v['review_notes'] != null ? Text('${tr('ملاحظات الإدارة', 'Admin notes')}: ${v['review_notes']}') : null,
                        trailing: StatusChip(
                          switch (v['decision']) {
                            'verified' => tr('مقبول', 'Approved'),
                            'rejected' => tr('مرفوض', 'Declined'),
                            'suspended' => tr('معلّق', 'Suspended'),
                            _ => tr('قيد المراجعة', 'In review'),
                          },
                          color: switch (v['decision']) {
                            'verified' => Colors.green.shade700,
                            null => Colors.orange.shade800,
                            _ => cs.error,
                          },
                        ),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}
