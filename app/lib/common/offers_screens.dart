import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/avatar.dart';
import '../core/backgrounds.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/lookups.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../patient/booking_screens.dart';
import '../patient/doctor_details_screen.dart';

final _fmt = intl.NumberFormat('#,##0.##', 'en');
String _money(num? v) => '${_fmt.format(v ?? 0)} ${tr('ج.م', 'EGP')}';
num? _num(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');

const offerKinds = ['operation', 'visit_price', 'service', 'discount', 'package', 'other'];
(String, IconData) offerKindInfo(String? k) => switch (k) {
      'operation' => (tr('عملية', 'Operation'), Icons.local_hospital_rounded),
      'visit_price' => (tr('سعر الكشف', 'Visit price'), Icons.payments_rounded),
      'service' => (tr('خدمة', 'Service'), Icons.medical_services_rounded),
      'discount' => (tr('خصم', 'Discount'), Icons.percent_rounded),
      'package' => (tr('باقة / كورس', 'Package'), Icons.inventory_2_rounded),
      _ => (tr('أخرى', 'Other'), Icons.campaign_rounded),
    };

/// Picks a photo from the gallery and uploads it to the public "offers" bucket. Returns its public URL.
Future<String?> pickAndUploadOfferImage(BuildContext context) async {
  XFile? x;
  try {
    x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 82);
  } catch (_) {
    if (context.mounted) showMessage(context, tr('تعذر فتح الصور', 'Could not open photos'), error: true);
    return null;
  }
  if (x == null || !context.mounted) return null;
  final Uint8List bytes = await x.readAsBytes();
  final isPng = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
  final isWebp = bytes.length > 12 && String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
  final ext = isPng ? 'png' : (isWebp ? 'webp' : 'jpg');
  String? url;
  if (!context.mounted) return null;
  await runBusy(context, () async {
    final path = '$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await supa.storage.from('offers').uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: isPng ? 'image/png' : (isWebp ? 'image/webp' : 'image/jpeg')));
    url = supa.storage.from('offers').getPublicUrl(path);
  });
  return url;
}

// ===========================================================================
// One offer as a card
// ===========================================================================
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.o, this.onTap, this.compact = false, this.trailing});
  final Map<String, dynamic> o;
  final VoidCallback? onTap;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = specialtyLook(o['specialty_en'] as String?).accent;
    final (kindLabel, kindIcon) = offerKindInfo(o['kind'] as String?);
    final price = _num(o['price']), old = _num(o['old_price']);
    final image = o['image_url'] as String?;
    final off = (price != null && old != null && old > price && old > 0) ? ((old - price) / old * 100).round() : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.only(bottom: compact ? 0 : 12),
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            if (image != null && image.isNotEmpty)
              AspectRatio(
                aspectRatio: compact ? 16 / 8 : 16 / 9,
                child: Image.network(image, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: lighten(accent, 0.85))),
              )
            else
              Container(
                height: compact ? 92 : 120,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [accent, darken(accent, 0.25)])),
                alignment: Alignment.center,
                child: Icon(kindIcon, size: compact ? 40 : 54, color: Colors.white.withValues(alpha: 0.9)),
              ),
            PositionedDirectional(
              top: 8,
              start: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                child: Text(kindLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
            if (off != null && off > 0)
              PositionedDirectional(
                top: 8,
                end: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Tone.red, borderRadius: BorderRadius.circular(20)),
                  child: Text(tr('خصم $off٪', '$off% off'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              if (price != null)
                Row(children: [
                  Text(_money(price), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: darken(accent, 0.2))),
                  if (old != null && old > price) ...[
                    const SizedBox(width: 8),
                    Text(_money(old),
                        style: TextStyle(decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant, fontSize: 13)),
                  ],
                ]),
              const SizedBox(height: 6),
              Row(children: [
                UserAvatar(url: o['doctor_avatar'] as String?, name: o['doctor_name'] as String?, radius: 13),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${tr('د.', 'Dr.')} ${o['doctor_name'] ?? ''}'
                    '${(o[L10n.isAr ? 'specialty_ar' : 'specialty_en'] ?? o['specialty_ar']) != null ? ' • ${o[L10n.isAr ? 'specialty_ar' : 'specialty_en'] ?? o['specialty_ar']}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                if (trailing != null) trailing!,
              ]),
              if (!compact && (o['city'] ?? o['governorate']) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('📍 ${[o['city'], o['governorate']].whereType<String>().join('، ')}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ===========================================================================
// Patients: feed + details
// ===========================================================================
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});
  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  int? _specialty;
  int? _governorate;
  int _key = 0;

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      await Lookups.ensure();
    } catch (_) {}
    final r = await rpc('list_offers', {'p_specialty': _specialty, 'p_governorate': _governorate});
    return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('عروض الأطباء', 'Doctors’ offers'))),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: _load,
        builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _specialty,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('التخصص', 'Specialty'), isDense: true),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(tr('الكل', 'All'))),
                  for (final s in Lookups.specialties)
                    DropdownMenuItem<int?>(value: s['id'] as int, child: Text(trField(s, 'name'), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _specialty = v;
                  _key++;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _governorate,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('المحافظة', 'Governorate'), isDense: true),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(tr('الكل', 'All'))),
                  for (final g in Lookups.governorates)
                    DropdownMenuItem<int?>(value: g['id'] as int, child: Text(trField(g, 'name'), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _governorate = v;
                  _key++;
                }),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (list.isEmpty)
            EmptyView(icon: Icons.local_offer_rounded, title: tr('مفيش عروض دلوقتي', 'No offers right now'),
                subtitle: tr('عروض الأطباء على العمليات والكشف والخدمات هتظهر هنا.', 'Doctors’ offers appear here.')),
          for (final o in list)
            OfferCard(o: o, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OfferDetailsScreen(offer: o)))),
        ]),
      ),
    );
  }
}

/// Horizontal strip of the latest offers for the home screen (hidden when there are none).
class OffersStrip extends StatelessWidget {
  const OffersStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: rpc('list_offers', {'p_limit': 10}).catchError((_) => const []),
      builder: (context, snap) {
        final list = (snap.data is List ? snap.data as List : const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon3D(Icons.local_offer_rounded, color: Tone.red, size: 34),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('عروض الأطباء', 'Doctors’ offers'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OffersScreen())),
              child: Text(tr('الكل', 'See all')),
            ),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 262,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SizedBox(
                width: 250,
                child: OfferCard(
                  o: list[i],
                  compact: true,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OfferDetailsScreen(offer: list[i]))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ]);
      },
    );
  }
}

class OfferDetailsScreen extends StatefulWidget {
  const OfferDetailsScreen({super.key, required this.offer});
  final Map<String, dynamic> offer;
  @override
  State<OfferDetailsScreen> createState() => _OfferDetailsScreenState();
}

class _OfferDetailsScreenState extends State<OfferDetailsScreen> {
  Map<String, dynamic> get o => widget.offer;

  @override
  void initState() {
    super.initState();
    if (AppState.context['role'] == 'patient') {
      rpc('offer_event', {'p_id': o['id'], 'p_event': 'view'}).catchError((_) => null);
    }
  }

  Future<void> _book() async {
    Map<String, dynamic>? doctor;
    final ok = await runBusy(context, () async {
      final d = await rpc('get_doctor_public', {'p_doctor': o['doctor_id']});
      doctor = d is Map ? Map<String, dynamic>.from(d) : null;
    });
    if (!ok || !mounted) return;
    if (doctor == null || (doctor!['clinics'] as List? ?? const []).isEmpty) {
      showMessage(context, tr('الحجز مش متاح عند الدكتور ده دلوقتي. كلّم العيادة.', 'Booking is not available; call the clinic.'),
          error: true);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingScreen(
          doctor: doctor!,
          offerId: o['id'] as String?,
          initialNote: '${tr('حجز بعرض', 'Booking with offer')}: ${o['title']}',
        )));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPatient = AppState.context['role'] == 'patient';
    final phone = o['clinic_phone'] as String?;
    final until = o['valid_until'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text(offerKindInfo(o['kind'] as String?).$1)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
        OfferCard(o: o),
        if ((o['body'] as String?)?.isNotEmpty == true)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(o['body'] as String, style: const TextStyle(height: 1.7, fontSize: 15.5)),
            ),
          ),
        if (until != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: InfoBanner(icon: Icons.timer_outlined, color: Tone.orange,
                text: '${tr('العرض ساري لحد', 'Valid until')} ${formatDate(until)}'),
          ),
        if (o['clinic_name'] != null)
          Card(
            child: ListTile(
              leading: const Icon3D(Icons.local_hospital_rounded, color: Tone.blue, size: 40),
              title: Text(o['clinic_name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text([o['clinic_address'], o['city'], o['governorate']].whereType<String>().join('، ')),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => DoctorDetailsScreen(doctorId: o['doctor_id'] as String))),
          icon: const Icon(Icons.person_search_rounded),
          label: Text(tr('صفحة الدكتور', 'Doctor’s page')),
        ),
        if (phone != null && phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            icon: const Icon(Icons.call_rounded),
            label: Text('${tr('اتصل بالعيادة', 'Call the clinic')} $phone'),
          ),
        ],
        const SizedBox(height: 10),
        Text(tr('العرض مسؤولية الطبيب، واتأكد من التفاصيل مع العيادة قبل الحجز.',
            'The offer is the doctor’s responsibility; confirm the details with the clinic.'),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
      bottomNavigationBar: isPatient
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _book,
                  icon: const Icon(Icons.event_available_rounded),
                  label: Text(tr('احجز بالعرض', 'Book with this offer')),
                ),
              ),
            )
          : null,
    );
  }
}

// ===========================================================================
// Doctor: my offers + form
// ===========================================================================
class DoctorOffersScreen extends StatefulWidget {
  const DoctorOffersScreen({super.key});
  @override
  State<DoctorOffersScreen> createState() => _DoctorOffersScreenState();
}

class _DoctorOffersScreenState extends State<DoctorOffersScreen> {
  int _key = 0;

  Future<void> _edit([Map<String, dynamic>? o]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => OfferForm(offer: o)));
    if (saved == true) setState(() => _key++);
  }

  Future<void> _delete(Map<String, dynamic> o) async {
    final yes = await confirmDialog(context, title: tr('حذف العرض؟', 'Delete offer?'), body: o['title'] as String? ?? '',
        confirm: tr('حذف', 'Delete'), danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async => rpc('delete_offer', {'p_id': o['id']}));
    if (ok) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('عروضي وإعلاناتي', 'My offers'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.campaign_rounded),
        label: Text(tr('إعلان جديد', 'New offer')),
      ),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () async => ((await rpc('list_offers', {'p_mine': true, 'p_doctor': actingDoctorId()})) as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        builder: (context, list, reload) => RefreshList(onRefresh: reload, children: [
          InfoBanner(icon: Icons.campaign_outlined,
              text: tr('إعلانك بيظهر لكل مرضى ${AppState.appName.value} في «عروض الأطباء»، ويقدروا يحجزوا بيه على طول.',
                  'Your offer shows to every patient in “Doctors’ offers”, and they can book with it right away.')),
          const SizedBox(height: 12),
          if (list.isEmpty)
            EmptyView(icon: Icons.local_offer_rounded, title: tr('لسه ما نزلتش إعلانات', 'No offers yet'),
                subtitle: tr('أعلن عن عملية أو سعر كشف أو أي خدمة في عيادتك.', 'Announce an operation, a visit price or any service.')),
          for (final o in list) ...[
            OfferCard(
              o: o,
              onTap: () => _edit(o),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? _edit(o) : _delete(o),
                itemBuilder: (c) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('تعديل', 'Edit'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('حذف', 'Delete'))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                StatusChip('👁 ${o['views'] ?? 0} ${tr('مشاهدة', 'views')}', color: Tone.blue),
                StatusChip('📅 ${o['bookings'] ?? 0} ${tr('حجز بالعرض', 'bookings')}', color: Tone.green),
                if (o['hidden_by_admin'] == true) StatusChip(tr('أوقفته الإدارة', 'Hidden by admin'), color: Tone.red)
                else if (o['is_active'] != true) StatusChip(tr('متوقف', 'Paused'), color: Colors.grey)
                else if (o['valid_until'] != null &&
                    (DateTime.tryParse('${o['valid_until']}')?.isBefore(DateTime.now().subtract(const Duration(days: 1))) ?? false))
                  StatusChip(tr('انتهى', 'Ended'), color: Colors.grey)
                else
                  StatusChip(tr('ظاهر للمرضى ✓', 'Live ✓'), color: Tone.green),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class OfferForm extends StatefulWidget {
  const OfferForm({super.key, this.offer});
  final Map<String, dynamic>? offer;
  @override
  State<OfferForm> createState() => _OfferFormState();
}

class _OfferFormState extends State<OfferForm> {
  late final _title = TextEditingController(text: widget.offer?['title'] as String?);
  late final _body = TextEditingController(text: widget.offer?['body'] as String?);
  late final _price = TextEditingController(text: _num(widget.offer?['price'])?.toString() ?? '');
  late final _old = TextEditingController(text: _num(widget.offer?['old_price'])?.toString() ?? '');
  late String _kind = widget.offer?['kind'] as String? ?? 'service';
  late String? _image = widget.offer?['image_url'] as String?;
  late DateTime? _until = DateTime.tryParse('${widget.offer?['valid_until']}');
  late bool _active = widget.offer?['is_active'] as bool? ?? true;

  Future<void> _save() async {
    if (_title.text.trim().length < 3) {
      showMessage(context, tr('اكتب عنوان الإعلان', 'Enter a title'), error: true);
      return;
    }
    final ok = await runBusy(context, () async {
      await rpc('save_offer', {
        'p_id': widget.offer?['id'],
        'p_title': _title.text.trim(),
        'p_kind': _kind,
        'p_body': _body.text.trim(),
        'p_price': num.tryParse(_price.text.trim()),
        'p_old_price': num.tryParse(_old.text.trim()),
        'p_image_url': _image,
        'p_valid_until': _until == null
            ? null
            : '${_until!.year}-${_until!.month.toString().padLeft(2, '0')}-${_until!.day.toString().padLeft(2, '0')}',
        'p_active': _active,
        'p_doctor': actingDoctorId(),
      });
    }, success: tr('الإعلان نزل لكل المرضى ✓', 'Offer published ✓'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.offer == null ? tr('إعلان جديد', 'New offer') : tr('تعديل الإعلان', 'Edit offer'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
        Text(tr('نوع الإعلان', 'Type'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in offerKinds)
            ChoiceChip(
              avatar: Icon(offerKindInfo(k).$2, size: 18),
              label: Text(offerKindInfo(k).$1),
              selected: _kind == k,
              onSelected: (_) => setState(() => _kind = k),
            ),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () async {
            final url = await pickAndUploadOfferImage(context);
            if (url != null) setState(() => _image = url);
          },
          child: Container(
            height: 170,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: _image != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.network(_image!, fit: BoxFit.cover),
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: IconButton.filled(onPressed: () => setState(() => _image = null), icon: const Icon(Icons.close)),
                    ),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_photo_alternate_rounded, size: 44),
                    const SizedBox(height: 6),
                    Text(tr('ضيف صورة للإعلان (اختياري)', 'Add a picture (optional)')),
                  ]),
          ),
        ),
        const SizedBox(height: 14),
        TextField(controller: _title, maxLength: 120,
            decoration: InputDecoration(labelText: tr('عنوان الإعلان', 'Title'),
                hintText: tr('مثلاً: عملية الغضروف بالمنظار بسعر خاص', 'e.g. Special price on knee arthroscopy'))),
        TextField(controller: _body, maxLines: 5, maxLength: 1500,
            decoration: InputDecoration(labelText: tr('التفاصيل', 'Details'),
                hintText: tr('إيه اللي يشمله العرض، وشروطه، والمواعيد', 'What it includes, conditions, timing'))),
        Row(children: [
          Expanded(child: TextField(controller: _price, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('السعر', 'Price'), suffixText: tr('ج.م', 'EGP')))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _old, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: tr('السعر قبل العرض', 'Old price'), suffixText: tr('ج.م', 'EGP')))),
        ]),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timer_outlined),
          title: Text(tr('العرض ساري لحد', 'Valid until')),
          subtitle: Text(_until == null ? tr('مفتوح', 'Open') : formatDate(_until!.toIso8601String())),
          trailing: _until == null ? null : IconButton(onPressed: () => setState(() => _until = null), icon: const Icon(Icons.close)),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _until ?? DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() => _until = d);
          },
        ),
        if (widget.offer != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: Text(tr('الإعلان ظاهر للمرضى', 'Visible to patients')),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _save,
            icon: const Icon(Icons.campaign_rounded),
            label: Text(widget.offer == null ? tr('نشر الإعلان', 'Publish') : tr('حفظ', 'Save')),
          ),
        ),
      ),
    );
  }
}
