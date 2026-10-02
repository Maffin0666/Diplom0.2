import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage(
      {super.key, required this.onStart, required this.onSettings});

  final VoidCallback onStart;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
              children: [
                const SizedBox(height: 28),
                const Center(
                    child: AnimatedLectoriaMascot(size: 220, mood: MascotMood.welcome)),
                const SizedBox(height: 28),
                const Center(child: BrandWordmark(large: true)),
                const SizedBox(height: 8),
                Text('Знания • Голос • Вдохновение',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: colors.onSurfaceVariant, fontSize: 16)),
                const SizedBox(height: 36),
                Text('Ваш конспект зазвучит',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                    'Сфотографируйте запись, слушайте её и переходите между фрагментами.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.4)),
                const SizedBox(height: 32),
                SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onStart();
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: Brand.orange,
                        foregroundColor: Brand.indigo),
                    icon: const Icon(Icons.graphic_eq_rounded),
                    label: const Text('Начать'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onSettings();
                  },
                  icon: const Icon(Icons.hearing_rounded),
                  label: const Text('Настройки доступности'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => showAboutDialog(
                    context: context,
                    applicationName: 'Лектория.Ai',
                    applicationVersion: '0.1',
                    children: const [
                      Text(
                          'Приложение превращает фотографии конспектов в текст и озвученные лекции.')
                    ],
                  ),
                  child: const Text('О приложении'),
                ),
                const SizedBox(height: 16),
                Text('Язык интерфейса: русский',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
