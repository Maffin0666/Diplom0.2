import 'dart:io';

import 'package:flutter/material.dart';

import 'brand.dart';
import 'models.dart';

class LectureView extends StatelessWidget {
  const LectureView({
    super.key,
    required this.record,
    required this.position,
    required this.playing,
    required this.loading,
    required this.audioReady,
    required this.uploaded,
    required this.listening,
    required this.message,
    required this.error,
    required this.speed,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSeekTime,
    required this.onListen,
    required this.onRetry,
    required this.onReprocess,
    required this.onSpeed,
    required this.onBookmark,
  });

  final LectureRecord record;
  final Duration position;
  final bool playing, loading, audioReady, uploaded, listening;
  final String message, error;
  final double speed;
  final VoidCallback onPlayPause, onListen, onRetry, onReprocess, onBookmark;
  final ValueChanged<int> onSeek;
  final ValueChanged<Duration> onSeekTime;
  final ValueChanged<double> onSpeed;

  @override
  Widget build(BuildContext context) {
    final manifest = record.manifest;
    final chunks = manifest?.chunks ?? [];
    final current = manifest?.chunkAt(position) ?? -1;
    final selected =
        current >= 0 && current < chunks.length ? chunks[current] : null;
    final colors = Theme.of(context).colorScheme;
    final duration = manifest?.totalDuration ?? 0;
    final seconds = (position.inMilliseconds / 1000)
        .clamp(0, duration <= 0 ? 1 : duration)
        .toDouble();
    return Scaffold(
      appBar: AppBar(
        title: Text(audioReady ? record.title : 'Обработка снимка',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (audioReady)
            IconButton(
              tooltip: record.bookmarkIndex == current
                  ? 'Убрать закладку'
                  : 'Поставить закладку',
              onPressed: onBookmark,
              icon: Icon(record.bookmarkIndex == current
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: audioReady
              ? [
                  Text(_date(record.createdAt),
                      style: TextStyle(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  Container(
                    constraints: const BoxConstraints(minHeight: 210),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF303159)
                          : const Color(0xFFFFEDCC),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              selected?.isFormula == true
                                  ? 'ФОРМУЛА'
                                  : 'СЕЙЧАС ЗВУЧИТ',
                              style: TextStyle(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Brand.aqua
                                      : Brand.violet,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 14),
                          SelectableText(
                              selected?.text.isNotEmpty == true
                                  ? selected!.text
                                  : 'Фрагменты пока не получены',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.35)),
                          const SizedBox(height: 10),
                          Text(
                              chunks.isEmpty
                                  ? ''
                                  : 'Фрагмент ${current + 1} из ${chunks.length}',
                              style: TextStyle(color: colors.onSurfaceVariant)),
                        ]),
                  ),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const LectoriaMascot(size: 90, mood: MascotMood.speaking),
                    const SizedBox(width: 12),
                    Flexible(
                        child: Text(
                            playing
                                ? 'Лекция звучит'
                                : 'Готова к прослушиванию',
                            style: Theme.of(context).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 8),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                          child: Column(children: [
                            Semantics(
                              label: 'Позиция воспроизведения',
                              value:
                                  '${position.inSeconds} из ${duration.round()} секунд',
                              child: Slider(
                                value: seconds,
                                min: 0,
                                max: duration <= 0 ? 1 : duration,
                                onChanged: (value) => onSeekTime(Duration(
                                    milliseconds: (value * 1000).round())),
                              ),
                            ),
                            Row(children: [
                              Text(_time(position)),
                              const Spacer(),
                              Text(_time(Duration(seconds: duration.round())))
                            ]),
                            const SizedBox(height: 10),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton.filledTonal(
                                    tooltip: 'Предыдущий фрагмент',
                                    iconSize: 32,
                                    constraints: const BoxConstraints(
                                        minWidth: 60, minHeight: 60),
                                    onPressed: current > 0
                                        ? () => onSeek(current - 1)
                                        : null,
                                    icon:
                                        const Icon(Icons.skip_previous_rounded),
                                  ),
                                  IconButton.filled(
                                    tooltip:
                                        playing ? 'Пауза' : 'Воспроизвести',
                                    iconSize: 42,
                                    constraints: const BoxConstraints(
                                        minWidth: 76, minHeight: 76),
                                    style: IconButton.styleFrom(
                                        backgroundColor: Brand.gold,
                                        foregroundColor: Brand.indigo),
                                    onPressed: onPlayPause,
                                    icon: Icon(playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded),
                                  ),
                                  IconButton.filledTonal(
                                    tooltip: 'Следующий фрагмент',
                                    iconSize: 32,
                                    constraints: const BoxConstraints(
                                        minWidth: 60, minHeight: 60),
                                    onPressed: current + 1 < chunks.length
                                        ? () => onSeek(current + 1)
                                        : null,
                                    icon: const Icon(Icons.skip_next_rounded),
                                  ),
                                ]),
                            const SizedBox(height: 12),
                            Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  MenuAnchor(
                                    builder: (context, controller, child) =>
                                        OutlinedButton.icon(
                                      onPressed: () => controller.isOpen
                                          ? controller.close()
                                          : controller.open(),
                                      icon: const Icon(Icons.speed_rounded),
                                      label:
                                          Text('${speed.toStringAsFixed(1)}×'),
                                    ),
                                    menuChildren: [
                                      for (final value in [
                                        0.75,
                                        1.0,
                                        1.25,
                                        1.5,
                                        2.0
                                      ])
                                        MenuItemButton(
                                            onPressed: () => onSpeed(value),
                                            child: Text(
                                                '${value.toStringAsFixed(2)}×'))
                                    ],
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: onBookmark,
                                    icon: Icon(record.bookmarkIndex == current
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_outline_rounded),
                                    label: Text(record.bookmarkIndex == current
                                        ? 'Закладка здесь'
                                        : 'Закладка'),
                                  ),
                                ]),
                          ]))),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onListen,
                    icon: Icon(
                        listening ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: Brand.coral),
                    label: Text(
                        listening ? 'Завершить команду' : 'Голосовая команда'),
                  ),
                  const SizedBox(height: 5),
                  Text(
                      'Команды: воспроизвести, пауза, следующий, предыдущий, повтори формулу.',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _errorCard(context, error),
                  ],
                  if (record.bookmarkIndex != null &&
                      record.bookmarkIndex! < chunks.length &&
                      record.bookmarkIndex != current) ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () => onSeek(record.bookmarkIndex!),
                      icon: const Icon(Icons.bookmark_rounded),
                      label: Text(
                          'К закладке · фрагмент ${record.bookmarkIndex! + 1}'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Фрагменты · ${chunks.length}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  for (var i = 0; i < chunks.length; i++) ...[
                    _chunkTile(
                        context, chunks[i], i == current, () => onSeek(i)),
                    const SizedBox(height: 10),
                  ],
                  if (manifest?.fullText.isNotEmpty == true)
                    Card(
                        child: ExpansionTile(
                      title: const Text('Полный распознанный текст'),
                      leading: const Icon(Icons.article_outlined),
                      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                      children: [
                        Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(manifest!.fullText))
                      ],
                    )),
                  const SizedBox(height: 12),
                  _photo(context),
                ]
              : [
                  const SizedBox(height: 20),
                  const Center(
                      child: AnimatedLectoriaMascot(
                          size: 185, mood: MascotMood.thinking)),
                  const SizedBox(height: 18),
                  Text(
                      record.status == 'failed'
                          ? 'Не удалось обработать снимок'
                          : 'Готовим лекцию',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Semantics(
                      liveRegion: true,
                      child: Text(
                        error.isNotEmpty
                            ? error
                            : message.isEmpty
                                ? 'Проверяем состояние задачи'
                                : message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: error.isNotEmpty
                                ? colors.error
                                : colors.onSurfaceVariant),
                      )),
                  const SizedBox(height: 22),
                  if (loading) const LinearProgressIndicator(),
                  const SizedBox(height: 22),
                  _stage(context, Icons.image_search_rounded,
                      'Изображение отправлено', uploaded),
                  _stage(
                      context,
                      Icons.document_scanner_rounded,
                      'Распознавание текста и формул',
                      record.status == 'completed'),
                  _stage(context, Icons.record_voice_over_rounded,
                      'Озвучивание и сохранение аудио', audioReady),
                  const SizedBox(height: 22),
                  if (error.isNotEmpty && !loading)
                    FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Повторить подключение')),
                  if (record.status == 'failed') ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                        onPressed: onReprocess,
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Обработать снимок заново')),
                  ],
                  const SizedBox(height: 12),
                  _photo(context),
                ],
        ),
      ))),
    );
  }

  Widget _stage(BuildContext context, IconData icon, String label, bool done) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(children: [
                  Icon(done ? Icons.check_circle_rounded : icon,
                      color: done
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 13),
                  Expanded(
                      child: Text(label,
                          style: Theme.of(context).textTheme.bodyLarge)),
                ]))),
      );

  Widget _errorCard(BuildContext context, String value) => Semantics(
        liveRegion: true,
        child: Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(value,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer)),
            )),
      );

  Widget _chunkTile(BuildContext context, LectureChunk chunk, bool selected,
          VoidCallback onTap) =>
      Semantics(
        button: true,
        selected: selected,
        label: 'Фрагмент ${chunk.index + 1}. ${chunk.text}',
        child: Card(
          color:
              selected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(
                      chunk.isFormula
                          ? Icons.functions_rounded
                          : Icons.notes_rounded,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(chunk.text,
                          maxLines: 3, overflow: TextOverflow.ellipsis)),
                  if (selected) const Icon(Icons.graphic_eq_rounded),
                ])),
          ),
        ),
      );

  Widget _photo(BuildContext context) => Card(
          child: ExpansionTile(
        title: const Text('Исходный снимок'),
        leading: const Icon(Icons.image_outlined),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          Image.file(File(record.imagePath),
              height: 260,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Text('Снимок не удалось открыть'))
        ],
      ));
}

String _time(Duration time) =>
    '${time.inMinutes.remainder(60).toString().padLeft(2, '0')}:${time.inSeconds.remainder(60).toString().padLeft(2, '0')}';
String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
