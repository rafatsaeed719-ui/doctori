import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'offers_screens.dart';

/// Owner posts shown at the top of the home screen; each user can close them.
class AnnouncementsStrip extends StatefulWidget {
  const AnnouncementsStrip({super.key});
  @override
  State<AnnouncementsStrip> createState() => _AnnouncementsStripState();
}

class _AnnouncementsStripState extends State<AnnouncementsStrip> {
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    rpc('my_announcements').then((r) {
      if (!mounted || r is! List) return;
      setState(() => _items = r.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    }).catchError((_) {});
  }

  void _dismiss(Map<String, dynamic> a) {
    setState(() => _items = [..._items]..remove(a));
    rpc('dismiss_announcement', {'p_id': a['id']}).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(children: [for (final a in _items) _card(context, a)]);
  }

  Widget _card(BuildContext context, Map<String, dynamic> a) {
    final image = a['image_url'] as String?;
    final link = a['link_url'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Tone.indigo, Tone.blue]),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Tone.indigo.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (image != null && image.isNotEmpty)
            AspectRatio(aspectRatio: 16 / 8, child: Image.network(image, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink())),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.campaign_rounded, color: Colors.white, size: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16.5)),
                  if ((a['body'] as String?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(a['body'] as String, style: const TextStyle(color: Colors.white, height: 1.55)),
                    ),
                  if (link != null && link.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                        child: Text(tr('افتح الرابط', 'Open link')),
                      ),
                    ),
                ]),
              ),
              IconButton(
                tooltip: tr('إخفاء', 'Close'),
                onPressed: () => _dismiss(a),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ===========================================================================
// Admin: announcements
// ===========================================================================
String audienceLabel(String? a) => switch (a) {
      'doctors' => tr('الأطباء', 'Doctors'),
      'patients' => tr('المرضى', 'Patients'),
      _ => tr('الكل', 'Everyone'),
    };

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});
  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  int _key = 0;

  Future<void> _edit([Map<String, dynamic>? a]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AnnouncementForm(item: a)));
    if (saved == true) setState(() => _key++);
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final yes = await confirmDialog(context, title: tr('حذف البوست؟', 'Delete post?'), body: a['title'] as String? ?? '',
        confirm: tr('حذف', 'Delete'), danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async => rpc('admin_delete_announcement', {'p_id': a['id']}));
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('بوستات الصفحة الرئيسية', 'Home posts'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('بوست جديد', 'New post')),
      ),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => rpcList('admin_list_announcements'),
        builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
          InfoBanner(icon: Icons.campaign_outlined,
              text: tr('البوست بيظهر فوق في الصفحة الرئيسية للي تختارهم أول ما يفتحوا التطبيق، لحد ما يقفلوه أو يخلص ميعاده.',
                  'A post shows at the top of the home screen for the chosen people until they close it or it ends.')),
          const SizedBox(height: 12),
          if (list.isEmpty)
            EmptyView(icon: Icons.campaign_rounded, title: tr('مفيش بوستات', 'No posts yet')),
          for (final a in list)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Icon3D(Icons.campaign_rounded, color: a['is_active'] == true ? Tone.indigo : Colors.grey, size: 44),
                title: Text(a['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text([
                  '${tr('لـ', 'To')}: ${audienceLabel(a['audience'] as String?)}',
                  if (a['ends_on'] != null) '${tr('لحد', 'until')} ${formatDate(a['ends_on'] as String?)}',
                  if (a['is_active'] != true) tr('متوقف', 'paused'),
                  '${tr('قفلوه', 'closed by')}: ${a['dismissed'] ?? 0}',
                ].join(' • ')),
                onTap: () => _edit(a),
                trailing: IconButton(onPressed: () => _delete(a), icon: const Icon(Icons.delete_outline)),
              ),
            ),
        ]),
      ),
    );
  }
}

class AnnouncementForm extends StatefulWidget {
  const AnnouncementForm({super.key, this.item});
  final Map<String, dynamic>? item;
  @override
  State<AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends State<AnnouncementForm> {
  late final _title = TextEditingController(text: widget.item?['title'] as String?);
  late final _body = TextEditingController(text: widget.item?['body'] as String?);
  late final _link = TextEditingController(text: widget.item?['link_url'] as String?);
  late String _audience = widget.item?['audience'] as String? ?? 'all';
  late String? _image = widget.item?['image_url'] as String?;
  late DateTime? _ends = DateTime.tryParse('${widget.item?['ends_on']}');
  late bool _active = widget.item?['is_active'] as bool? ?? true;

  Future<void> _save() async {
    if (_title.text.trim().length < 2) {
      showMessage(context, tr('اكتب عنوان البوست', 'Enter a title'), error: true);
      return;
    }
    var link = _link.text.trim();
    if (link.isNotEmpty && !link.startsWith('http')) link = 'https://$link';
    final ok = await runBusy(context, () async {
      await rpc('admin_save_announcement', {
        'p_id': widget.item?['id'],
        'p_title': _title.text.trim(),
        'p_body': _body.text.trim(),
        'p_audience': _audience,
        'p_image_url': _image,
        'p_link_url': link,
        'p_ends_on': _ends == null
            ? null
            : '${_ends!.year}-${_ends!.month.toString().padLeft(2, '0')}-${_ends!.day.toString().padLeft(2, '0')}',
        'p_active': _active,
      });
    }, success: tr('البوست نزل ✓', 'Posted ✓'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? tr('بوست جديد', 'New post') : tr('تعديل البوست', 'Edit post'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
        Text(tr('يظهر لمين؟', 'Show to'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'all', label: Text(audienceLabel('all'))),
            ButtonSegment(value: 'doctors', label: Text(audienceLabel('doctors'))),
            ButtonSegment(value: 'patients', label: Text(audienceLabel('patients'))),
          ],
          selected: {_audience},
          onSelectionChanged: (s) => setState(() => _audience = s.first),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () async {
            final url = await pickAndUploadOfferImage(context);
            if (url != null) setState(() => _image = url);
          },
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: _image != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.network(_image!, fit: BoxFit.cover),
                    PositionedDirectional(top: 6, end: 6,
                        child: IconButton.filled(onPressed: () => setState(() => _image = null), icon: const Icon(Icons.close))),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_photo_alternate_rounded, size: 40),
                    const SizedBox(height: 6),
                    Text(tr('صورة (اختياري)', 'Picture (optional)')),
                  ]),
          ),
        ),
        const SizedBox(height: 14),
        TextField(controller: _title, maxLength: 120, decoration: InputDecoration(labelText: tr('العنوان', 'Title'))),
        TextField(controller: _body, maxLines: 5, maxLength: 2000, decoration: InputDecoration(labelText: tr('الكلام', 'Text'))),
        TextField(controller: _link, keyboardType: TextInputType.url, textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: tr('رابط (اختياري)', 'Link (optional)'), hintText: 'https://')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timer_outlined),
          title: Text(tr('يختفي بعد', 'Ends on')),
          subtitle: Text(_ends == null ? tr('مفتوح', 'Open') : formatDate(_ends!.toIso8601String())),
          trailing: _ends == null ? null : IconButton(onPressed: () => setState(() => _ends = null), icon: const Icon(Icons.close)),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _ends ?? DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _ends = d);
          },
        ),
        if (widget.item != null)
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v),
              title: Text(tr('البوست ظاهر', 'Visible'))),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _save,
            icon: const Icon(Icons.send_rounded),
            label: Text(widget.item == null ? tr('نشر', 'Publish') : tr('حفظ', 'Save')),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Admin: all doctors' offers, with hide / show
// ===========================================================================
class AdminOffersScreen extends StatefulWidget {
  const AdminOffersScreen({super.key});
  @override
  State<AdminOffersScreen> createState() => _AdminOffersScreenState();
}

class _AdminOffersScreenState extends State<AdminOffersScreen> {
  int _key = 0;

  Future<void> _hide(Map<String, dynamic> o, bool hidden) async {
    final ok = await runBusy(context, () async => rpc('admin_hide_offer', {'p_id': o['id'], 'p_hidden': hidden}),
        success: hidden ? tr('العرض اتخفى عن المرضى', 'Offer hidden') : tr('العرض رجع يظهر', 'Offer visible'));
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('عروض الأطباء', 'Doctors’ offers'))),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => rpcList('list_offers', {'p_limit': 200}),
        builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
          if (list.isEmpty) EmptyView(icon: Icons.local_offer_rounded, title: tr('مفيش عروض', 'No offers')),
          for (final o in list) ...[
            Opacity(opacity: o['hidden_by_admin'] == true ? 0.5 : 1, child: OfferCard(o: o)),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
              child: Row(children: [
                Expanded(child: Text('👁 ${o['views'] ?? 0}   📅 ${o['bookings'] ?? 0}')),
                o['hidden_by_admin'] == true
                    ? OutlinedButton.icon(onPressed: () => _hide(o, false), icon: const Icon(Icons.visibility),
                        label: Text(tr('إظهار', 'Show')))
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                        onPressed: () => _hide(o, true), icon: const Icon(Icons.visibility_off),
                        label: Text(tr('إخفاء عن المرضى', 'Hide'))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
