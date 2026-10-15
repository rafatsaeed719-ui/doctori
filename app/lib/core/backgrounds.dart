import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'look3d.dart';

/// Visual identity of a medical specialty: accent colour + themed emoji pattern.
class SpecialtyLook {
  const SpecialtyLook(this.accent, this.emojis);
  final Color accent;
  final List<String> emojis;
}

const _defaultDoctorLook = SpecialtyLook(Color(0xFF0E7C86), ['🩺', '💊', '🌡️', '❤️', '🏥']);

/// Matches by the English specialty name, so it keeps working if the admin reorders or adds specialties.
SpecialtyLook specialtyLook(String? specialtyEn) {
  final s = (specialtyEn ?? '').toLowerCase();
  bool has(String k) => s.contains(k);
  if (has('pediatric') || has('child')) return const SpecialtyLook(Color(0xFFEC5B92), ['🧸', '👶', '🍼', '⭐', '🎈', '🧩']);
  if (has('dent')) return const SpecialtyLook(Color(0xFF1E9BD7), ['🦷', '🪥', '✨', '😁', '🫧']);
  if (has('cardio') || has('heart')) return const SpecialtyLook(Color(0xFFE5484D), ['❤️', '🫀', '💓', '🩺', '📈']);
  if (has('dermat') || has('skin')) return const SpecialtyLook(Color(0xFFE58A5C), ['🧴', '✨', '🌸', '💆', '☀️']);
  if (has('gyn') || has('obstet')) return const SpecialtyLook(Color(0xFFD64D9A), ['🤰', '🌸', '👶', '💗', '🌷']);
  if (has('ortho') || has('bone')) return const SpecialtyLook(Color(0xFF4A6FA5), ['🦴', '🦵', '🏃', '💪', '🩻']);
  if (s == 'ent' || has('ear') || has('throat')) return const SpecialtyLook(Color(0xFF8E6CDB), ['👂', '👃', '👄', '🎧', '🗣️']);
  if (has('ophthal') || has('eye')) return const SpecialtyLook(Color(0xFF2E8BC0), ['👁️', '👓', '🔍', '✨', '🌈']);
  if (has('psychiat') || has('mental')) return const SpecialtyLook(Color(0xFF6A9C89), ['🧠', '🌿', '💭', '🕊️', '☀️']);
  if (has('neuro')) return const SpecialtyLook(Color(0xFF7B5CD6), ['🧠', '⚡', '💭', '🔬', '🧩']);
  if (has('urolog')) return const SpecialtyLook(Color(0xFF3A86C8), ['💧', '🩺', '🚰', '🫘']);
  if (has('nephro') || has('kidney')) return const SpecialtyLook(Color(0xFF2C7DA0), ['🫘', '💧', '🚰', '🩺']);
  if (has('pulmon') || has('chest') || has('lung')) return const SpecialtyLook(Color(0xFF3BA99C), ['🫁', '🌬️', '🍃', '🌳']);
  if (has('endocr') || has('diabet')) return const SpecialtyLook(Color(0xFFE07A2F), ['🩸', '🍎', '⚖️', '💉', '📊']);
  if (has('gastro') || has('hepat') || has('liver')) return const SpecialtyLook(Color(0xFF5B8C2A), ['🍏', '🥦', '🍵', '🥣']);
  if (has('oncol') || has('cancer')) return const SpecialtyLook(Color(0xFF8E44AD), ['🎗️', '💜', '🌱', '🌸']);
  if (has('rheum')) return const SpecialtyLook(Color(0xFFB5651D), ['🦴', '🤲', '🌡️', '🧘']);
  if (has('physical') || has('physio') || has('rehab')) return const SpecialtyLook(Color(0xFF16A085), ['🏃', '🧘', '💪', '🦵', '🤸']);
  if (has('nutrition') || has('diet')) return const SpecialtyLook(Color(0xFF4CAF50), ['🥗', '🍎', '🥑', '💧', '🥕']);
  if (has('surg')) return const SpecialtyLook(Color(0xFF2F7F7A), ['🩺', '🏥', '💉', '🩹']);
  if (has('family')) return const SpecialtyLook(Color(0xFF0E7C86), ['👨‍👩‍👧', '🏠', '❤️', '🩺']);
  return _defaultDoctorLook;
}

/// Calm, soothing look for patients: sky and mint with nature touches.
const patientLook = SpecialtyLook(Color(0xFF3A9BB5), ['🌿', '☁️', '🌸', '🍃', '☀️', '🕊️']);

/// Admin look: deep blue with dashboard symbols.
const adminLook = SpecialtyLook(Tone.indigo, ['📊', '⚙️', '🩺', '🛡️', '📈']);

/// Soft gradient + a faint, tilted emoji pattern drawn behind the content.
class PatternBackground extends StatelessWidget {
  const PatternBackground({super.key, required this.look, required this.child, this.calm = false});
  final SpecialtyLook look;
  final Widget child;
  final bool calm;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF101418) : Colors.white;
    final colors = calm
        ? (dark
            ? [const Color(0xFF0F2027), const Color(0xFF15302B)]
            : [const Color(0xFFE2F3F8), const Color(0xFFEAF7EE), const Color(0xFFFDF6EC)])
        : [Color.lerp(look.accent, base, dark ? 0.82 : 0.82)!, Color.lerp(look.accent, base, dark ? 0.9 : 0.95)!];
    return Stack(children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
          ),
        ),
      ),
      if (calm)
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _SoftBlobs(dark)))),
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _EmojiPattern(look.emojis, opacity: dark ? 0.10 : (calm ? 0.16 : 0.13))),
        ),
      ),
      child,
    ]);
  }
}

class _EmojiPattern extends CustomPainter {
  _EmojiPattern(this.emojis, {required this.opacity});
  final List<String> emojis;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (emojis.isEmpty) return;
    canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: opacity));
    const step = 92.0;
    var i = 0;
    for (var y = 24.0, row = 0; y < size.height + step; y += step, row++) {
      for (var x = (row.isOdd ? step / 2 : 0) + 12.0; x < size.width + step; x += step) {
        final e = emojis[(i * 7 + row * 3) % emojis.length];
        final tp = TextPainter(
          text: TextSpan(text: e, style: const TextStyle(fontSize: 30)),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(((i % 5) - 2) * 0.18);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
        i++;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EmojiPattern old) => old.emojis != emojis || old.opacity != opacity;
}

class _SoftBlobs extends CustomPainter {
  _SoftBlobs(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final blobs = [
      (const Offset(0.15, 0.08), 0.42, const Color(0xFFB9E4F2)),
      (const Offset(0.95, 0.30), 0.38, const Color(0xFFCDEFD9)),
      (const Offset(0.20, 0.75), 0.46, const Color(0xFFFCE7D2)),
    ];
    for (final (c, r, color) in blobs) {
      final center = Offset(c.dx * size.width, c.dy * size.height);
      final radius = r * math.max(size.width, 320);
      final paint = Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: dark ? 0.10 : 0.55),
          color.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoftBlobs old) => old.dark != dark;
}
