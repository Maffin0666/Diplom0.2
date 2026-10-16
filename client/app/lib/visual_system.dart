import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'brand.dart';

/// A quiet ruled-page texture connects the camera, library and reader screens.
/// It is decorative only and disappears in high-contrast mode.
class EditorialBackdrop extends StatelessWidget {
  const EditorialBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (PreferencesScope.of(context).highContrast) return child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: _PageLinesPainter(
              line: scheme.primary.withValues(alpha: .055),
              accent: scheme.secondary.withValues(alpha: .10),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _PageLinesPainter extends CustomPainter {
  const _PageLinesPainter({required this.line, required this.accent});
  final Color line;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (double y = 28; y < size.height; y += 38) {
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), pen);
    }
    pen.color = accent;
    canvas.drawLine(const Offset(30, 0), Offset(30, size.height), pen);
    pen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(size.width + 36, 58), 96, pen);
    canvas.drawCircle(Offset(size.width + 36, 58), 134, pen);
  }

  @override
  bool shouldRepaint(covariant _PageLinesPainter oldDelegate) =>
      line != oldDelegate.line || accent != oldDelegate.accent;
}

class SectionKicker extends StatelessWidget {
  const SectionKicker(this.label, {super.key, this.light = false});
  final String label;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = light ? const Color(0xFFA8F5EC) : scheme.secondary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 19, height: 3, color: color),
      const SizedBox(width: 9),
      Flexible(
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    ]);
  }
}

class EditorialHeading extends StatelessWidget {
  const EditorialHeading({
    super.key,
    required this.kicker,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String kicker;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionKicker(kicker),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          subtitle!,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ]);
  }
}

class AccentPill extends StatelessWidget {
  const AccentPill({super.key, required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contrast = PreferencesScope.of(context).highContrast;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: contrast ? scheme.surface : scheme.secondaryContainer,
        border: Border.all(
          color: contrast
              ? scheme.outline
              : scheme.secondary.withValues(alpha: .4),
          width: contrast ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: scheme.onSecondaryContainer),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Decorative rings make the mascot feel part of a working audio studio.
class OrbitDecoration extends StatelessWidget {
  const OrbitDecoration({super.key, this.size = 180});
  final double size;

  @override
  Widget build(BuildContext context) {
    if (PreferencesScope.of(context).highContrast) {
      return SizedBox(width: size, height: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OrbitPainter()),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .53, size.height * .5);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Brand.aqua.withValues(alpha: .32);
    for (final factor in [.34, .43, .52]) {
      canvas.drawCircle(center, size.shortestSide * factor, pen);
    }
    pen
      ..style = PaintingStyle.fill
      ..color = Brand.coral;
    canvas.drawCircle(
        Offset(center.dx + size.width * .39, center.dy - size.height * .17),
        4,
        pen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
