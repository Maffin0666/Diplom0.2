import 'package:flutter/material.dart';

/// Colours from the Лектория.Ai screen specification.
abstract final class Brand {
  static const indigo = Color(0xFF1A1B41);
  static const violet = Color(0xFF7B2CBF);
  static const aqua = Color(0xFF00E5FF);
  static const coral = Color(0xFFFF6B6B);
  static const orange = Color(0xFFFF8C42);
  static const gold = Color(0xFFFFB84D);
  static const cream = Color(0xFFFFF9F0);
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Лектория', style: TextStyle(color: color)),
        const TextSpan(text: '.', style: TextStyle(color: Brand.coral)),
        TextSpan(text: 'Ai', style: TextStyle(color: color)),
      ]),
      style: TextStyle(
          fontSize: large ? 32 : 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
