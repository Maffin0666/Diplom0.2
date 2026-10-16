import 'package:flutter/material.dart';
import 'app_preferences.dart';
import 'brand.dart';
import 'lektoria_sprite.dart';
import 'models.dart';
import 'visual_system.dart';

/// The stage size depends on accessibility scale, never on fragment length.
/// Only the transcript scrolls; transport buttons keep their position.
class LectureStage extends StatefulWidget {
  const LectureStage(
      {super.key,
      required this.chunk,
      required this.index,
      required this.count,
      required this.pose,
      required this.playing});
  final LectureChunk? chunk;
  final int index, count;
  final LectoriaPose pose;
  final bool playing;
  @override
  State<LectureStage> createState() => _LectureStageState();
}

class _LectureStageState extends State<LectureStage> {
  final _scroll = ScrollController();
  @override
  void didUpdateWidget(LectureStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chunk?.id != widget.chunk?.id && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final contrast = PreferencesScope.of(context).highContrast;
    final light = Theme.of(context).brightness == Brightness.light;
    final ink = contrast || light ? colors.onSurface : Colors.white;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Container(
      key: const ValueKey('lecture_stage'),
      height: 244 + (scale - 1).clamp(0, 2) * 70,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: contrast ? colors.surface : null,
        gradient: contrast
            ? null
            : LinearGradient(
                colors: light
                    ? const [Color(0xFFF0F2FF), Color(0xFFDBF4EF)]
                    : const [Color(0xFF172044), Color(0xFF34366F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
        border: Border.all(
            color: contrast ? colors.outline : Brand.violet,
            width: contrast ? 2 : 1),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
            bottomRight: Radius.circular(30),
            bottomLeft: Radius.circular(8)),
      ),
      child: Stack(children: [
        if (!contrast)
          const Positioned(
              right: -48, top: -72, child: OrbitDecoration(size: 220)),
        Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 16, 10),
            child: Row(children: [
              LectoriaSprite(pose: widget.pose, size: 44),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionKicker(
                      widget.chunk?.isFormula == true
                          ? 'математическая запись'
                          : 'текущий фрагмент',
                      light: !contrast && !light),
                  const SizedBox(height: 3),
                  Text(
                      widget.playing
                          ? 'Лектория читает'
                          : 'Готово к прослушиванию',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: ink, fontWeight: FontWeight.w700)),
                ],
              )),
              Text(
                  '${(widget.index + 1).toString().padLeft(2, '0')} / '
                  '${widget.count.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: ink, fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
          ),
          Divider(height: 1, color: ink.withValues(alpha: .35)),
          Expanded(
              child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: const ValueKey('current_fragment_scroll'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(22, 17, 28, 17),
              child: Align(
                alignment: Alignment.topLeft,
                child: SelectableText(
                  widget.chunk?.text ?? 'Фрагменты пока не получены',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: ink, height: 1.42),
                ),
              ),
            ),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 12),
            child: Row(children: [
              Icon(
                  widget.playing
                      ? Icons.graphic_eq_rounded
                      : Icons.headphones_rounded,
                  size: 18,
                  color: ink),
              const SizedBox(width: 8),
              Expanded(
                  child: LinearProgressIndicator(
                value:
                    widget.count == 0 ? 0 : (widget.index + 1) / widget.count,
                minHeight: 4,
                backgroundColor: ink.withValues(alpha: .25),
                color: contrast ? colors.primary : Brand.aqua,
                borderRadius: BorderRadius.circular(4),
              )),
              const SizedBox(width: 10),
              Tooltip(
                  message: 'Длинный текст можно прокрутить внутри карточки',
                  child: Icon(Icons.unfold_more_rounded, color: ink, size: 20)),
            ]),
          ),
        ]),
      ]),
    );
  }
}
