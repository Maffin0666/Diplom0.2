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

enum MascotMood { welcome, idle, thinking, speaking, success }

/// A lightweight vector placeholder for the mascot; it needs no asset download.
class LectoriaMascot extends StatelessWidget {
  const LectoriaMascot(
      {super.key, this.size = 96, this.mood = MascotMood.idle});

  final double size;
  final MascotMood mood;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Лектория, помощница приложения',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _MascotPainter(mood, dark),
        ),
      ),
    );
  }
}

/// Slow, optional motion for non-interactive mascot illustrations.
class AnimatedLectoriaMascot extends StatefulWidget {
  const AnimatedLectoriaMascot({super.key, required this.size, required this.mood});

  final double size;
  final MascotMood mood;

  @override
  State<AnimatedLectoriaMascot> createState() => _AnimatedLectoriaMascotState();
}

class _AnimatedLectoriaMascotState extends State<AnimatedLectoriaMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: 1 + _controller.value * .025,
          child: child,
        ),
        child: LectoriaMascot(size: widget.size, mood: widget.mood),
      );
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter(this.mood, this.dark);

  final MascotMood mood;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final halo = Paint()
      ..color = (dark ? Brand.violet : Brand.gold).withValues(alpha: .16);
    canvas.drawCircle(const Offset(50, 49), 46, halo);
    final book = Paint()..color = Brand.cream;
    final cover = Paint()..color = Brand.orange;
    final line = Paint()
      ..color = Brand.indigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    final headphones = Paint()
      ..color = Brand.violet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        const Rect.fromLTWH(23, 13, 54, 65), 3.15, 3.15, false, headphones);
    canvas.drawRRect(RRect.fromLTRBR(17, 42, 29, 65, const Radius.circular(5)),
        Paint()..color = Brand.violet);
    canvas.drawRRect(RRect.fromLTRBR(71, 42, 83, 65, const Radius.circular(5)),
        Paint()..color = Brand.violet);
    final left = Path()
      ..moveTo(50, 38)
      ..quadraticBezierTo(40, 31, 25, 38)
      ..lineTo(25, 79)
      ..quadraticBezierTo(40, 71, 50, 81)
      ..close();
    final right = Path()
      ..moveTo(50, 38)
      ..quadraticBezierTo(60, 31, 75, 38)
      ..lineTo(75, 79)
      ..quadraticBezierTo(60, 71, 50, 81)
      ..close();
    canvas.drawPath(left, book);
    canvas.drawPath(right, book);
    canvas.drawPath(left, line);
    canvas.drawPath(right, line);
    canvas.drawLine(const Offset(50, 39), const Offset(50, 81), line);
    for (final x in [34.0, 61.0]) {
      canvas.drawCircle(Offset(x, 53), 2.6, Paint()..color = Brand.indigo);
    }
    canvas.drawArc(const Rect.fromLTWH(41, 52, 17, 12), .15, 2.8, false, line);
    canvas.drawPath(
        Path()
          ..moveTo(25, 77)
          ..quadraticBezierTo(39, 69, 50, 81)
          ..quadraticBezierTo(61, 69, 75, 77),
        Paint()
          ..color = Brand.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);
    if (mood == MascotMood.welcome || mood == MascotMood.success) {
      canvas.drawCircle(const Offset(83, 25), 4, cover);
      canvas.drawCircle(const Offset(91, 35), 2.5, Paint()..color = Brand.aqua);
    } else if (mood == MascotMood.speaking) {
      final wave = Paint()
        ..color = Brand.aqua
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawArc(const Rect.fromLTWH(77, 45, 13, 18), -1.0, 2, false, wave);
      canvas.drawArc(const Rect.fromLTWH(79, 38, 18, 32), -1.0, 2, false, wave);
    } else if (mood == MascotMood.thinking) {
      canvas.drawCircle(const Offset(86, 22), 4, cover);
      canvas.drawCircle(const Offset(81, 32), 2, cover);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) =>
      mood != oldDelegate.mood || dark != oldDelegate.dark;
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
