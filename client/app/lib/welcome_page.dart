import 'package:flutter/material.dart';
import 'app_haptics.dart';

import 'brand.dart';
import 'lektoria_sprite.dart';
import 'app_preferences.dart';
import 'visual_system.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage(
      {super.key, required this.onStart, required this.onSettings});

  final VoidCallback onStart;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final contrast = PreferencesScope.of(context).highContrast;
    final light = Theme.of(context).brightness == Brightness.light;
    final heroInk = contrast || light ? colors.onSurface : Colors.white;
    return Scaffold(
      body: EditorialBackdrop(
          child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 36),
              children: [
                const BrandWordmark(large: true),
                const SizedBox(height: 8),
                Text('ЛЕКЦИИ МОЖНО СЛУШАТЬ',
                    style: TextStyle(
                        color: colors.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1)),
                const SizedBox(height: 28),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: contrast ? colors.surface : null,
                    gradient: contrast
                        ? null
                        : LinearGradient(
                            colors: light
                                ? const [Color(0xFFE9F5F3), Color(0xFFEAE8FA)]
                                : const [Color(0xFF151A3F), Color(0xFF4B367E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                    border: Border.all(
                        color: contrast ? colors.outline : Brand.violet,
                        width: contrast ? 2 : 1),
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(34),
                        topRight: Radius.circular(34),
                        bottomRight: Radius.circular(34),
                        bottomLeft: Radius.circular(8)),
                  ),
                  child: Stack(children: [
                    const Positioned(
                        right: -32, top: 18, child: OrbitDecoration(size: 250)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionKicker('знакомьтесь, Лектория',
                                light: !contrast && !light),
                            const SizedBox(height: 15),
                            Text('Ваш конспект\nзазвучит',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(color: heroInk, height: 1.08)),
                            const SizedBox(height: 10),
                            Text(
                                'Снимите страницу, проверьте расшифровку и слушайте лекцию в своём темпе.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                        color: contrast || light
                                            ? heroInk
                                            : const Color(0xFFE4E9FA))),
                            const Align(
                              alignment: Alignment.centerRight,
                              child: AnimatedLectoriaSprite(
                                pose: LectoriaPose.greeting,
                                crop: SpriteCrop.full,
                                size: 188,
                              ),
                            ),
                          ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                const SectionKicker('три простых шага'),
                const SizedBox(height: 14),
                _benefit(
                    context,
                    '01',
                    Icons.camera_alt_outlined,
                    'Снимите страницу',
                    'Достаточно фотографии конспекта или доски.'),
                const SizedBox(height: 12),
                _benefit(
                    context,
                    '02',
                    Icons.edit_note_rounded,
                    'Проверьте текст',
                    'Поправьте ошибки распознавания перед озвучкой.'),
                const SizedBox(height: 12),
                _benefit(
                    context,
                    '03',
                    Icons.headphones_rounded,
                    'Слушайте лекцию',
                    'Переходите по фрагментам голосом или касанием.'),
                const SizedBox(height: 28),
                SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: () {
                      AppHaptics.vibrate();
                      onStart();
                    },
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Начать работу'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    AppHaptics.vibrate();
                    onSettings();
                  },
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Настроить приложение'),
                ),
              ],
            ),
          ),
        ),
      )),
    );
  }

  Widget _benefit(BuildContext context, String number, IconData icon,
      String title, String detail) {
    final colors = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4)),
        ),
        child: Icon(icon, color: colors.onSecondaryContainer),
      ),
      const SizedBox(width: 14),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$number / $title',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 3),
        Text(detail, style: TextStyle(color: colors.onSurfaceVariant)),
      ])),
    ]);
  }
}
