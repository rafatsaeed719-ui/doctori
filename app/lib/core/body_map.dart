import 'package:flutter/material.dart';

import 'l10n.dart';
import 'specialty_templates.dart';

/// Tap where the problem is: a body figure (front / back), a teeth chart, or simple chips.
class RegionPicker extends StatelessWidget {
  const RegionPicker({super.key, required this.template, required this.selected, required this.onChanged, this.accent});
  final CaseTemplate template;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Color? accent;

  void _toggle(String k) {
    final s = {...selected};
    s.contains(k) ? s.remove(k) : s.add(k);
    onChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    return switch (template.map) {
      MapKind.body => BodyMap(selected: selected, onTap: _toggle, color: color),
      MapKind.teeth => TeethChart(selected: selected, onTap: _toggle, color: color),
      MapKind.chips => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in template.regionChips)
            FilterChip(label: Text(c.label), selected: selected.contains(c.key), onSelected: (_) => _toggle(c.key)),
        ]),
      MapKind.none => const SizedBox.shrink(),
    };
  }
}

/// Front and back figures side by side with tappable spots. Read-only when [onTap] is null.
class BodyMap extends StatelessWidget {
  const BodyMap({super.key, required this.selected, this.onTap, required this.color, this.height = 300});
  final Set<String> selected;
  final ValueChanged<String>? onTap;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      // Figures are drawn facing the viewer; keep them in a fixed left-to-right layout.
      textDirection: TextDirection.ltr,
      child: Row(children: [
        Expanded(child: _figure(context, back: false)),
        const SizedBox(width: 8),
        Expanded(child: _figure(context, back: true)),
      ]),
    );
  }

  Widget _figure(BuildContext context, {required bool back}) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Text(back ? tr('من الخلف', 'Back') : tr('من الأمام', 'Front'),
          style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
      const SizedBox(height: 4),
      SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          final regions = bodyRegions.where((r) => back ? r.back : r.front);
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _BodyPainter(cs.surfaceContainerHighest, cs.outlineVariant))),
            for (final r in regions)
              Positioned(
                // On the back view the patient's right side is on the viewer's right.
                left: (back ? 1 - r.x : r.x) * w - 15,
                top: r.y * h - 15,
                child: _Spot(
                  on: selected.contains(r.key),
                  color: color,
                  label: r.label,
                  onTap: onTap == null ? null : () => onTap!(r.key),
                ),
              ),
          ]);
        }),
      ),
    ]);
  }
}

class _Spot extends StatelessWidget {
  const _Spot({required this.on, required this.color, required this.label, this.onTap});
  final bool on;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: onTap != null,
        selected: on,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: on ? 24 : 16,
                height: on ? 24 : 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? color : Colors.white.withValues(alpha: 0.85),
                  border: Border.all(color: on ? Colors.white : color.withValues(alpha: 0.6), width: 2),
                  boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)] : null,
                ),
                child: on ? const Icon(Icons.close, size: 13, color: Colors.white) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter(this.fill, this.stroke);
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = fill;
    final line = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = s.width, h = s.height;
    final cx = w / 2;
    void both(Path path) {
      canvas.drawPath(path, p);
      canvas.drawPath(path, line);
    }

    RRect rr(double l, double t, double r, double b, double rad) =>
        RRect.fromLTRBR(l, t, r, b, Radius.circular(rad));
    // head
    both(Path()..addOval(Rect.fromCenter(center: Offset(cx, h * 0.06), width: w * 0.17, height: h * 0.095)));
    // neck
    both(Path()..addRect(Rect.fromLTRB(cx - w * 0.045, h * 0.10, cx + w * 0.045, h * 0.15)));
    // torso
    both(Path()..addRRect(rr(cx - w * 0.2, h * 0.15, cx + w * 0.2, h * 0.47, w * 0.08)));
    // arms
    for (final sgn in [-1.0, 1.0]) {
      final x0 = cx + sgn * w * 0.2;
      final arm = Path()
        ..moveTo(x0, h * 0.16)
        ..lineTo(x0 + sgn * w * 0.12, h * 0.33)
        ..lineTo(x0 + sgn * w * 0.15, h * 0.50)
        ..lineTo(x0 + sgn * w * 0.07, h * 0.50)
        ..lineTo(x0 + sgn * w * 0.04, h * 0.34)
        ..lineTo(x0, h * 0.27)
        ..close();
      both(arm);
      // legs
      final lx = cx + sgn * w * 0.1;
      both(Path()..addRRect(rr(lx - w * 0.085, h * 0.46, lx + w * 0.085, h * 0.92, w * 0.06)));
      both(Path()..addOval(Rect.fromCenter(center: Offset(lx + sgn * w * 0.01, h * 0.94), width: w * 0.16, height: h * 0.04)));
    }
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) => old.fill != fill || old.stroke != stroke;
}

/// FDI teeth chart: upper 18…11 | 21…28, lower 48…41 | 31…38.
class TeethChart extends StatelessWidget {
  const TeethChart({super.key, required this.selected, this.onTap, required this.color});
  final Set<String> selected;
  final ValueChanged<String>? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final upper = [for (var i = 8; i >= 1; i--) 10 + i, for (var i = 1; i <= 8; i++) 20 + i];
    final lower = [for (var i = 8; i >= 1; i--) 40 + i, for (var i = 1; i <= 8; i++) 30 + i];
    Widget row(List<int> teeth) => Row(children: [
          for (var i = 0; i < teeth.length; i++) ...[
            if (i == 8) Container(width: 2, height: 30, color: color.withValues(alpha: 0.4)),
            Expanded(child: _tooth(context, teeth[i])),
          ],
        ]);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Text(tr('الفك العلوي', 'Upper jaw'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        row(upper),
        const SizedBox(height: 10),
        row(lower),
        const SizedBox(height: 4),
        Text(tr('الفك السفلي', 'Lower jaw'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(tr('يمين المريض ←  → شمال المريض', 'Patient right ←  → patient left'), style: const TextStyle(fontSize: 11)),
      ]),
    );
  }

  Widget _tooth(BuildContext context, int n) {
    final on = selected.contains('tooth_$n');
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!('tooth_$n'),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? color : Colors.grey.shade400),
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : Colors.black87)),
          ),
        ),
      ),
    );
  }
}
