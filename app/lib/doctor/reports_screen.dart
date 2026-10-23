import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'finance_screen.dart' show incomeKindInfo, monthName;

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
final _fmt = intl.NumberFormat('#,##0', 'en');
// 0 = Sunday (database order)
String _shortDay(int d) => (L10n.isAr
    ? const ['أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت']
    : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'])[d];

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

/// Clinic reports with simple charts: visits, busiest days and hours, services, money, patients, offers.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final to = DateTime.now();
    final from = _days == 0 ? DateTime(to.year, 1, 1) : to.subtract(Duration(days: _days - 1));
    return Scaffold(
      appBar: AppBar(title: Text(tr('التقارير', 'Reports'))),
      body: FutureView<Map<String, dynamic>>(
        key: ValueKey(_days),
        load: () async => Map<String, dynamic>.from(
            await rpc('doctor_reports', {'p_from': _iso(from), 'p_to': _iso(to), 'p_doctor': actingDoctorId()}) as Map),
        builder: (context, r, reload) {
          final ap = Map<String, dynamic>.from(r['appointments'] as Map? ?? const {});
          final fin = r['finance'] is Map ? Map<String, dynamic>.from(r['finance'] as Map) : null;
          final total = _n(ap['total']).toInt();
          final noShowRate = total == 0 ? 0 : (_n(ap['no_show']) / total * 100).round();
          final wd = Map<String, dynamic>.from(r['by_weekday'] as Map? ?? const {});
          final hrs = Map<String, dynamic>.from(r['by_hour'] as Map? ?? const {});
          final byDay = (r['by_day'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final rating = Map<String, dynamic>.from(r['rating'] as Map? ?? const {});
          return RefreshList(onRefresh: reload, children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 7, label: Text(tr('أسبوع', 'Week'))),
                ButtonSegment(value: 30, label: Text(tr('شهر', 'Month'))),
                ButtonSegment(value: 90, label: Text(tr('3 شهور', '3 months'))),
                ButtonSegment(value: 0, label: Text(tr('السنة', 'Year'))),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _Kpi(tr('حجوزات', 'Bookings'), '$total', Icons.event_note_rounded, Tone.blue),
              _Kpi(tr('تم الكشف', 'Completed'), '${ap['completed'] ?? 0}', Icons.check_circle_rounded, Tone.green),
              _Kpi(tr('ملغي', 'Cancelled'), '${ap['cancelled'] ?? 0}', Icons.cancel_rounded, Tone.red),
              _Kpi(tr('لم يحضر', 'No-show'), '$noShowRate٪', Icons.person_off_rounded, Tone.orange),
              _Kpi(tr('مرضى جدد', 'New patients'), '${r['new_patients'] ?? 0}', Icons.person_add_rounded, Tone.purple),
              _Kpi(tr('مرضى متابعين', 'Active patients'), '${r['active_patients'] ?? 0}', Icons.people_alt_rounded, Tone.teal),
              _Kpi(tr('روشتات', 'Prescriptions'), '${r['prescriptions'] ?? 0}', Icons.receipt_long_rounded, Tone.indigo),
              _Kpi(tr('عمليات', 'Surgeries'), '${r['surgeries'] ?? 0}', Icons.local_hospital_rounded, Tone.pink),
              _Kpi(tr('التقييم', 'Rating'), _n(rating['avg']) == 0 ? '—' : '${_n(rating['avg']).toStringAsFixed(1)} ⭐',
                  Icons.star_rounded, Tone.amber),
            ]),
            if (byDay.isNotEmpty) ...[
              SectionTitle(tr('الزيارات يوم بيوم', 'Visits per day')),
              _Card(child: _Bars(
                values: [for (final d in byDay) _n(d['visits'])],
                labels: [for (final d in byDay) '${DateTime.tryParse('${d['day']}')?.day ?? ''}'],
                color: Tone.blue,
                height: 150,
              )),
            ],
            SectionTitle(tr('أكتر الأيام زحمة', 'Busiest weekdays')),
            _Card(child: _Bars(
              // Saturday first, like the Egyptian week. DB: 0 = Sunday.
              values: [for (final d in [6, 0, 1, 2, 3, 4, 5]) _n(wd['$d'])],
              labels: [for (final d in [6, 0, 1, 2, 3, 4, 5]) _shortDay(d)],
              color: Tone.purple,
            )),
            if (hrs.isNotEmpty) ...[
              SectionTitle(tr('أكتر الساعات زحمة', 'Busiest hours')),
              _Card(child: _Bars(
                values: [for (var h = 8; h <= 23; h++) _n(hrs['$h'])],
                labels: [for (var h = 8; h <= 23; h++) '${h % 12 == 0 ? 12 : h % 12}'],
                color: Tone.orange,
              )),
            ],
            if (fin != null) ...[
              SectionTitle(tr('الفلوس', 'Money')),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _Kpi(tr('الدخل', 'Income'), _fmt.format(_n(fin['income'])), Icons.trending_up_rounded, Tone.green),
                _Kpi(tr('المصروفات', 'Expenses'), _fmt.format(_n(fin['expenses'])), Icons.trending_down_rounded, Tone.red),
                _Kpi(tr('الصافي', 'Net'), _fmt.format(_n(fin['income']) - _n(fin['expenses'])), Icons.account_balance_wallet_rounded,
                    Tone.blue),
              ]),
              if ((fin['top_services'] as List? ?? const []).isNotEmpty) ...[
                SectionTitle(tr('أكتر الخدمات دخلاً', 'Top services')),
                _Card(child: Column(children: [
                  for (final s in (fin['top_services'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                    _HBar(
                      label: '${incomeKindInfo(s['kind'] as String?).$1} ${incomeKindInfo(s['kind'] as String?).$2} (${s['count']})',
                      value: _n(s['amount']),
                      max: _n((fin['top_services'] as List).first['amount']),
                      color: incomeKindInfo(s['kind'] as String?).$3,
                    ),
                ])),
              ],
              if ((fin['by_month'] as List? ?? const []).length > 1) ...[
                SectionTitle(tr('الدخل والمصروفات شهرياً', 'Monthly income & expenses')),
                _Card(child: Column(children: [
                  for (final m in (fin['by_month'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        SizedBox(width: 70, child: Text(monthName(int.tryParse('${m['month']}'.split('-').last) ?? 1),
                            style: const TextStyle(fontSize: 12.5))),
                        Expanded(child: Column(children: [
                          _line(_n(m['income']), _maxMonth(fin), Tone.green),
                          const SizedBox(height: 3),
                          _line(_n(m['expenses']), _maxMonth(fin), Tone.red),
                        ])),
                      ]),
                    ),
                ])),
              ],
            ],
            if ((r['offers'] as List? ?? const []).isNotEmpty) ...[
              SectionTitle(tr('أداء الإعلانات', 'Offers performance')),
              _Card(child: Column(children: [
                for (final o in (r['offers'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(o['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text('👁 ${o['views']}   📅 ${o['bookings']}'),
                  ),
              ])),
            ],
          ]);
        },
      ),
    );
  }

  num _maxMonth(Map<String, dynamic> fin) {
    num m = 1;
    for (final x in (fin['by_month'] as List)) {
      final mm = Map<String, dynamic>.from(x as Map);
      if (_n(mm['income']) > m) m = _n(mm['income']);
      if (_n(mm['expenses']) > m) m = _n(mm['expenses']);
    }
    return m;
  }

  Widget _line(num v, num max, Color c) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(value: (v / max).clamp(0, 1).toDouble(), minHeight: 9, color: c,
            backgroundColor: c.withValues(alpha: 0.1)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: child));
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (MediaQuery.of(context).size.width - 32 - 20) / 3;
      return SizedBox(
        width: w,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon3D(icon, color: color, size: 30),
              const SizedBox(height: 6),
              FittedBox(child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: darken(color, 0.2)))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );
    });
  }
}

/// Simple vertical bar chart.
class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.color, this.height = 120});
  final List<num> values;
  final List<String> labels;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) {
    final max = values.fold<num>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: height + 34,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (values[i] > 0) FittedBox(child: Text('${values[i]}', style: const TextStyle(fontSize: 10.5))),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: max == 0 ? 2 : (values[i] / max * height).clamp(2, height).toDouble(),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [lighten(color, 0.2), color]),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(child: Text(labels[i], style: const TextStyle(fontSize: 10.5))),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _HBar extends StatelessWidget {
  const _HBar({required this.label, required this.value, required this.max, required this.color});
  final String label;
  final num value;
  final num max;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text('${_fmt.format(value)} ${tr('ج.م', 'EGP')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: max <= 0 ? 0 : (value / max).clamp(0, 1).toDouble(), minHeight: 10,
                color: color, backgroundColor: color.withValues(alpha: 0.12)),
          ),
        ]),
      );
}
