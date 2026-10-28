import 'package:flutter/material.dart';
import 'app_haptics.dart';

import 'lektoria_sprite.dart';
import 'app_preferences.dart';
import 'brand.dart';
import 'visual_system.dart';
import 'voice_commands.dart';
import 'voice_navigation.dart';

/// The native camera remains the actual viewfinder and capture surface.
/// This screen gives positioning guidance before opening it.
class CapturePage extends StatelessWidget {
  const CapturePage(
      {super.key,
      required this.onCamera,
      required this.onGallery,
      this.onSystemCamera});

  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback? onSystemCamera;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final contrast = PreferencesScope.of(context).highContrast;
    final previewInk = contrast ? colors.onSurface : Colors.white;
    return VoicePage(
      onCommand: (intent) async {
        if (intent.command == AppCommand.camera ||
            intent.command == AppCommand.capture) {
          onCamera();
          return true;
        }
        if (intent.command == AppCommand.gallery) {
          onGallery();
          return true;
        }
        return false;
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('Добавить лекцию')),
      body: EditorialBackdrop(
          child: SafeArea(
              child: Center(
                  child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            children: [
              const EditorialHeading(
                kicker: 'новая лекция / шаг 01',
                title: 'Покажите Лектории\nсвою запись',
                subtitle: 'Снимите конспект или выберите готовую фотографию.',
              ),
              const SizedBox(height: 24),
              Container(
                height: 234,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                    color: contrast ? colors.surface : const Color(0xFF172045),
                    border: Border.all(
                        color: contrast ? colors.outline : Brand.violet,
                        width: contrast ? 2 : 1),
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                        bottomLeft: Radius.circular(8))),
                child: Stack(children: [
                  Positioned.fill(
                      child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 19, 22, 19),
                    child: CustomPaint(
                        painter: _GuidePainter(
                            contrast ? colors.onSurface : Brand.aqua)),
                  )),
                  Positioned(
                    top: 23,
                    left: 42,
                    child: Text('СТРАНИЦА В КАДРЕ',
                        style: TextStyle(
                            color: previewInk,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                  ),
                  Positioned(
                    left: 42,
                    bottom: 28,
                    right: 100,
                    child: Text(
                        'Держите телефон ровно и оставьте поля вокруг текста.',
                        style: TextStyle(
                            color: previewInk,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3)),
                  ),
                  const Positioned(
                      right: 2,
                      bottom: 4,
                      child: AnimatedLectoriaSprite(
                          pose: LectoriaPose.hint, size: 104)),
                ]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (PreferencesScope.of(context).haptics) {
                        AppHaptics.vibrate();
                      }
                      onCamera();
                    },
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Открыть камеру'),
                  )),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Выбрать из галереи')),
              if (onSystemCamera != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onSystemCamera,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Снять системной камерой'),
                ),
              ],
              const SizedBox(height: 26),
              const SectionKicker('перед съёмкой'),
              const SizedBox(height: 8),
              Text('Три детали хорошего снимка',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _tip(context, Icons.crop_free_rounded, 'Вся страница в кадре'),
              _tip(context, Icons.wb_sunny_outlined,
                  'Ровный свет без бликов и теней'),
              _tip(context, Icons.center_focus_strong_rounded,
                  'Резкий снимок без движения'),
            ]),
      )))),
    ));
  }

  Widget _tip(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ]),
      );
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
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
    // A few ruled lines hint at handwriting without posing as detected text.
    paint
      ..color = color.withValues(alpha: .28)
      ..strokeWidth = 1;
    for (double y = 72; y < size.height - 44; y += 24) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
