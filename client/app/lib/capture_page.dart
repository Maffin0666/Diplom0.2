import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

/// The native camera remains the actual viewfinder and capture surface.
/// This screen gives positioning guidance before opening it.
class CapturePage extends StatelessWidget {
  const CapturePage(
      {super.key, required this.onCamera, required this.onGallery});

  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Новая лекция')),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              AspectRatio(
                aspectRatio: 1.1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Brand.indigo, Color(0xFF44356D)]),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Stack(children: [
                    Positioned.fill(
                        child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: CustomPaint(painter: _GuidePainter()),
                    )),
                    const Align(
                        alignment: Alignment.center,
                        child: Icon(Icons.description_outlined,
                            color: Brand.cream, size: 82)),
                    const Positioned(
                        right: 8,
                        bottom: 8,
                        child:
                            LectoriaMascot(size: 95, mood: MascotMood.welcome)),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
              Text('Подготовьте страницу',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                  'Поместите конспект целиком в кадр, обеспечьте ровный свет и держите телефон неподвижно.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.45, color: colors.onSurfaceVariant)),
              const SizedBox(height: 20),
              SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      onCamera();
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: Brand.gold,
                        foregroundColor: Brand.indigo),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Открыть камеру'),
                  )),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Выбрать из галереи')),
              const SizedBox(height: 14),
              Text('Камера откроется в системном приложении телефона.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant)),
            ]),
      ))),
    );
  }
}

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Brand.aqua
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const length = 26.0;
    final path = Path()
      ..moveTo(0, length)
      ..lineTo(0, 0)
      ..lineTo(length, 0)
      ..moveTo(size.width - length, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, length)
      ..moveTo(0, size.height - length)
      ..lineTo(0, size.height)
      ..lineTo(length, size.height)
      ..moveTo(size.width - length, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, size.height - length);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
