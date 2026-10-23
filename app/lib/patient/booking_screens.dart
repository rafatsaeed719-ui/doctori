import 'package:flutter/material.dart';

import '../common/reviews.dart';

import '../common/map_widgets.dart';
import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

const _weekShortAr = ['أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];
const _weekShortEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
String _dayShort(DateTime d) => (L10n.isAr ? _weekShortAr : _weekShortEn)[d.weekday % 7];
String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "17:20" → "5:20 م"
String hhmm12(String? t) => formatTime(t == null ? null : '$t:00');

(String, Color) appointmentStatus(String? s) => switch (s) {
      'pending' => (tr('بانتظار التأكيد', 'Awaiting confirmation'), Tone.orange),
      'confirmed' => (tr('مؤكد', 'Confirmed'), Tone.green),
      'cancelled' => (tr('ملغي', 'Cancelled'), Tone.red),
      'completed' => (tr('تم الكشف', 'Completed'), Tone.blue),
      'no_show' => (tr('لم يحضر', 'No show'), Colors.grey),
      _ => (s ?? '', Colors.grey),
    };

/// Pick clinic → day → free time. Patients book for themselves; staff pass [patientId] to book for a linked patient.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, required this.doctor, this.patientId, this.patientName, this.initialNote, this.offerId});
  final Map<String, dynamic> doctor; // from get_doctor_public (has clinics with hours)
  final String? patientId;
  final String? patientName;

  /// Booking from a doctor's offer: the note mentions the offer and the booking is counted for it.
  final String? initialNote;
  final String? offerId;
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late final List<Map<String, dynamic>> _clinics =
      (widget.doctor['clinics'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Map<String, dynamic>? _clinic;
  late DateTime _day;
  Future<List<Map<String, dynamic>>>? _slots;
  String? _picked;
  late final _note = TextEditingController(text: widget.initialNote);

  @override
  void initState() {
    super.initState();
    if (_clinics.isNotEmpty) _clinic = _clinics.first;
    _day = _nextOpenDay(DateTime.now()) ?? DateTime.now();
    _loadSlots();
  }

  Set<int> get _openWeekdays =>
      {for (final h in (_clinic?['hours'] as List? ?? const [])) (h as Map)['weekday'] as int};

  DateTime? _nextOpenDay(DateTime from) {
    for (var i = 0; i < 30; i++) {
      final d = DateTime(from.year, from.month, from.day).add(Duration(days: i));
      if (_openWeekdays.contains(d.weekday % 7)) return d;
    }
    return null;
  }

  void _loadSlots() {
    if (_clinic == null) return;
    _picked = null;
    _slots = rpcList('clinic_slots', {'p_clinic': _clinic!['id'], 'p_date': _iso(_day)});
  }

  Future<void> _book() async {
    if (_picked == null) return;
    final ok = await runBusy(context, () async {
      await rpc('book_appointment', {
        'p_clinic': _clinic!['id'],
        'p_starts_at': _picked,
        'p_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        if (widget.patientId != null) 'p_patient': widget.patientId,
      });
    });
    if (!ok || !mounted) return;
    if (widget.offerId != null) {
      rpc('offer_event', {'p_id': widget.offerId, 'p_event': 'booking'}).catchError((_) => null);
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon3D(Icons.event_available_rounded, color: Tone.green, size: 60),
        title: Text(widget.patientId == null ? tr('تم إرسال الحجز 🎉', 'Booking sent 🎉') : tr('تم الحجز ✓', 'Booked ✓')),
        content: Text(widget.patientId == null
            ? tr('حجزك بانتظار تأكيد العيادة. تابع حالته من «مواعيدي».', 'Waiting for the clinic to confirm. Follow it in “My appointments”.')
            : tr('الحجز اتسجل ومؤكد.', 'The booking is saved and confirmed.')),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('تمام', 'OK')))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = [for (var i = 0; i < 21; i++) DateTime.now().add(Duration(days: i))];
    return Scaffold(
      appBar: AppBar(title: Text(widget.patientName == null
          ? tr('احجز موعد', 'Book an appointment')
          : '${tr('حجز لـ', 'Book for')} ${widget.patientName}')),
      body: _clinics.isEmpty
          ? EmptyView(icon: Icons.event_busy, title: tr('الطبيب لم يضف عيادات بعد', 'No clinics yet'))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                UserAvatar(url: widget.doctor['avatar_url'] as String?, name: widget.doctor['full_name'] as String?, radius: 24),
                const SizedBox(width: 10),
                Expanded(child: Text('${tr('د.', 'Dr.')} ${widget.doctor['full_name'] ?? ''}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              ]),
              if (_clinics.length > 1) ...[
                SectionTitle(tr('العيادة', 'Clinic')),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in _clinics)
                    ChoiceChip(
                      label: Text(c['name'] ?? ''),
                      selected: _clinic?['id'] == c['id'],
                      onSelected: (_) => setState(() {
                        _clinic = c;
                        _day = _nextOpenDay(DateTime.now()) ?? DateTime.now();
                        _loadSlots();
                      }),
                    ),
                ]),
              ],
              SectionTitle(tr('اليوم', 'Day')),
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: days.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final d = days[i];
                    final open = _openWeekdays.contains(d.weekday % 7);
                    final sel = _iso(d) == _iso(_day);
                    return GestureDetector(
                      onTap: open ? () => setState(() {
                            _day = d;
                            _loadSlots();
                          }) : null,
                      child: Container(
                        width: 62,
                        decoration: BoxDecoration(
                          color: sel ? cs.primary : (open ? cs.surface : cs.surfaceContainerHighest),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: sel ? cs.primary : cs.outlineVariant),
                          boxShadow: sel ? [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))] : null,
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(_dayShort(d), style: TextStyle(fontSize: 12, color: sel ? cs.onPrimary : (open ? cs.onSurface : cs.outline))),
                          Text('${d.day}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                              color: sel ? cs.onPrimary : (open ? cs.onSurface : cs.outline))),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              SectionTitle(tr('الميعاد', 'Time')),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _slots,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const LoadingView();
                  if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(_loadSlots));
                  final slots = snap.data ?? const [];
                  if (slots.isEmpty) {
                    return Text(tr('العيادة مقفولة اليوم ده. اختار يوم تاني.', 'The clinic is closed this day. Pick another.'));
                  }
                  if (!slots.any((s) => s['available'] == true)) {
                    return Text(tr('كل المواعيد محجوزة اليوم ده.', 'All times are booked this day.'));
                  }
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in slots)
                      ChoiceChip(
                        label: Text(hhmm12(s['label'] as String?)),
                        selected: _picked == s['starts_at'],
                        onSelected: s['available'] == true ? (_) => setState(() => _picked = s['starts_at'] as String) : null,
                      ),
                  ]);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                maxLength: 300,
                decoration: InputDecoration(labelText: tr('ملاحظة للعيادة (اختياري)', 'Note to the clinic (optional)'),
                    hintText: tr('مثلاً: كشف متابعة', 'e.g. follow-up visit')),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _picked == null ? null : _book,
                icon: const Icon(Icons.event_available_rounded),
                label: Text(tr('تأكيد الحجز', 'Confirm booking')),
              ),
            ]),
    );
  }
}

/// Patient: upcoming and past appointments, with cancel and directions.
class MyAppointmentsScreen extends StatelessWidget {
  const MyAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('مواعيدي', 'My appointments'))),
      body: FutureView<List<Map<String, dynamic>>>(
        load: () async {
          final r = await rpc('patient_my_appointments');
          return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        },
        builder: (context, list, reload) {
          final now = DateTime.now();
          bool upcoming(Map<String, dynamic> a) =>
              (DateTime.tryParse(a['starts_at'] as String? ?? '')?.isAfter(now) ?? false) &&
              (a['status'] == 'pending' || a['status'] == 'confirmed');
          final next = list.where(upcoming).toList().reversed.toList();
          final past = list.where((a) => !upcoming(a)).toList();
          return RefreshList(onRefresh: reload, children: [
            if (list.isEmpty)
              EmptyView(icon: Icons.event_note_rounded, title: tr('لا توجد مواعيد', 'No appointments'),
                  subtitle: tr('احجز من صفحة أي طبيب: زرار «احجز موعد».', 'Book from any doctor page: “Book appointment”.')),
            if (next.isNotEmpty) SectionTitle(tr('القادمة', 'Upcoming')),
            for (final a in next) _AppointmentCard(a: a, onChanged: reload, canCancel: true),
            if (past.isNotEmpty) SectionTitle(tr('السابقة', 'Past')),
            for (final a in past) _AppointmentCard(a: a, onChanged: reload, canCancel: false),
          ]);
        },
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.a, required this.onChanged, required this.canCancel});
  final Map<String, dynamic> a;
  final Future<void> Function() onChanged;
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    final (label, color) = appointmentStatus(a['status'] as String?);
    final d = DateTime.tryParse('${a['local_date']}');
    final lat = (a['lat'] as num?)?.toDouble(), lng = (a['lng'] as num?)?.toDouble();
    final now = DateTime.now();
    final isToday = d != null && d.year == now.year && d.month == now.month && d.day == now.day;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [lighten(color, 0.25), color]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Text(d == null ? '' : _dayShort(d), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Text(d == null ? '' : '${d.day}/${d.month}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr('د.', 'Dr.')} ${a['doctor_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${hhmm12(a['local_time'] as String?)} • ${a['clinic_name'] ?? ''}'),
                ]),
              ),
              StatusChip(label, color: color),
            ]),
            if (isToday && (a['status'] == 'pending' || a['status'] == 'confirmed'))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: Tone.teal),
                  onPressed: () async {
                    final ok = await runBusy(context, () async => rpc('queue_checkin', {'p_appointment': a['id']}),
                        success: tr('اتسجل وصولك ✓ هتلاقي رقمك في الصفحة الرئيسية', 'Checked in ✓ — your number is on the home screen'));
                    if (ok) onChanged();
                  },
                  icon: const Icon(Icons.where_to_vote_rounded),
                  label: Text(tr('وصلت العيادة', 'I have arrived')),
                ),
              ),
            if (a['status'] == 'completed' && a['doctor_id'] != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => rateDoctorDialog(context, a['doctor_id'] as String, doctorName: a['doctor_name'] as String?),
                  icon: const Icon(Icons.star_rounded, color: Tone.amber),
                  label: Text(tr('قيّم الزيارة', 'Rate visit')),
                ),
              ),
            if (canCancel || (lat != null && lng != null))
              Row(children: [
                if (lat != null && lng != null)
                  TextButton.icon(onPressed: () => openDirections(context, lat, lng),
                      icon: const Icon(Icons.directions), label: Text(tr('الاتجاهات', 'Directions'))),
                const Spacer(),
                if (canCancel)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () async {
                      final yes = await confirmDialog(context,
                          title: tr('إلغاء الحجز؟', 'Cancel booking?'),
                          body: tr('الميعاد هيتلغي ويبقى متاح لغيرك.', 'The time will be freed for others.'),
                          confirm: tr('إلغاء الحجز', 'Cancel booking'),
                          danger: true);
                      if (!yes || !context.mounted) return;
                      final ok = await runBusy(context, () async {
                        await rpc('set_appointment_status', {'p_id': a['id'], 'p_status': 'cancelled'});
                      }, success: tr('تم إلغاء الحجز', 'Booking cancelled'));
                      if (ok) onChanged();
                    },
                    icon: const Icon(Icons.close),
                    label: Text(tr('إلغاء', 'Cancel')),
                  ),
              ]),
          ]),
        ),
      ),
    );
  }
}
