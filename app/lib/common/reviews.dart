import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

Widget starsRow(num value, {double size = 18}) => Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Icon(value >= i ? Icons.star_rounded : (value >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            color: Tone.amber, size: size),
    ]);

/// Asks the patient for 1–5 stars and a comment. Returns true when saved.
Future<bool> rateDoctorDialog(BuildContext context, String doctorId, {String? doctorName, int initial = 0, String? comment}) async {
  var stars = initial;
  final text = TextEditingController(text: comment);
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(doctorName == null ? tr('قيّم الدكتور', 'Rate the doctor') : '${tr('قيّم د.', 'Rate Dr.')} $doctorName'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i',
                onPressed: () => setS(() => stars = i),
                icon: Icon(stars >= i ? Icons.star_rounded : Icons.star_outline_rounded, color: Tone.amber, size: 36),
              ),
          ]),
          TextField(controller: text, maxLines: 3, maxLength: 600,
              decoration: InputDecoration(labelText: tr('رأيك (اختياري)', 'Your comment (optional)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: stars == 0 ? null : () => Navigator.pop(c, true), child: Text(tr('إرسال', 'Send'))),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return false;
  return runBusy(context, () async {
    await rpc('submit_review', {'p_doctor': doctorId, 'p_stars': stars, 'p_comment': text.text.trim()});
  }, success: tr('شكراً على تقييمك 💙', 'Thanks for your rating 💙'));
}

/// Rating summary + reviews (doctor page for patients; "my reviews" for the doctor with replies; admin can hide).
class ReviewsSection extends StatefulWidget {
  const ReviewsSection({super.key, required this.doctorId, this.doctorName});
  final String doctorId;
  final String? doctorName;
  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  int _key = 0;

  @override
  Widget build(BuildContext context) {
    final role = AppState.context['role'];
    final isOwner = myId == widget.doctorId;
    final isAdmin = role == 'admin';
    return FutureBuilder<dynamic>(
      key: ValueKey(_key),
      future: rpc('doctor_reviews_list', {'p_doctor': widget.doctorId}),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final r = Map<String, dynamic>.from(snap.data as Map);
        final items = (r['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final avg = (r['avg'] as num?) ?? 0;
        final count = (r['count'] as num?)?.toInt() ?? 0;
        final mine = r['mine'] as Map?;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(tr('التقييمات', 'Reviews')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Text(avg == 0 ? '—' : avg.toStringAsFixed(1), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    starsRow(avg, size: 22),
                    Text(tr('$count تقييم', '$count reviews')),
                  ]),
                ),
                if (role == 'patient' && r['can_review'] == true)
                  FilledButton.tonal(
                    onPressed: () async {
                      if (await rateDoctorDialog(context, widget.doctorId, doctorName: widget.doctorName,
                          initial: (mine?['stars'] as num?)?.toInt() ?? 0, comment: mine?['comment'] as String?)) {
                        setState(() => _key++);
                      }
                    },
                    child: Text(mine == null ? tr('قيّم', 'Rate') : tr('عدّل تقييمك', 'Edit rating')),
                  ),
              ]),
            ),
          ),
          for (final it in items.take(isOwner || isAdmin ? 100 : 10))
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(it['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800))),
                    starsRow((it['stars'] as num?) ?? 0, size: 16),
                  ]),
                  if ((it['comment'] as String?)?.isNotEmpty == true)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(it['comment'] as String)),
                  if ((it['reply'] as String?)?.isNotEmpty == true)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12)),
                      child: Text('${tr('رد الدكتور', 'Doctor’s reply')}: ${it['reply']}'),
                    ),
                  if (it['hidden'] == true) StatusChip(tr('مخفي', 'Hidden'), color: Colors.grey),
                  if (isOwner || isAdmin)
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (isOwner)
                        TextButton(
                          onPressed: () async {
                            final c = TextEditingController(text: it['reply'] as String?);
                            final go = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                                  title: Text(tr('رد على التقييم', 'Reply')),
                                  content: TextField(controller: c, maxLines: 3, maxLength: 600),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('إلغاء', 'Cancel'))),
                                    FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('حفظ', 'Save'))),
                                  ],
                                ));
                            if (go != true || !context.mounted) return;
                            if (await runBusy(context, () async => rpc('reply_review', {'p_id': it['id'], 'p_reply': c.text}))) {
                              setState(() => _key++);
                            }
                          },
                          child: Text(tr('رد', 'Reply')),
                        ),
                      if (isAdmin)
                        TextButton(
                          onPressed: () async {
                            if (await runBusy(context, () async =>
                                rpc('admin_hide_review', {'p_id': it['id'], 'p_hidden': it['hidden'] != true}))) {
                              setState(() => _key++);
                            }
                          },
                          child: Text(it['hidden'] == true ? tr('إظهار', 'Show') : tr('إخفاء', 'Hide')),
                        ),
                    ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('تقييماتي', 'My reviews'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [ReviewsSection(doctorId: myId)]),
      );
}
