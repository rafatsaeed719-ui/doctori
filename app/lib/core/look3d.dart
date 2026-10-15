import 'package:flutter/material.dart';

Color lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

/// Palette used for the 3D tiles (each action keeps its own colour everywhere).
class Tone {
  static const blue = Color(0xFF3D7BF4);
  static const teal = Color(0xFF14A3A3);
  static const green = Color(0xFF2DB37A);
  static const orange = Color(0xFFF59A2E);
  static const pink = Color(0xFFEC5B92);
  static const purple = Color(0xFF8B5CF6);
  static const indigo = Color(0xFF4F5BD5);
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFE9B320);
  static const sky = Color(0xFF38A8E0);
}

/// A glossy, raised "3D" icon: gradient body, top highlight, coloured drop shadow.
class Icon3D extends StatelessWidget {
  const Icon3D(this.icon, {super.key, required this.color, this.size = 56, this.emoji});
  final IconData? icon;
  final Color color;
  final double size;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final r = size * 0.3;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [lighten(color, 0.28), color, darken(color, 0.18)],
            stops: const [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(color: darken(color, 0.25).withValues(alpha: 0.45), blurRadius: size * 0.28, offset: Offset(0, size * 0.14)),
            BoxShadow(color: darken(color, 0.35).withValues(alpha: 0.35), blurRadius: 0, offset: Offset(0, size * 0.05)),
          ],
        ),
        child: Stack(children: [
          // glossy highlight on the upper half
          Positioned(
            top: size * 0.05,
            left: size * 0.1,
            right: size * 0.1,
            height: size * 0.45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(r * 0.85),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
          Center(
            child: emoji != null
                ? Text(emoji!, style: TextStyle(fontSize: size * 0.48, color: Colors.white, fontWeight: FontWeight.w900))
                : Icon(icon, color: Colors.white, size: size * 0.5, shadows: [
                    Shadow(color: darken(color, 0.45).withValues(alpha: 0.6), blurRadius: size * 0.08, offset: Offset(0, size * 0.04)),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// A big tappable tile with a 3D icon, a label, an optional count badge, and a press animation.
class Tile3D extends StatefulWidget {
  const Tile3D({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.subtitle,
    this.badge,
    this.onTap,
    this.emoji,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final int? badge;
  final VoidCallback? onTap;
  final String? emoji;

  @override
  State<Tile3D> createState() => _Tile3DState();
}

class _Tile3DState extends State<Tile3D> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          decoration: BoxDecoration(
            color: dark ? cs.surfaceContainerHigh : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: widget.color.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(color: widget.color.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon3D(widget.icon, color: widget.color, size: 58, emoji: widget.emoji),
              if ((widget.badge ?? 0) > 0)
                PositionedDirectional(
                  top: -6,
                  end: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Tone.red,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text('${widget.badge}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Text(widget.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 2),
              Text(widget.subtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Grid of tiles that adapts to the screen width (2 columns on phones, 3 on wide screens).
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 560 ? 3 : 2;
      const gap = 14.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in children) SizedBox(width: w, child: t)],
      );
    });
  }
}

/// Small 3D icon for the selected item of a bottom navigation bar.
Widget navIcon3D(IconData icon, Color color) => Icon3D(icon, color: color, size: 34);

/// A frosted card used for headers on top of patterned backgrounds.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: (dark ? Colors.black : Colors.white).withValues(alpha: dark ? 0.45 : 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.08 : 0.9)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }
}
