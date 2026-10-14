import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

(String, Color) requestStatus(BuildContext context, String? s) => switch (s) {
      'pending' => (tr('بانتظار رد الطبيب', 'Waiting for doctor'), Colors.orange.shade800),
      'accepted' => (tr('مقبول', 'Accepted'), Colors.green.shade700),
      'rejected' => (tr('مرفوض', 'Declined'), Theme.of(context).colorScheme.error),
      'cancelled' => (tr('ملغى', 'Cancelled'), Theme.of(context).colorScheme.outline),
      _ => (s ?? '', Theme.of(context).colorScheme.outline),
    };

class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('طلبات الانضمام', 'Join requests'))),
      body: FutureView<List<Map<String, dynamic>>>(
        load: () => rpcList('patient_my_requests'),
        builder: (context, list, reload) => RefreshList(
          onRefresh: reload,
          children: list.isEmpty
              ? [EmptyView(icon: Icons.outbox_outlined, title: tr('لا توجد طلبات', 'No requests yet'))]
              : [
                  for (final r in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text('${tr('د.', 'Dr.')} ${r['doctor_name'] ?? ''}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              Builder(builder: (context) {
                                final (label, color) = requestStatus(context, r['status'] as String?);
                                return StatusChip(label, color: color);
                              }),
                            ]),
                            const SizedBox(height: 4),
                            Text(trField(r, 'specialty')),
                            Text('${tr('أُرسل', 'Sent')}: ${formatDate(r['created_at'] as String?)}',
                                style: Theme.of(context).textTheme.bodySmall),
                            if ((r['reject_reason'] as String?)?.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('${tr('السبب', 'Reason')}: ${r['reject_reason']}'),
                              ),
                            if (r['status'] == 'pending')
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton(
                                  onPressed: () async {
                                    final yes = await confirmDialog(context,
                                        title: tr('سحب الطلب؟', 'Withdraw request?'),
                                        body: tr('هيتم إلغاء طلب الانضمام لهذا الطبيب.', 'Your join request will be cancelled.'),
                                        confirm: tr('سحب الطلب', 'Withdraw'),
                                        danger: true);
                                    if (yes && context.mounted) {
                                      final ok = await runBusy(context, () async {
                                        await rpc('cancel_join_request', {'p_request': r['request_id']});
                                      });
                                      if (ok) reload();
                                    }
                                  },
                                  child: Text(tr('سحب الطلب', 'Withdraw')),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ),
                ],
        ),
      ),
    );
  }
}
