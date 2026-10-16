import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'lektoria_sprite.dart';
import 'models.dart';
import 'photo_line_preview.dart';
import 'visual_system.dart';
import 'user_error.dart';

/// The server supplies chunk timestamps only. This gives a visual estimate
/// within a spoken text chunk; it never changes audio navigation or timing.
int? estimatedWordIndex(LectureChunk chunk, Duration position) {
  final seconds = position.inMilliseconds / 1000;
  if (chunk.isFormula ||
      chunk.endTime <= chunk.startTime ||
      seconds < chunk.startTime ||
      seconds > chunk.endTime) {
    return null;
  }
  final words = RegExp(r'\S+').allMatches(chunk.text).toList();
  if (words.isEmpty) return null;
  final total = words.fold<int>(0, (sum, word) => sum + word.group(0)!.length);
  final target =
      ((seconds - chunk.startTime) / (chunk.endTime - chunk.startTime) * total)
          .clamp(0, total);
  var elapsed = 0;
  for (var i = 0; i < words.length; i++) {
    elapsed += words[i].group(0)!.length;
    if (target < elapsed) return i;
  }
  return words.length - 1;
}

/// Sentence breaks improve scanning without claiming sentence-level timestamps.
String readableTranscriptText(String value) => value
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'(?<=[.!?]) +(?=[А-ЯЁA-Z])'), '\n')
    .trim();

/// A full transcript above a fixed transport dock. Rows remain tappable while
/// playback continues, like synchronized lyrics rather than a card carousel.
class LyricsPlayer extends StatefulWidget {
  const LyricsPlayer(
      {super.key,
      required this.record,
      required this.position,
      required this.playing,
      required this.loading,
      required this.speed,
      required this.onPlayPause,
      required this.onSeek,
      required this.onSeekTime,
      required this.onSpeed,
      required this.onBookmark,
      required this.onEditTranscript,
      this.onExportText,
      this.onExportAudio,
      this.onExplainFormula,
      this.onOpenBookmarks,
      this.scrollController,
      required this.pose,
      required this.message,
      required this.error});

  final LectureRecord record;
  final Duration position;
  final bool playing, loading;
  final double speed;
  final VoidCallback onPlayPause, onBookmark, onEditTranscript;
  final VoidCallback? onExportText, onExportAudio;
  final ValueChanged<int>? onExplainFormula;
  final VoidCallback? onOpenBookmarks;
  final ValueChanged<int> onSeek;
  final ValueChanged<Duration> onSeekTime;
  final ValueChanged<double> onSpeed;
  final ScrollController? scrollController;
  final LectoriaPose pose;
  final String message, error;

  @override
  State<LyricsPlayer> createState() => _LyricsPlayerState();
}

class _LyricsPlayerState extends State<LyricsPlayer> {
  final _ownScroll = ScrollController();
  late Future<ui.Image?> _photoFuture;
  late final ValueNotifier<int> _photoIndex;
  ui.Image? _decodedPhoto;
  final Map<String, GlobalKey> _rowKeys = {};
  final Map<int, DateTime> _touches = {};
  DateTime? _firstTwoFingerTap;
  bool _pairRegistered = false;
  ScrollController get _scroll => widget.scrollController ?? _ownScroll;

  @override
  void initState() {
    super.initState();
    _photoFuture = _loadPhoto();
    _photoIndex = ValueNotifier<int>(
        widget.record.manifest?.chunkAt(widget.position) ?? -1);
  }

  Future<ui.Image?> _loadPhoto() async {
    try {
      final bytes = await File(widget.record.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: 2048, allowUpscaling: false);
      try {
        final frame = await codec.getNextFrame();
        if (!mounted) {
          frame.image.dispose();
          return null;
        }
        _decodedPhoto = frame.image;
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  void _pointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    _touches[event.pointer] = now;
    if (_touches.length != 2 || _pairRegistered) return;
    final times = _touches.values.toList();
    if (times[0].difference(times[1]).inMilliseconds.abs() > 170) return;
    _pairRegistered = true;
    if (_firstTwoFingerTap != null &&
        now.difference(_firstTwoFingerTap!).inMilliseconds < 650) {
      _firstTwoFingerTap = null;
      widget.onPlayPause();
    } else {
      _firstTwoFingerTap = now;
    }
  }

  void _pointerEnd(PointerEvent event) {
    _touches.remove(event.pointer);
    if (_touches.isEmpty) _pairRegistered = false;
  }

  @override
  void didUpdateWidget(LyricsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.imagePath != widget.record.imagePath) {
      _decodedPhoto?.dispose();
      _decodedPhoto = null;
      _photoFuture = _loadPhoto();
    }
    final current = widget.record.manifest?.chunkAt(widget.position) ?? -1;
    if (_photoIndex.value != current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _photoIndex.value = current;
      });
    }
    final previous =
        oldWidget.record.manifest?.chunkAt(oldWidget.position) ?? -1;
    if (current != previous && current >= 0 && widget.playing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final chunks = widget.record.manifest?.chunks ?? [];
        if (current >= chunks.length) return;
        final target = _rowKeys[chunks[current].id]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(target,
              duration: PreferencesScope.of(context).reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: .32);
        }
      });
    }
  }

  @override
  void dispose() {
    _ownScroll.dispose();
    _photoIndex.dispose();
    _decodedPhoto?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manifest = widget.record.manifest;
    final chunks = manifest?.chunks ?? [];
    final current = manifest?.chunkAt(widget.position) ?? -1;
    final total = manifest?.totalDuration ?? 0.0;
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final narrowActions = MediaQuery.textScalerOf(context).scale(1) > 2.2;
    final position = (widget.position.inMilliseconds / 1000)
        .clamp(0, total <= 0 ? 1 : total)
        .toDouble();
    return Listener(
        onPointerDown: _pointerDown,
        onPointerUp: _pointerEnd,
        onPointerCancel: _pointerEnd,
        child: Scaffold(
          appBar: AppBar(
              title: Text(compact ? 'Лекция' : 'Студия лекции'),
              actions: [
                if (narrowActions)
                  PopupMenuButton<String>(
                    tooltip: 'Действия с лекцией',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (value) {
                      if (value == 'text') widget.onExportText?.call();
                      if (value == 'audio') widget.onExportAudio?.call();
                      if (value == 'edit') widget.onEditTranscript();
                      if (value == 'bookmarks') widget.onOpenBookmarks?.call();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'edit', child: Text('Исправить текст')),
                      PopupMenuItem(
                          value: 'bookmarks', child: Text('Закладки')),
                      PopupMenuItem(
                          value: 'text', child: Text('Поделиться текстом')),
                      PopupMenuItem(
                          value: 'audio', child: Text('Поделиться аудио')),
                    ],
                  ),
                if (!narrowActions) ...[
                  PopupMenuButton<String>(
                    tooltip: 'Экспорт лекции',
                    icon: const Icon(Icons.ios_share_rounded),
                    onSelected: (value) {
                      if (value == 'text') widget.onExportText?.call();
                      if (value == 'audio') widget.onExportAudio?.call();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'text', child: Text('Поделиться текстом')),
                      PopupMenuItem(
                          value: 'audio',
                          child: Text('Поделиться аудио и метками')),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Исправить расшифровку',
                    onPressed: widget.loading ? null : widget.onEditTranscript,
                    icon: const Icon(Icons.edit_note_rounded),
                  ),
                  IconButton(
                    tooltip: 'Открыть закладки',
                    onPressed: widget.onOpenBookmarks,
                    icon: const Icon(Icons.bookmarks_outlined),
                  ),
                ],
              ]),
          body: EditorialBackdrop(
              child: SafeArea(
                  child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, compact ? 6 : 12, 20, compact ? 7 : 13),
                  child: Row(children: [
                    AnimatedLectoriaSprite(
                        pose: widget.pose, size: compact ? 42 : 58),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          if (!compact) ...[
                            const SectionKicker('читайте вместе с Лекторией'),
                            const SizedBox(height: 5),
                          ],
                          Text(widget.record.title,
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge),
                        ])),
                    IconButton.outlined(
                      tooltip: 'Исходный снимок',
                      onPressed: () => _showPhoto(context, current),
                      icon: const Icon(Icons.image_outlined),
                    ),
                  ]),
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                Expanded(
                    child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity < -250 && current + 1 < chunks.length) {
                            widget.onSeek(current + 1);
                          } else if (velocity > 250 && current > 0) {
                            widget.onSeek(current - 1);
                          }
                        },
                        child: Scrollbar(
                          controller: _scroll,
                          child: SingleChildScrollView(
                            key: const ValueKey('lyrics_transcript_scroll'),
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                border:
                                    Border.all(color: scheme.outlineVariant),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(17, 14, 17, 11),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('ТЕКСТ ЛЕКЦИИ',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 1.1)),
                                        const SizedBox(height: 7),
                                        Wrap(
                                            spacing: 9,
                                            runSpacing: 5,
                                            children: [
                                              _legend(context, false),
                                              _legend(context, true),
                                            ]),
                                        const SizedBox(height: 5),
                                        Text(
                                            'Предложения разделены для чтения. Переход и подсветка слова приблизительны: сервер задаёт время для целого фрагмента.',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall),
                                      ]),
                                ),
                                Divider(
                                    height: 1, color: scheme.outlineVariant),
                                for (var i = 0; i < chunks.length; i++) ...[
                                  _line(context, chunks[i], i, i == current),
                                  if (i < chunks.length - 1 &&
                                      (chunks[i].isFormula ||
                                          chunks[i + 1].isFormula))
                                    Divider(
                                        height: 1,
                                        indent: 55,
                                        color: scheme.outlineVariant
                                            .withValues(alpha: .65)),
                                ],
                                if (chunks.isEmpty)
                                  const Padding(
                                      padding: EdgeInsets.all(20),
                                      child: Text(
                                          'В этой лекции пока нет фрагментов')),
                              ]),
                            ),
                          ),
                        ))),
                if (widget.error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: ErrorNotice(message: widget.error),
                  ),
                _transport(
                    context, current, chunks.length, total, position, compact),
              ]),
            ),
          ))),
        ));
  }

  Widget _line(
      BuildContext context, LectureChunk chunk, int index, bool active) {
    final scheme = Theme.of(context).colorScheme;
    final accent = chunk.isFormula ? scheme.tertiary : scheme.primary;
    final guide = PreferencesScope.of(context).readingGuide;
    return Container(
      key: _rowKeys.putIfAbsent(chunk.id, GlobalKey.new),
      child: Semantics(
        button: true,
        selected: active,
        label:
            '${chunk.isFormula ? 'Формула' : 'Текст'}, фрагмент ${index + 1}. ${chunk.text}',
        child: AnimatedContainer(
          duration: PreferencesScope.of(context).reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 240),
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: .15)
                : guide
                    ? scheme.surface.withValues(alpha: .65)
                    : Colors.transparent,
            border:
                Border(left: BorderSide(color: accent, width: active ? 6 : 3)),
          ),
          child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => widget.onSeek(index),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 10, 14, 10),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${index + 1}'.padLeft(2, '0'),
                            style: TextStyle(
                                color: accent, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 13),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (chunk.isFormula) ...[
                              Text('ФОРМУЛА',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: accent,
                                          fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                            ],
                            _chunkText(context, chunk, active, guide),
                          ],
                        )),
                        if (widget.record.hasBookmark(index)) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.bookmark_rounded,
                              size: 19, color: scheme.primary),
                        ],
                        if (active && chunk.bbox != null)
                          IconButton(
                            tooltip: 'Показать фрагмент ${index + 1} на фото',
                            onPressed: () => _showPhoto(context, index),
                            icon: const Icon(Icons.image_search_rounded),
                          ),
                        if (chunk.isFormula)
                          IconButton(
                            tooltip: 'Разобрать формулу ${index + 1}',
                            onPressed: widget.onExplainFormula == null
                                ? null
                                : () => widget.onExplainFormula!(index),
                            icon: const Icon(Icons.functions_rounded),
                          ),
                      ]),
                ),
              )),
        ),
      ),
    );
  }

  Widget _chunkText(
      BuildContext context, LectureChunk chunk, bool active, bool guide) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: guide && !active
              ? scheme.onSurface.withValues(alpha: .58)
              : scheme.onSurface,
          fontWeight: active ? FontWeight.w800 : null,
        );
    final wordIndex = active && widget.playing
        ? estimatedWordIndex(chunk, widget.position)
        : null;
    if (wordIndex == null) {
      return Text(readableTranscriptText(chunk.text), style: style);
    }
    final matches = RegExp(r'\S+').allMatches(chunk.text).toList();
    final spans = <TextSpan>[];
    var previous = 0;
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      if (previous < match.start) {
        final gap = chunk.text.substring(previous, match.start);
        final sentenceBreak = previous > 0 &&
            RegExp(r'[.!?]').hasMatch(chunk.text[previous - 1]) &&
            RegExp(r'[А-ЯЁA-Z]').hasMatch(chunk.text[match.start]);
        spans.add(TextSpan(text: sentenceBreak ? '\n' : gap));
      }
      spans.add(TextSpan(
          text: chunk.text.substring(match.start, match.end),
          style: i == wordIndex
              ? TextStyle(
                  backgroundColor: scheme.primary.withValues(alpha: .28),
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.primary,
                  decorationThickness: 2)
              : null));
      previous = match.end;
    }
    if (previous < chunk.text.length) {
      spans.add(TextSpan(text: chunk.text.substring(previous)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  Widget _legend(BuildContext context, bool formula) {
    final scheme = Theme.of(context).colorScheme;
    final color = formula ? scheme.tertiary : scheme.primary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(formula ? 'формула' : 'текст',
          style: Theme.of(context).textTheme.labelSmall),
    ]);
  }

  Widget _transport(BuildContext context, int current, int count, double total,
      double seconds, bool compact) {
    final scheme = Theme.of(context).colorScheme;
    final contrast = PreferencesScope.of(context).highContrast;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
            top: BorderSide(
          color: contrast ? scheme.outline : scheme.outlineVariant,
          width: contrast ? 2 : 1,
        )),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
                child: Text(
              count == 0
                  ? 'Нет фрагментов'
                  : 'Фрагмент ${current + 1} из $count',
              style: Theme.of(context).textTheme.titleMedium,
            )),
            if (compact)
              IconButton(
                tooltip: 'Открыть закладки',
                onPressed: widget.onOpenBookmarks,
                icon: const Icon(Icons.bookmarks_outlined),
              )
            else
              TextButton.icon(
                onPressed: widget.onOpenBookmarks,
                icon: const Icon(Icons.bookmarks_outlined),
                label: Text('Закладки ${widget.record.bookmarkIndexes.length}'),
              ),
          ]),
          Semantics(
            key: const ValueKey('player_transport'),
            label: 'Позиция воспроизведения',
            value: '${widget.position.inSeconds} из ${total.round()} секунд',
            child: Slider(
              value: seconds,
              min: 0,
              max: total <= 0 ? 1 : total,
              onChanged: (value) => widget
                  .onSeekTime(Duration(milliseconds: (value * 1000).round())),
            ),
          ),
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 16, children: [
            Text(_time(widget.position)),
            Text(_time(Duration(seconds: total.round()))),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton.outlined(
              tooltip: widget.record.hasBookmark(current)
                  ? 'Убрать закладку'
                  : 'Поставить закладку',
              onPressed: count == 0 ? null : widget.onBookmark,
              icon: Icon(widget.record.hasBookmark(current)
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded),
              constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
              padding: EdgeInsets.zero,
            ),
            IconButton.filledTonal(
              tooltip: 'Предыдущий фрагмент',
              onPressed: current > 0 ? () => widget.onSeek(current - 1) : null,
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 25,
              constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
              padding: EdgeInsets.zero,
            ),
            IconButton.filled(
              tooltip: widget.playing ? 'Пауза' : 'Воспроизвести',
              onPressed: widget.onPlayPause,
              icon: Icon(widget.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
              iconSize: 34,
              constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
              padding: EdgeInsets.zero,
            ),
            IconButton.filledTonal(
              tooltip: 'Следующий фрагмент',
              onPressed:
                  current + 1 < count ? () => widget.onSeek(current + 1) : null,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 25,
              constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
              padding: EdgeInsets.zero,
            ),
            SizedBox(
                width: 64,
                height: 64,
                child: PopupMenuButton<double>(
                  tooltip: 'Скорость воспроизведения',
                  icon: const Icon(Icons.speed_rounded),
                  iconSize: 23,
                  initialValue: widget.speed,
                  onSelected: widget.onSpeed,
                  itemBuilder: (_) => [
                    for (final speed in [
                      .75,
                      1.0,
                      1.25,
                      1.5,
                      1.75,
                      2.0,
                      2.25,
                      2.5,
                      2.75,
                      3.0
                    ])
                      PopupMenuItem(
                          value: speed,
                          child: Text('${speed.toStringAsFixed(2)}×')),
                  ],
                )),
          ]),
          if (widget.loading) const LinearProgressIndicator(),
          if (!compact && widget.message.isNotEmpty && widget.error.isEmpty)
            Text(widget.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }

  void _showPhoto(BuildContext context, int index) {
    _photoIndex.value = index;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(children: [
            ValueListenableBuilder<int>(
              valueListenable: _photoIndex,
              builder: (context, selected, _) {
                final manifest = widget.record.manifest;
                final chunk = manifest != null &&
                        selected >= 0 &&
                        selected < manifest.chunks.length
                    ? manifest.chunks[selected]
                    : null;
                return Column(children: [
                  Text(
                    chunk == null
                        ? 'Исходный снимок'
                        : 'Фрагмент ${selected + 1} на снимке',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (chunk != null) ...[
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Выделена область текущего фрагмента. '
                          'Если сервер объединил строки, показана вся область.'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: PhotoRegionOverview(
                        imageFuture: _photoFuture,
                        chunk: chunk,
                        originalWidth: manifest!.imageWidth ?? 0,
                        originalHeight: manifest.imageHeight ?? 0,
                      ),
                    ),
                  ],
                ]);
              },
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _photoIndex,
                builder: (context, selected, _) {
                  final manifest = widget.record.manifest;
                  final chunk = manifest != null &&
                          selected >= 0 &&
                          selected < manifest.chunks.length
                      ? manifest.chunks[selected]
                      : null;
                  final imageWidth = manifest?.imageWidth ?? 0;
                  final imageHeight = manifest?.imageHeight ?? 0;
                  if (chunk == null ||
                      chunk.bbox == null ||
                      imageWidth <= 0 ||
                      imageHeight <= 0) {
                    return InteractiveViewer(
                      minScale: .5,
                      maxScale: 6,
                      child: Image.file(
                        File(widget.record.imagePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Text('Снимок не удалось открыть')),
                      ),
                    );
                  }
                  final width = MediaQuery.sizeOf(context).width - 32;
                  return InteractiveViewer(
                    constrained: false,
                    minScale: .5,
                    maxScale: 6,
                    child: SizedBox(
                      width: width,
                      height: width * imageHeight / imageWidth,
                      child: PhotoRegionOverview(
                        imageFuture: _photoFuture,
                        chunk: chunk,
                        originalWidth: imageWidth,
                        originalHeight: imageHeight,
                        maxHeight: double.infinity,
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

String _time(Duration time) =>
    '${time.inMinutes.remainder(60).toString().padLeft(2, '0')}:${time.inSeconds.remainder(60).toString().padLeft(2, '0')}';
