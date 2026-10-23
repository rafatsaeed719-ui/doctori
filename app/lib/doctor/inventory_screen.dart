import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

String _q(num? v) {
  if (v == null) return '0';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

String moveReason(String? r) => switch (r) {
      'purchase' => tr('شراء', 'Purchase'),
      'use' => tr('استخدام', 'Used'),
      'expired' => tr('منتهي الصلاحية', 'Expired'),
      'return' => tr('مرتجع', 'Returned'),
      _ => tr('تعديل جرد', 'Adjustment'),
    };

/// Clinic stock: items, quantities, low-stock alerts, in/out moves (a purchase can be added to expenses).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  int _key = 0;
  String _search = '';

  void _reload() => setState(() => _key++);

  Future<void> _editItem([Map<String, dynamic>? item]) async {
    final name = TextEditingController(text: item?['name'] as String?);
    final category = TextEditingController(text: item?['category'] as String?);
    final unit = TextEditingController(text: item?['unit'] as String?);
    final minQty = TextEditingController(text: item == null ? '5' : _q(item['min_qty'] as num?));
    final cost = TextEditingController(text: item?['unit_cost'] == null ? '' : _q(item!['unit_cost'] as num?));
    final initial = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(item == null ? tr('صنف جديد', 'New item') : tr('تعديل الصنف', 'Edit item'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: InputDecoration(labelText: tr('اسم الصنف', 'Item name'),
                hintText: tr('مثلاً: جوانتي، شاش، بنج موضعي', 'e.g. gloves, gauze'))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: category, decoration: InputDecoration(labelText: tr('القسم', 'Category')))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: unit, decoration: InputDecoration(labelText: tr('الوحدة', 'Unit'),
                  hintText: tr('علبة / قطعة', 'box / piece')))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: minQty, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: tr('نبهني لما يوصل', 'Alert at')))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: cost, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: tr('سعر الوحدة', 'Unit cost'), suffixText: tr('ج.م', 'EGP')))),
            ]),
            if (item == null) ...[
              const SizedBox(height: 10),
              TextField(controller: initial, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: tr('الكمية الموجودة دلوقتي', 'Quantity on hand'))),
            ],
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ', 'Save'))),
          ]),
        ),
      ),
    );
    if (go != true || !mounted || name.text.trim().isEmpty) return;
    final ok = await runBusy(context, () async {
      await rpc('save_inventory_item', {
        'p_id': item?['id'],
        'p_name': name.text.trim(),
        'p_category': category.text.trim(),
        'p_unit': unit.text.trim(),
        'p_min_qty': num.tryParse(minQty.text.trim()) ?? 0,
        'p_unit_cost': num.tryParse(cost.text.trim()),
        'p_initial_qty': num.tryParse(initial.text.trim()) ?? 0,
        'p_doctor': actingDoctorId(),
      });
    }, success: tr('تم الحفظ ✓', 'Saved ✓'));
    if (ok) _reload();
  }

  Future<void> _move(Map<String, dynamic> item, bool incoming) async {
    final qty = TextEditingController();
    final cost = TextEditingController();
    final note = TextEditingController();
    var reason = incoming ? 'purchase' : 'use';
    var addExpense = can('finance');
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, setS) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${incoming ? tr('إضافة للمخزن', 'Stock in') : tr('صرف من المخزن', 'Stock out')}: ${item['name']}',
                    style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, children: [
                  for (final r in incoming ? ['purchase', 'return', 'adjust'] : ['use', 'expired', 'adjust'])
                    ChoiceChip(label: Text(moveReason(r)), selected: reason == r, onSelected: (_) => setS(() => reason = r)),
                ]),
                const SizedBox(height: 10),
                TextField(controller: qty, autofocus: true, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    decoration: InputDecoration(labelText: tr('الكمية', 'Quantity'), suffixText: item['unit'] as String?)),
                if (incoming && reason == 'purchase') ...[
                  const SizedBox(height: 10),
                  TextField(controller: cost, keyboardType: TextInputType.number, textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: tr('اتدفع كام إجمالي؟', 'Total paid'), suffixText: tr('ج.م', 'EGP'))),
                  if (can('finance'))
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: addExpense,
                      onChanged: (v) => setS(() => addExpense = v),
                      title: Text(tr('سجّلها في المصروفات', 'Add to expenses')),
                    ),
                ],
                TextField(controller: note, decoration: InputDecoration(labelText: tr('ملاحظة', 'Note'))),
                const SizedBox(height: 14),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('حفظ', 'Save'))),
              ]),
            ),
          )),
    );
    final n = num.tryParse(qty.text.trim());
    if (go != true || !mounted || n == null || n <= 0) return;
    final ok = await runBusy(context, () async {
      await rpc('inventory_move', {
        'p_item': item['id'],
        'p_delta': incoming ? n : -n,
        'p_reason': reason,
        'p_note': note.text.trim(),
        'p_cost': num.tryParse(cost.text.trim()),
        'p_record_expense': addExpense,
      });
    }, success: tr('تم ✓', 'Done ✓'));
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('مخزن العيادة', 'Clinic stock'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editItem(),
        icon: const Icon(Icons.add_box_rounded),
        label: Text(tr('صنف جديد', 'New item')),
      ),
      body: FutureView<List<Map<String, dynamic>>>(
        key: ValueKey(_key),
        load: () => rpcList('list_inventory', {'p_doctor': actingDoctorId()}),
        builder: (context, all, reload) {
          final list = all.where((i) => _search.isEmpty || '${i['name']} ${i['category'] ?? ''}'.contains(_search)).toList();
          final low = all.where((i) => i['low'] == true).length;
          return RefreshList(onRefresh: reload, children: [
            if (low > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InfoBanner(icon: Icons.warning_amber_rounded, color: Tone.red,
                    text: tr('$low صنف قرب يخلص — اطلبهم قبل ما يخلصوا.', '$low items are running low.')),
              ),
            TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('دوّر على صنف', 'Search items')),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
            const SizedBox(height: 12),
            if (all.isEmpty)
              EmptyView(icon: Icons.inventory_2_rounded, title: tr('المخزن فاضي', 'No items yet'),
                  subtitle: tr('ضيف المستلزمات اللي بتستخدمها في العيادة وكمياتها.', 'Add the supplies you use and their quantities.')),
            for (final i in list)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  leading: Icon3D(Icons.inventory_2_rounded, color: i['low'] == true ? Tone.red : Tone.teal, size: 42),
                  title: Text(i['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${tr('الموجود', 'On hand')}: ${_q(i['qty'] as num?)} ${i['unit'] ?? ''}'
                      '${i['category'] != null ? ' • ${i['category']}' : ''}'),
                  trailing: i['low'] == true ? StatusChip(tr('قرب يخلص', 'Low'), color: Tone.red) : null,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    Row(children: [
                      Expanded(child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Tone.green),
                          onPressed: () => _move(i, true), icon: const Icon(Icons.add), label: Text(tr('إضافة', 'In')))),
                      const SizedBox(width: 8),
                      Expanded(child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Tone.orange),
                          onPressed: () => _move(i, false), icon: const Icon(Icons.remove), label: Text(tr('صرف', 'Out')))),
                      IconButton(onPressed: () => _editItem(i), icon: const Icon(Icons.edit_outlined)),
                      IconButton(
                        onPressed: () async {
                          final yes = await confirmDialog(context, title: tr('حذف الصنف؟', 'Delete item?'), body: '${i['name']}',
                              confirm: tr('حذف', 'Delete'), danger: true);
                          if (!yes || !context.mounted) return;
                          if (await runBusy(context, () async => rpc('delete_inventory_item', {'p_id': i['id']}))) _reload();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text('${tr('ينبهك عند', 'Alert at')} ${_q(i['min_qty'] as num?)}'
                          '${i['unit_cost'] != null ? ' • ${tr('سعر الوحدة', 'Unit cost')} ${_q(i['unit_cost'] as num?)} ${tr('ج.م', 'EGP')}' : ''}',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                    for (final m in (i['moves'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon((m['delta'] as num) > 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                            color: (m['delta'] as num) > 0 ? Tone.green : Tone.orange),
                        title: Text('${(m['delta'] as num) > 0 ? '+' : ''}${_q(m['delta'] as num?)} — ${moveReason(m['reason'] as String?)}'),
                        subtitle: Text([formatDate(m['at'] as String?), m['by'], m['note']].whereType<String>()
                            .where((s) => s.isNotEmpty).join(' • ')),
                      ),
                  ],
                ),
              ),
          ]);
        },
      ),
    );
  }
}
