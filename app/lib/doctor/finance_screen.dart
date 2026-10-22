import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../core/avatar.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/phone.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _monthsAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _headAr = ['سبت', 'أحد', 'اثن', 'ثلا', 'أرب', 'خمي', 'جمع'];
const _headEn = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
String monthName(int m) => (L10n.isAr ? _monthsAr : _monthsEn)[m - 1];

final _fmt = intl.NumberFormat('#,##0.##', 'en');
String money(num? v) => '${_fmt.format(v ?? 0)} ${tr('ج.م', 'EGP')}';

/// Short form for calendar cells: 950 / 1.2k / 15k
String _short(num v) {
  final a = v.abs();
  final s = a >= 10000 ? '${(a / 1000).round()}k' : (a >= 1000 ? '${(a / 1000).toStringAsFixed(1)}k' : '${a.round()}');
  return v < 0 ? '-$s' : s;
}

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

// Income kinds and expense categories (keys match the database).
const incomeKinds = ['visit', 'revisit', 'lab', 'xray', 'session', 'procedure', 'other'];
(String, String, Color) incomeKindInfo(String? k) => switch (k) {
      'visit' => ('🩺', tr('كشف', 'Visit'), Tone.blue),
      'revisit' => ('🔁', tr('إعادة', 'Re-visit'), Tone.teal),
      'lab' => ('🧪', tr('تحليل', 'Lab test'), Tone.purple),
      'xray' => ('🩻', tr('أشعة', 'X-ray / scan'), Tone.indigo),
      'session' => ('💪', tr('جلسة', 'Session'), Tone.green),
      'procedure' => ('🏥', tr('إجراء / عملية', 'Procedure'), Tone.pink),
      _ => ('➕', tr('أخرى', 'Other'), Tone.sky),
    };

const expenseCategories = ['rent', 'salaries', 'supplies', 'utilities', 'equipment', 'maintenance', 'lab', 'marketing', 'transport', 'other'];
(String, String) expenseInfo(String? k) => switch (k) {
      'rent' => ('🏠', tr('إيجار', 'Rent')),
      'salaries' => ('👥', tr('مرتبات', 'Salaries')),
      'supplies' => ('🧰', tr('مستلزمات طبية', 'Medical supplies')),
      'utilities' => ('💡', tr('كهرباء ومياه ونت', 'Utilities')),
      'equipment' => ('🖥️', tr('أجهزة', 'Equipment')),
      'maintenance' => ('🔧', tr('صيانة', 'Maintenance')),
      'lab' => ('🧪', tr('معمل / تحاليل', 'Lab costs')),
      'marketing' => ('📣', tr('دعاية', 'Marketing')),
      'transport' => ('🚗', tr('مواصلات', 'Transport')),
      _ => ('🧾', tr('أخرى', 'Other')),
    };

// ===========================================================================
// Main screen
// ===========================================================================
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  DateTime _day = DateTime.now();
  late DateTime _month = DateTime(_day.year, _day.month);
  int _key = 0;

  Future<(Map<String, dynamic>, Map<String, dynamic>)> _load() async {
    final doc = actingDoctorId();
    final res = await Future.wait([
      rpc('finance_month', {'p_year': _month.year, 'p_month': _month.month, 'p_doctor': doc}),
      rpc('finance_day', {'p_day': _iso(_day), 'p_doctor': doc}),
    ]);
    return (Map<String, dynamic>.from(res[0] as Map), Map<String, dynamic>.from(res[1] as Map));
  }

  void _reload() => setState(() => _key++);

  void _pickDay(DateTime d) => setState(() {
        _day = d;
        _month = DateTime(d.year, d.month);
        _key++;
      });

  void _shiftMonth(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        final now = DateTime.now();
        _day = (_month.year == now.year && _month.month == now.month) ? now : _month;
        _key++;
      });

  Future<void> _search() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: tr('اختار اليوم اللي عايز تعرف دخله', 'Pick a day'),
    );
    if (d != null) _pickDay(d);
  }

  Future<void> _addIncome(Map<String, dynamic> prices, [Map<String, dynamic>? item]) async {
    final saved = await incomeSheet(context, day: _day, prices: prices, item: item);
    if (saved) _reload();
  }

  Future<void> _addExpense([Map<String, dynamic>? item]) async {
    final saved = await expenseSheet(context, day: _day, item: item);
    if (saved) _reload();
  }

  Future<void> _delete(String type, Map<String, dynamic> item) async {
    final yes = await confirmDialog(context,
        title: tr('حذف؟', 'Delete?'), body: '${money(_n(item['amount']))} — ${tr('مش هيترجع تاني.', 'This cannot be undone.')}',
        confirm: tr('حذف', 'Delete'), danger: true);
    if (!yes || !mounted) return;
    final ok = await runBusy(context, () async {
      await rpc('delete_finance_entry', {'p_type': type, 'p_id': item['id']});
    });
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('رصيدي اليومي', 'My daily balance')),
        actions: [
          IconButton(tooltip: tr('ابحث عن يوم', 'Find a day'), onPressed: _search, icon: const Icon(Icons.manage_search_rounded)),
          IconButton(
            tooltip: tr('السنة كلها', 'Whole year'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FinanceYearScreen(year: _month.year))),
            icon: const Icon(Icons.bar_chart_rounded),
          ),
          if (!isAssistant)
            IconButton(
              tooltip: tr('أسعار الكشف والخدمات', 'Prices'),
              onPressed: () async {
                if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PriceListScreen())) == true) _reload();
              },
              icon: const Icon(Icons.sell_outlined),
            ),
        ],
      ),
      body: FutureView<(Map<String, dynamic>, Map<String, dynamic>)>(
        key: ValueKey(_key),
        load: _load,
        builder: (context, data, reload) {
          final (month, day) = data;
          final prices = Map<String, dynamic>.from(day['prices'] as Map? ?? const {});
          final days = {
            for (final d in (month['days'] as List? ?? const [])) '${(d as Map)['day']}': Map<String, dynamic>.from(d),
          };
          final incomeItems = (day['income_items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final expenseItems = (day['expense_items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final byKind = Map<String, dynamic>.from(day['by_kind'] as Map? ?? const {});
          final isToday = _iso(_day) == _iso(DateTime.now());
          return Stack(children: [
            RefreshList(onRefresh: reload, padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
              _DayHeader(
                title: isToday
                    ? tr('النهارده', 'Today')
                    : '${weekdayName(_day.weekday % 7)} ${formatDate(_day.toIso8601String())}',
                income: _n(day['income']),
                expenses: _n(day['expenses']),
                net: _n(day['net']),
                cases: _n(day['cases']).toInt(),
              ),
              if (byKind.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final k in incomeKinds)
                    if (byKind[k] != null)
                      StatusChip(
                        '${incomeKindInfo(k).$1} ${incomeKindInfo(k).$2} ×${(byKind[k] as Map)['count']} = ${money(_n((byKind[k] as Map)['amount']))}',
                        color: incomeKindInfo(k).$3,
                      ),
                ]),
              ],
              SectionTitle('${tr('الدخل', 'Income')} (${incomeItems.length})'),
              if (incomeItems.isEmpty)
                Text(tr('مفيش دخل متسجل في اليوم ده.', 'No income recorded this day.'), textAlign: TextAlign.center),
              for (final i in incomeItems)
                _EntryTile(
                  emoji: incomeKindInfo(i['kind'] as String?).$1,
                  color: incomeKindInfo(i['kind'] as String?).$3,
                  title: '${incomeKindInfo(i['kind'] as String?).$2}'
                      '${(i['patient_name'] as String?)?.isNotEmpty == true ? ' — ${i['patient_name']}' : ''}',
                  subtitle: [i['note'], if (i['by'] != null) '${tr('سجّله', 'by')} ${i['by']}']
                      .whereType<String>().where((s) => s.isNotEmpty).join(' • '),
                  amount: '+${money(_n(i['amount']))}',
                  amountColor: Tone.green,
                  avatar: i['patient_id'] != null ? UserAvatar(url: i['patient_avatar'] as String?, name: i['patient_name'] as String?, radius: 18) : null,
                  onTap: () => _addIncome(prices, i),
                  onDelete: () => _delete('income', i),
                ),
              SectionTitle('${tr('المصروفات', 'Expenses')} (${expenseItems.length})'),
              if (expenseItems.isEmpty)
                Text(tr('مفيش مصروفات في اليوم ده.', 'No expenses this day.'), textAlign: TextAlign.center),
              for (final e in expenseItems)
                _EntryTile(
                  emoji: expenseInfo(e['category'] as String?).$1,
                  color: Tone.red,
                  title: expenseInfo(e['category'] as String?).$2,
                  subtitle: [e['reason'], if (e['by'] != null) '${tr('سجّله', 'by')} ${e['by']}']
                      .whereType<String>().where((s) => s.isNotEmpty).join(' • '),
                  amount: '−${money(_n(e['amount']))}',
                  amountColor: Tone.red,
                  onTap: () => _addExpense(e),
                  onDelete: () => _delete('expense', e),
                ),
              const SizedBox(height: 18),
              _MonthCalendar(
                month: _month,
                selected: _day,
                days: days,
                onPrev: () => _shiftMonth(-1),
                onNext: () => _shiftMonth(1),
                onPick: _pickDay,
              ),
              const SizedBox(height: 12),
              _MonthTotals(month: month),
            ]),
            PositionedDirectional(
              start: 16,
              end: 16,
              bottom: 16,
              child: SafeArea(
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Tone.green, minimumSize: const Size.fromHeight(52)),
                      onPressed: () => _addIncome(prices),
                      icon: const Icon(Icons.add_circle_rounded),
                      label: Text(tr('دخل حالة', 'Add income')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Tone.red, minimumSize: const Size.fromHeight(52)),
                      onPressed: () => _addExpense(),
                      icon: const Icon(Icons.remove_circle_rounded),
                      label: Text(tr('مصروف', 'Add expense')),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.title, required this.income, required this.expenses, required this.net, required this.cases});
  final String title;
  final num income;
  final num expenses;
  final num net;
  final int cases;

  @override
  Widget build(BuildContext context) {
    final positive = net >= 0;
    final base = positive ? Tone.green : Tone.red;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [lighten(base, 0.05), darken(base, 0.25)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: base.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon3D(Icons.account_balance_wallet_rounded, color: Tone.amber, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              Text(tr('الصافي (الدخل − المصروفات)', 'Net (income − expenses)'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
            child: Text('👥 ${tr('$cases حالة', '$cases cases')}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        FittedBox(
          child: Text(money(net), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _pill('⬆️ ${tr('دخل', 'In')}', money(income))),
          const SizedBox(width: 8),
          Expanded(child: _pill('⬇️ ${tr('مصروفات', 'Out')}', money(expenses))),
        ]),
      ]),
    );
  }

  Widget _pill(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          FittedBox(child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
        ]),
      );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.emoji,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
    this.avatar,
    this.onTap,
    this.onDelete,
  });
  final String emoji;
  final Color color;
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final Widget? avatar;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: onTap,
          onLongPress: onDelete,
          leading: avatar ?? Icon3D(null, color: color, size: 40, emoji: emoji),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(amount, style: TextStyle(fontWeight: FontWeight.w900, color: darken(amountColor, 0.1))),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') {
                  onTap?.call();
                } else {
                  onDelete?.call();
                }
              },
              itemBuilder: (c) => [
                PopupMenuItem(value: 'edit', child: Text(tr('تعديل', 'Edit'))),
                PopupMenuItem(value: 'delete', child: Text(tr('حذف', 'Delete'))),
              ],
            ),
          ]),
        ),
      );
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selected,
    required this.days,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });
  final DateTime month;
  final DateTime selected;
  final Map<String, Map<String, dynamic>> days;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final lead = (first.weekday + 1) % 7; // Saturday first
    final today = _iso(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('${monthName(month.month)} ${month.year}',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ]),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.72,
            children: [
              for (final h in (L10n.isAr ? _headAr : _headEn))
                Center(child: Text(h, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= count; d++)
                Builder(builder: (context) {
                  final date = DateTime(month.year, month.month, d);
                  final key = _iso(date);
                  final info = days[key];
                  final cases = _n(info?['cases']).toInt();
                  final net = _n(info?['net']);
                  final sel = key == _iso(selected);
                  final has = info != null;
                  return GestureDetector(
                    onTap: () => onPick(date),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: sel ? cs.primary : (has ? (net >= 0 ? lighten(Tone.green, 0.82) : lighten(Tone.red, 0.82)) : null),
                        borderRadius: BorderRadius.circular(10),
                        border: key == today ? Border.all(color: cs.primary, width: 2) : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        Text('$d', style: TextStyle(fontWeight: FontWeight.w900, color: sel ? cs.onPrimary : cs.onSurface)),
                        if (has) ...[
                          Text('👥$cases', style: TextStyle(fontSize: 9.5, color: sel ? cs.onPrimary : Colors.black87)),
                          FittedBox(
                            child: Text(_short(net),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                                    color: sel ? cs.onPrimary : (net >= 0 ? darken(Tone.green, 0.3) : Tone.red))),
                          ),
                        ],
                      ]),
                    ),
                  );
                }),
            ],
          ),
          const SizedBox(height: 4),
          Text(tr('كل يوم: 👥 عدد الحالات والصافي. اضغط أي يوم تشوف تفاصيله.',
              'Each day: 👥 cases and net. Tap a day for details.'),
              style: const TextStyle(fontSize: 11.5), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.month});
  final Map<String, dynamic> month;

  @override
  Widget build(BuildContext context) {
    final income = _n(month['income']), expenses = _n(month['expenses']), net = _n(month['net']);
    final byKind = Map<String, dynamic>.from(month['by_kind'] as Map? ?? const {});
    final byCat = Map<String, dynamic>.from(month['by_category'] as Map? ?? const {});
    final m = _n(month['month']).toInt();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${tr('إجمالي شهر', 'Total for')} ${m > 0 ? monthName(m) : ''}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _stat(tr('الدخل', 'Income'), money(income), Tone.green)),
            Expanded(child: _stat(tr('المصروفات', 'Expenses'), money(expenses), Tone.red)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _stat(tr('الصافي', 'Net'), money(net), net >= 0 ? Tone.blue : Tone.red)),
            Expanded(child: _stat(tr('عدد الحالات', 'Cases'), '${_n(month['cases']).toInt()}', Tone.purple)),
          ]),
          if (byKind.isNotEmpty) ...[
            const Divider(height: 24),
            Text(tr('الدخل حسب النوع', 'Income by type'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final k in incomeKinds)
              if (byKind[k] != null)
                _bar('${incomeKindInfo(k).$1} ${incomeKindInfo(k).$2} (${(byKind[k] as Map)['count']})',
                    _n((byKind[k] as Map)['amount']), income, incomeKindInfo(k).$3),
          ],
          if (byCat.isNotEmpty) ...[
            const Divider(height: 24),
            Text(tr('المصروفات حسب النوع', 'Expenses by type'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final k in expenseCategories)
              if (byCat[k] != null)
                _bar('${expenseInfo(k).$1} ${expenseInfo(k).$2}', _n((byCat[k] as Map)['amount']), expenses, Tone.red),
          ],
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, Color c) => Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: darken(c, 0.2)))),
          ]),
        ),
      );

  Widget _bar(String label, num value, num total, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(money(value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total <= 0 ? 0 : (value / total).clamp(0, 1).toDouble(),
              minHeight: 8,
              color: c,
              backgroundColor: c.withValues(alpha: 0.12),
            ),
          ),
        ]),
      );
}

// ===========================================================================
// Add / edit income and expenses
// ===========================================================================

/// Records what a case paid. Pre-fill [patientId]/[patientName]/[appointmentId] when called from a booking.
Future<bool> incomeSheet(BuildContext context,
    {DateTime? day,
    Map<String, dynamic>? prices,
    Map<String, dynamic>? item,
    String? patientId,
    String? patientName,
    String? appointmentId,
    String initialKind = 'visit'}) async {
  if (prices == null) {
    try {
      final d = await rpc('finance_day', {'p_day': _iso(day ?? DateTime.now()), 'p_doctor': actingDoctorId()});
      prices = Map<String, dynamic>.from((d as Map)['prices'] as Map? ?? const {});
    } catch (_) {
      prices = const {};
    }
  }
  if (!context.mounted) return false;
  final Map<String, dynamic> pr = prices ?? const {};
  var kind = item?['kind'] as String? ?? initialKind;
  String priceFor(String k) => pr[k] == null ? '' : '${pr[k]}';
  final amount = TextEditingController(text: item != null ? '${_n(item['amount'])}' : priceFor(kind));
  final note = TextEditingController(text: item?['note'] as String?);
  String? pid = item?['patient_id'] as String? ?? patientId;
  final name = TextEditingController(text: item?['patient_name'] as String? ?? patientName);
  var date = DateTime.tryParse('${item?['paid_on']}') ?? day ?? DateTime.now();
  List<Map<String, dynamic>>? patients;

  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(item == null ? tr('دخل حالة', 'Income from a case') : tr('تعديل الدخل', 'Edit income'),
                style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in incomeKinds)
                ChoiceChip(
                  label: Text('${incomeKindInfo(k).$1} ${incomeKindInfo(k).$2}'),
                  selected: kind == k,
                  onSelected: (_) => setS(() {
                    kind = k;
                    if (priceFor(k).isNotEmpty) amount.text = priceFor(k);
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: item == null && amount.text.isEmpty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              decoration: InputDecoration(labelText: tr('المبلغ', 'Amount'), suffixText: tr('ج.م', 'EGP')),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: name,
                  readOnly: pid != null,
                  decoration: InputDecoration(
                    labelText: tr('اسم الحالة', 'Patient name'),
                    prefixIcon: pid != null ? const Icon(Icons.verified_user_rounded, color: Tone.green) : null,
                    suffixIcon: pid != null
                        ? IconButton(onPressed: () => setS(() {
                              pid = null;
                              name.clear();
                            }), icon: const Icon(Icons.close))
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: tr('اختار من مرضاي', 'Pick from my patients'),
                onPressed: () async {
                  try {
                    patients ??= await rpcList('doctor_my_patients', {'p_doctor': actingDoctorId()});
                  } catch (_) {
                    patients = const [];
                  }
                  if (!c.mounted) return;
                  if (patients!.isEmpty) {
                    showMessage(c, tr('اكتب اسم الحالة بإيدك.', 'Type the patient name.'));
                    return;
                  }
                  final p = await showModalBottomSheet<Map<String, dynamic>>(
                    context: c,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (cc) => SafeArea(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(cc).size.height * 0.6),
                        child: ListView(shrinkWrap: true, children: [
                          for (final x in patients!)
                            ListTile(
                              leading: UserAvatar(url: x['avatar_url'] as String?, name: x['patient_name'] as String?, radius: 18),
                              title: Text(x['patient_name'] ?? ''),
                              subtitle: Text(displayPhone(x['phone'] as String?)),
                              onTap: () => Navigator.pop(cc, x),
                            ),
                        ]),
                      ),
                    ),
                  );
                  if (p != null) {
                    setS(() {
                      pid = p['patient_id'] as String;
                      name.text = p['patient_name'] as String? ?? '';
                    });
                  }
                },
                icon: const Icon(Icons.people_alt_rounded),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: note, maxLength: 300, decoration: InputDecoration(labelText: tr('ملاحظة', 'Note'))),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                final d = await showDatePicker(context: c, initialDate: date, firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setS(() => date = d);
              },
              icon: const Icon(Icons.event),
              label: Text('${tr('اليوم', 'Date')}: ${formatDate(date.toIso8601String())}'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Tone.green, minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                final v = num.tryParse(amount.text.trim().replaceAll(',', '.'));
                if (v == null || v <= 0) {
                  showMessage(c, tr('اكتب المبلغ', 'Enter the amount'), error: true);
                  return;
                }
                Navigator.pop(c, true);
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(tr('حفظ', 'Save')),
            ),
          ]),
        ),
      );
    }),
  );
  if (go != true || !context.mounted) return false;
  return runBusy(context, () async {
    await rpc('save_income', {
      'p_id': item?['id'],
      'p_kind': kind,
      'p_amount': num.parse(amount.text.trim().replaceAll(',', '.')),
      'p_on': _iso(date),
      'p_patient': pid,
      'p_patient_name': pid == null ? name.text.trim() : null,
      'p_note': note.text.trim(),
      'p_appointment': appointmentId,
      'p_doctor': actingDoctorId(),
    });
  }, success: tr('اتسجل في رصيدك ✓', 'Added to your balance ✓'));
}

Future<bool> expenseSheet(BuildContext context, {DateTime? day, Map<String, dynamic>? item}) async {
  var cat = item?['category'] as String? ?? 'supplies';
  final amount = TextEditingController(text: item != null ? '${_n(item['amount'])}' : '');
  final reason = TextEditingController(text: item?['reason'] as String?);
  var date = DateTime.tryParse('${item?['spent_on']}') ?? day ?? DateTime.now();
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(item == null ? tr('مصروف جديد', 'New expense') : tr('تعديل المصروف', 'Edit expense'),
                style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(tr('صرفت في إيه؟', 'What for?'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in expenseCategories)
                ChoiceChip(
                  label: Text('${expenseInfo(k).$1} ${expenseInfo(k).$2}'),
                  selected: cat == k,
                  onSelected: (_) => setS(() => cat = k),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: item == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              decoration: InputDecoration(labelText: tr('المبلغ', 'Amount'), suffixText: tr('ج.م', 'EGP')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              maxLength: 300,
              decoration: InputDecoration(labelText: tr('ليه؟ (السبب)', 'Why? (reason)'),
                  hintText: tr('مثلاً: شاش وقطن وسرنجات', 'e.g. gauze and syringes')),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                final d = await showDatePicker(context: c, initialDate: date, firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setS(() => date = d);
              },
              icon: const Icon(Icons.event),
              label: Text('${tr('اليوم', 'Date')}: ${formatDate(date.toIso8601String())}'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Tone.red, minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                final v = num.tryParse(amount.text.trim().replaceAll(',', '.'));
                if (v == null || v <= 0) {
                  showMessage(c, tr('اكتب المبلغ', 'Enter the amount'), error: true);
                  return;
                }
                Navigator.pop(c, true);
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(tr('حفظ', 'Save')),
            ),
          ]),
        ),
      );
    }),
  );
  if (go != true || !context.mounted) return false;
  return runBusy(context, () async {
    await rpc('save_expense', {
      'p_id': item?['id'],
      'p_category': cat,
      'p_amount': num.parse(amount.text.trim().replaceAll(',', '.')),
      'p_on': _iso(date),
      'p_reason': reason.text.trim(),
      'p_doctor': actingDoctorId(),
    });
  }, success: tr('اتخصم من رصيدك ✓', 'Expense recorded ✓'));
}

// ===========================================================================
// Year overview
// ===========================================================================
class FinanceYearScreen extends StatefulWidget {
  const FinanceYearScreen({super.key, required this.year});
  final int year;
  @override
  State<FinanceYearScreen> createState() => _FinanceYearScreenState();
}

class _FinanceYearScreenState extends State<FinanceYearScreen> {
  late int _year = widget.year;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${tr('حساب سنة', 'Year')} $_year'), actions: [
        IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
        IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right)),
      ]),
      body: FutureView<Map<String, dynamic>>(
        key: ValueKey(_year),
        load: () async => Map<String, dynamic>.from(await rpc('finance_year', {'p_year': _year, 'p_doctor': actingDoctorId()}) as Map),
        builder: (context, y, reload) {
          final months = (y['months'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final maxIn = months.fold<num>(1, (m, x) => _n(x['income']) > m ? _n(x['income']) : m);
          return RefreshList(onRefresh: reload, children: [
            _DayHeader(
              title: '${tr('إجمالي سنة', 'Total for')} $_year',
              income: _n(y['income']),
              expenses: _n(y['expenses']),
              net: _n(y['net']),
              cases: months.fold<int>(0, (s, m) => s + _n(m['entries']).toInt()),
            ),
            const SizedBox(height: 12),
            for (final m in months)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(monthName(_n(m['month']).toInt()), style: const TextStyle(fontWeight: FontWeight.w900))),
                      Text(money(_n(m['net'])),
                          style: TextStyle(fontWeight: FontWeight.w900, color: _n(m['net']) >= 0 ? darken(Tone.green, 0.2) : Tone.red)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: (_n(m['income']) / maxIn).clamp(0, 1).toDouble(), minHeight: 8,
                          color: Tone.green, backgroundColor: Tone.green.withValues(alpha: 0.1)),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: (_n(m['expenses']) / maxIn).clamp(0, 1).toDouble(), minHeight: 8,
                          color: Tone.red, backgroundColor: Tone.red.withValues(alpha: 0.1)),
                    ),
                    const SizedBox(height: 4),
                    Text('${tr('دخل', 'In')} ${money(_n(m['income']))} • ${tr('مصروفات', 'Out')} ${money(_n(m['expenses']))}',
                        style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ===========================================================================
// Default prices (filled automatically when recording income)
// ===========================================================================
class PriceListScreen extends StatefulWidget {
  const PriceListScreen({super.key});
  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends State<PriceListScreen> {
  final _ctrl = {for (final k in incomeKinds) k: TextEditingController()};
  late final Future<void> _loaded = _load();

  Future<void> _load() async {
    final row = await supa.from('doctors').select('price_list').eq('id', myId).single();
    final p = Map<String, dynamic>.from(row['price_list'] as Map? ?? const {});
    for (final k in incomeKinds) {
      if (p[k] != null) _ctrl[k]!.text = '${p[k]}';
    }
  }

  Future<void> _save() async {
    final prices = <String, num>{};
    for (final e in _ctrl.entries) {
      final v = num.tryParse(e.value.text.trim());
      if (v != null && v > 0) prices[e.key] = v;
    }
    final ok = await runBusy(context, () async {
      await rpc('set_price_list', {'p_prices': prices});
    }, success: tr('تم حفظ الأسعار ✓', 'Prices saved ✓'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('أسعار الكشف والخدمات', 'Prices'))),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          return ListView(padding: const EdgeInsets.all(16), children: [
            InfoBanner(icon: Icons.info_outline,
                text: tr('السعر هيتكتب لوحده لما تسجل دخل حالة، وتقدر تغيّره وقتها.',
                    'The price fills in automatically when you record income; you can still change it.')),
            const SizedBox(height: 12),
            for (final k in incomeKinds)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _ctrl[k],
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: '${incomeKindInfo(k).$1} ${incomeKindInfo(k).$2}',
                    suffixText: tr('ج.م', 'EGP'),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: Text(tr('حفظ', 'Save'))),
          ]);
        },
      ),
    );
  }
}
