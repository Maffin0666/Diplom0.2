import 'package:flutter/material.dart';

import 'brand.dart';
import 'app_preferences.dart';
import 'lektoria_sprite.dart';

/// Shown while local lectures and preferences are restored.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: 'Лектория загружает ваши лекции',
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (!PreferencesScope.of(context).showMascot)
                  const SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                else
                  SizedBox(
                    width: 224,
                    height: 224,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox(
                        width: 215,
                        height: 215,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.primary,
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                        ),
                      ),
                      const AnimatedLectoriaSprite(
                        pose: LectoriaPose.greeting,
                        crop: SpriteCrop.full,
                        size: 190,
                        halo: true,
                      ),
                    ]),
                  ),
                const SizedBox(height: 22),
                const BrandWordmark(large: true),
                const SizedBox(height: 12),
                Text('Ваши лекции уже близко',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ),
      );
}
