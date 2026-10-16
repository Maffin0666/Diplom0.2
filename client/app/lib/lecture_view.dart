import 'dart:io';

import 'package:flutter/material.dart';

import 'lektoria_sprite.dart';
import 'lyrics_player.dart';
import 'models.dart';
import 'visual_system.dart';
import 'user_error.dart';

/// Displays the synchronized transcript when audio is ready, or processing
/// progress while the original photo is being recognized and voiced.
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
    this.serverVoiceFallback = false,
    required this.message,
    required this.error,
    required this.speed,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSeekTime,
    required this.onListen,
    required this.onServerVoice,
    required this.onVoiceHelp,
    required this.onRetry,
    required this.onReprocess,
    required this.onSpeed,
    required this.onBookmark,
    required this.onEditTranscript,
    this.onExportText,
    this.onExportAudio,
    this.onExplainFormula,
    this.onOpenBookmarks,
    this.actionPose,
    this.scrollController,
  });

  final LectureRecord record;
  final ScrollController? scrollController;
  final Duration position;
  final bool playing, loading, audioReady, uploaded, listening;
  final bool serverVoiceFallback;
  final String message, error;
  final double speed;
  final VoidCallback onPlayPause, onListen, onRetry, onReprocess, onBookmark;
  final VoidCallback onServerVoice, onVoiceHelp, onEditTranscript;
  final VoidCallback? onExportText, onExportAudio;
  final ValueChanged<int>? onExplainFormula;
  final VoidCallback? onOpenBookmarks;
  final LectoriaPose? actionPose;
  final ValueChanged<int> onSeek;
  final ValueChanged<Duration> onSeekTime;
  final ValueChanged<double> onSpeed;

  @override
  Widget build(BuildContext context) {
    final pose = error.isNotEmpty
        ? LectoriaPose.criticalWarning
        : listening
            ? LectoriaPose.listening
            : actionPose ??
                (playing ? LectoriaPose.speaking : LectoriaPose.idle);
    if (audioReady) {
      return LyricsPlayer(
        record: record,
        position: position,
        playing: playing,
        loading: loading,
        speed: speed,
        onPlayPause: onPlayPause,
        onSeek: onSeek,
        onSeekTime: onSeekTime,
        onSpeed: onSpeed,
        onBookmark: onBookmark,
        onEditTranscript: onEditTranscript,
        onExportText: onExportText,
        onExportAudio: onExportAudio,
        onExplainFormula: onExplainFormula,
        onOpenBookmarks: onOpenBookmarks,
        scrollController: scrollController,
        pose: pose,
        message: message,
        error: error,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Обработка снимка')),
      body: EditorialBackdrop(
        child: SafeArea(
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              children: [
                Center(
                    child: AnimatedLectoriaSprite(
                  size: 175,
                  crop: SpriteCrop.full,
                  halo: true,
                  pose: pose == LectoriaPose.criticalWarning
                      ? pose
                      : LectoriaPose.thinking,
                )),
                const SizedBox(height: 16),
                Text(
                    record.status == 'failed'
                        ? 'Не удалось обработать снимок'
                        : 'Готовим лекцию',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                if (error.isNotEmpty)
                  ErrorNotice(message: error)
                else
                  Semantics(
                    liveRegion: true,
                    child: Text(
                        message.isEmpty
                            ? 'Проверяем состояние задачи'
                            : message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                const SizedBox(height: 22),
                if (loading) const LinearProgressIndicator(),
                const SizedBox(height: 18),
                _step(context, Icons.image_search_rounded,
                    'Изображение отправлено', uploaded),
                _step(
                    context,
                    Icons.document_scanner_rounded,
                    'Распознавание текста и формул',
                    record.status == 'completed'),
                _step(context, Icons.record_voice_over_rounded,
                    'Озвучивание и сохранение аудио', audioReady),
                if (error.isNotEmpty && !loading) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Повторить подключение')),
                ],
                if (record.status == 'failed') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                      onPressed: onReprocess,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Обработать снимок заново')),
                ],
                const SizedBox(height: 18),
                Card(
                    child: ExpansionTile(
                  title: const Text('Исходный снимок'),
                  leading: const Icon(Icons.image_outlined),
                  childrenPadding: const EdgeInsets.all(12),
                  children: [
                    SizedBox(
                        height: 260,
                        child: InteractiveViewer(
                            minScale: .5,
                            maxScale: 6,
                            child: Image.file(File(record.imagePath),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                    child: Text('Снимок не удалось открыть')))))
                  ],
                )),
              ],
            ),
          )),
        ),
      ),
    );
  }

  Widget _step(BuildContext context, IconData icon, String label, bool done) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
          child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(children: [
          Icon(done ? Icons.check_circle_rounded : icon,
              color: done ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
        ]),
      )),
    );
  }
}
