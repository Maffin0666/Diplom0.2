import 'package:flutter/material.dart';
import 'app_preferences.dart';

/// Available poses are centralized so screens select a state, not a file name.
enum LectoriaPose {
  idle,
  greeting,
  listening,
  thinking,
  speaking,
  success,
  question,
  hint,
  warning,
  criticalWarning,
  play,
  pause,
  next,
  previous,
  fastForward,
  rewind,
  volumeUp,
  volumeDown,
  mute,
  stop,
  repeat,
  repeatDotted,
  bookmark,
  close,
}

enum SpriteCrop { full, chest }

abstract final class LectoriaAssets {
  static const _root = 'assets/sprites/';

  static String pose(LectoriaPose pose, SpriteCrop crop) {
    final filename = switch (pose) {
      LectoriaPose.idle => crop == SpriteCrop.full
          ? 'lektoria_idle_full.png'
          : 'lektoria_idle_chest.png',
      LectoriaPose.greeting => crop == SpriteCrop.full
          ? 'lektoria_greeting_full.png'
          : 'lektoria_greeting_chest.png',
      LectoriaPose.listening => crop == SpriteCrop.full
          ? 'lektoria_listening_full.png'
          : 'lektoria_listening_chest.png',
      LectoriaPose.thinking => crop == SpriteCrop.full
          ? 'lektoria_thinking_full.png'
          : 'lektoria_thinking_chest.png',
      LectoriaPose.speaking => 'lektoria_speaking_chest.png',
      LectoriaPose.success => 'lektoria_success.png',
      LectoriaPose.question => 'lektoria_question.png',
      LectoriaPose.hint => 'lektoria_hint.png',
      LectoriaPose.warning => 'lektoria_warning_palm.png',
      LectoriaPose.criticalWarning => 'lektoria_warning_finger.png',
      LectoriaPose.play => 'lektoria_play.png',
      LectoriaPose.pause => 'lektoria_pause.png',
      LectoriaPose.next => 'lektoria_next.png',
      LectoriaPose.previous => 'lektoria_previous.png',
      LectoriaPose.fastForward => 'lektoria_fast_forward.png',
      LectoriaPose.rewind => 'lektoria_rewind.png',
      LectoriaPose.volumeUp => 'lektoria_volume_up.png',
      LectoriaPose.volumeDown => 'lektoria_volume_down.png',
      LectoriaPose.mute => 'lektoria_mute.png',
      LectoriaPose.stop => 'lektoria_stop.png',
      LectoriaPose.repeat => 'lektoria_repeat.png',
      LectoriaPose.repeatDotted => 'lektoria_repeat_dotted.png',
      LectoriaPose.bookmark => 'lektoria_bookmark.png',
      // Only lektoria_close.png was supplied, so both crops share it.
      LectoriaPose.close => 'lektoria_close.png',
    };
    return '$_root$filename';
  }

  static String label(LectoriaPose pose) => switch (pose) {
        LectoriaPose.idle => 'Лектория рядом',
        LectoriaPose.greeting => 'Лектория приветствует вас',
        LectoriaPose.listening => 'Лектория слушает команду',
        LectoriaPose.thinking => 'Лектория обрабатывает снимок',
        LectoriaPose.speaking => 'Лектория озвучивает лекцию',
        LectoriaPose.success => 'Лектория сообщает об успехе',
        LectoriaPose.question => 'Лектория просит уточнить команду',
        LectoriaPose.hint => 'Лектория подсказывает',
        LectoriaPose.warning => 'Лектория напоминает проверить снимок',
        LectoriaPose.criticalWarning => 'Лектория сообщает об ошибке',
        LectoriaPose.play => 'Лектория запускает воспроизведение',
        LectoriaPose.pause => 'Лектория ставит воспроизведение на паузу',
        LectoriaPose.next => 'Лектория переходит к следующему фрагменту',
        LectoriaPose.previous =>
          'Лектория возвращается к предыдущему фрагменту',
        LectoriaPose.fastForward => 'Лектория перематывает вперёд',
        LectoriaPose.rewind => 'Лектория перематывает назад',
        LectoriaPose.volumeUp => 'Лектория увеличивает громкость',
        LectoriaPose.volumeDown => 'Лектория уменьшает громкость',
        LectoriaPose.mute => 'Лектория выключает звук',
        LectoriaPose.stop => 'Лектория останавливает воспроизведение',
        LectoriaPose.repeat => 'Лектория повторяет фрагмент',
        LectoriaPose.repeatDotted => 'Лектория показывает жест повтора',
        LectoriaPose.bookmark => 'Лектория ставит закладку',
        LectoriaPose.close => 'Лектория закрывает окно',
      };
}

/// Decorative mascot poses are hidden from screen readers.
class LectoriaSprite extends StatelessWidget {
  const LectoriaSprite({
    super.key,
    required this.pose,
    required this.size,
    this.crop = SpriteCrop.chest,
  });

  final LectoriaPose pose;
  final double size;
  final SpriteCrop crop;

  @override
  Widget build(BuildContext context) => PreferencesScope.of(context).showMascot
      ? ExcludeSemantics(
          child: Image.asset(
            LectoriaAssets.pose(pose, crop),
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            gaplessPlayback: true,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
        )
      : const SizedBox.shrink();
}

/// Pose changes fade in. Only an active task gets a progress indicator.
class AnimatedLectoriaSprite extends StatelessWidget {
  const AnimatedLectoriaSprite({
    super.key,
    required this.pose,
    required this.size,
    this.crop = SpriteCrop.chest,
    this.halo = false,
  });

  final LectoriaPose pose;
  final double size;
  final SpriteCrop crop;
  final bool halo;

  @override
  Widget build(BuildContext context) {
    if (!PreferencesScope.of(context).showMascot) {
      return const SizedBox.shrink();
    }
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations == true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final busy = pose == LectoriaPose.thinking;
    final portrait = AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: LectoriaSprite(
        key: ValueKey((pose, crop)),
        pose: pose,
        size: size,
        crop: crop,
      ),
    );
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          if (halo)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  dark
                      ? const Color(0xFF7468B7).withValues(alpha: .48)
                      : const Color(0xFFDBB9FF).withValues(alpha: .7),
                  Colors.transparent,
                ]),
              ),
            ),
          portrait,
          if (busy)
            Positioned(
              right: 0,
              bottom: 0,
              child: ExcludeSemantics(
                child: SizedBox(
                  width: size * .21,
                  height: size * .21,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
