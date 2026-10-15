import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../patient/booking_screens.dart';

const _monthsAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
// Egyptian week starts on Saturday.
const _headAr = ['سبت', 'أحد', 'اثن', 'ثلا', 'أرب', 'خمي', 'جمع'];
const _headEn = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Doctor / assistant: month calendar with the number of visits per day, and the day's list with actions.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateTime.now();
  int _key = 0;

  Future<List<Map<String, dynamic>>> _load() async {
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1, 0);
    final r = await rpc('doctor_appointments', {'p_from': _iso(from), 'p_to': _iso(to), 'p_doctor': actingDoctorId()});
    return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _shiftMonth(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _selected = _month.year == DateTime.now().year && _month.month == DateTime.now().month ? DateTime.now() : _month;
        _key++;
      });

  Future<void> _setStatus(Map<String, dynamic> a, String status) async {
    final ok = await runBusy(context, () async {
      await rpc('set_appointment_status', {'p_id': a['id'], 'p_status': status});
    }, success: tr('تم التحديث', 'Updated'));
    if (ok) setState(() => _key++);
  }

  Future<void> _bookForPatient() async {
    List<Map<String, dynamic>> patients;
    Map<String, dynamic>? doctor;
    try {
      patients = await rpcList('doctor_my_patients', {'p_doctor': actingDoctorId()});
      final d = await rpc('get_doctor_public', {'p_doctor': actingDoctorId()});
      doctor = d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    if (doctor == null) {
      showMessage(context, tr('الحجز متاح بعد توثيق حساب الطبيب.', 'Available after the doctor is verified.'), error: true);
      return;
    }
    if (patients.isEmpty) {
      showMessage(context, tr('مفيش مرضى في العيادة لسه، أو مش مسموحلك تشوف قائمة المرضى.',
          'No clinic patients yet, or you are not allowed to see them.'), error: true);
      return;
    }
    final p = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr('اختار المريض', 'Choose the patient'), style: Theme.of(c).textTheme.titleLarge),
            ),
            for (final x in patients)
              ListTile(
                leading: UserAvatar(url: x['avatar_url'] as String?, name: x['patient_name'] as String?, radius: 20),
                title: Text(x['patient_name'] ?? ''),
                subtitle: Text(displayPhone(x['phone'] as String?)),
                onTap: () => Navigator.pop(c, x),
              ),
          ]),
        ),
      ),
    );
    if (p == null || !mounted) return;
    final done = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => BookingScreen(doctor: doctor!, patientId: p['patient_id'] as String, patientName: p['patient_name'] as String?)));
    if (done == true) setState(() => _key++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('الحجوزات', 'Bookings'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bookForPatient,
        icon: const Icon(Icons.add),
        label: Text(tr('حجز لمريض', 'Book for patient')),
      ),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: _load,
        builder: (context, list, reload) {
          final byDay = <String, List<Map<String, dynamic>>>{};
          for (final a in list) {
            byDay.putIfAbsent(a['local_date'] as String, () => []).add(a);
          }
          final dayList = byDay[_iso(_selected)] ?? const [];
          final active = list.where((a) => a['status'] != 'cancelled').length;
          final pending = list.where((a) => a['status'] == 'pending').length;
          return RefreshList(onRefresh: reload, children: [
            Row(children: [
              Expanded(child: _SummaryTile(icon: Icons.event_available_rounded, color: Tone.blue,
                  value: '$active', label: tr('حجز الشهر ده', 'this month'))),
              const SizedBox(width: 10),
              Expanded(child: _SummaryTile(icon: Icons.hourglass_top_rounded, color: Tone.orange,
                  value: '$pending', label: tr('بانتظار التأكيد', 'awaiting'))),
            ]),
            const SizedBox(height: 14),
            _Calendar(
              month: _month,
              selected: _selected,
              counts: {for (final e in byDay.entries) e.key: e.value.where((a) => a['status'] != 'cancelled').length},
              pendings: {for (final e in byDay.entries) e.key: e.value.where((a) => a['status'] == 'pending').length},
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onPick: (d) => setState(() => _selected = d),
            ),
            SectionTitle('${tr('حجوزات', 'Bookings on')} ${formatDate(_selected.toIso8601String())} '
                '(${dayList.where((a) => a['status'] != 'cancelled').length})'),
            if (dayList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('مفيش حجوزات في اليوم ده.', 'No bookings this day.'), textAlign: TextAlign.center),
              ),
            for (final a in dayList) _DayItem(a: a, onStatus: (s) => _setStatus(a, s)),
          ]);
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.icon, required this.color, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon3D(icon, color: color, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: darken(color, 0.15))),
                Text(label, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ]),
        ),
      );
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.selected,
    required this.counts,
    required this.pendings,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });
  final DateTime month;
  final DateTime selected;
  final Map<String, int> counts;
  final Map<String, int> pendings;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = (first.weekday + 1) % 7; // Saturday = 0
    final today = _iso(DateTime.now());
    final cells = <Widget>[
      for (final h in (L10n.isAr ? _headAr : _headEn))
        Center(child: Text(h, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        Builder(builder: (context) {
          final date = DateTime(month.year, month.month, d);
          final key = _iso(date);
          final n = counts[key] ?? 0;
          final p = pendings[key] ?? 0;
          final sel = key == _iso(selected);
          return GestureDetector(
            onTap: () => onPick(date),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: sel ? cs.primary : (n > 0 ? cs.primaryContainer.withValues(alpha: 0.6) : null),
                borderRadius: BorderRadius.circular(12),
                border: key == today ? Border.all(color: cs.primary, width: 2) : null,
              ),
              child: Stack(children: [
                Center(
                  child: Text('$d', style: TextStyle(fontWeight: FontWeight.w800, color: sel ? cs.onPrimary : cs.onSurface)),
                ),
                if (n > 0)
                  PositionedDirectional(
                    bottom: 2,
                    end: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: p > 0 ? Tone.orange : Tone.green, borderRadius: BorderRadius.circular(8)),
                      child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ]),
            ),
          );
        }),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('${(L10n.isAr ? _monthsAr : _monthsEn)[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ]),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1,
            children: cells,
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _dot(Tone.green), Text(tr(' كله مؤكد   ', ' all confirmed   '), style: const TextStyle(fontSize: 11.5)),
            _dot(Tone.orange), Text(tr(' فيه حجوزات بانتظار التأكيد', ' has pending'), style: const TextStyle(fontSize: 11.5)),
          ]),
        ]),
      ),
    );
  }

  Widget _dot(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

class _DayItem extends StatelessWidget {
  const _DayItem({required this.a, required this.onStatus});
  final Map<String, dynamic> a;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final (label, color) = appointmentStatus(a['status'] as String?);
    final phone = a['patient_phone'] as String?;
    final status = a['status'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(hhmm12(a['local_time'] as String?),
                    style: TextStyle(fontWeight: FontWeight.w900, color: darken(color, 0.2))),
              ),
              const SizedBox(width: 10),
              UserAvatar(url: a['patient_avatar'] as String?, name: a['patient_name'] as String?, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['patient_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(a['clinic_name'] ?? '', style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
              StatusChip(label, color: color),
            ]),
            if ((a['patient_note'] as String?)?.isNotEmpty == true)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('«${a['patient_note']}»')),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (status == 'pending')
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: Tone.green),
                  onPressed: () => onStatus('confirmed'),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(tr('تأكيد', 'Confirm')),
                ),
              if (status == 'pending' || status == 'confirmed') ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => onStatus('completed'),
                  child: Text(tr('تم الكشف', 'Done')),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => onStatus('cancelled'),
                  child: Text(tr('إلغاء', 'Cancel')),
                ),
                TextButton(onPressed: () => onStatus('no_show'), child: Text(tr('لم يحضر', 'No show'))),
              ],
              if (phone != null && phone.isNotEmpty)
                IconButton(
                  tooltip: displayPhone(phone),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: displayPhone(phone))),
                  icon: const Icon(Icons.call),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
