import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'lecture_timeline.dart';
import 'mp3_joiner.dart';

String transcriptForExport(LectureRecord record) {
  final chunks = record.manifest?.chunks ?? const <LectureChunk>[];
  return '${record.title}\n\n${chunks.map((chunk) => '${chunk.isFormula ? 'Формула: ' : ''}${chunk.text}').join('\n')}\n';
}

String timedTranscriptForExport(LectureRecord record) {
  final chunks = record.manifest?.chunks ?? const <LectureChunk>[];
  return '[ti:${record.title}]\n'
      '${chunks.map((chunk) => '${_stamp(chunk.startTime)}${chunk.spokenText.isEmpty ? chunk.text : chunk.spokenText}').join('\n')}\n';
}

String _stamp(double seconds) {
  final centiseconds = (seconds * 100).round();
  final minutes = centiseconds ~/ 6000;
  final wholeSeconds = centiseconds ~/ 100 % 60;
  final rest = centiseconds % 100;
  return '[${minutes.toString().padLeft(2, '0')}:${wholeSeconds.toString().padLeft(2, '0')}.${rest.toString().padLeft(2, '0')}]';
}

String fullTranscriptForExport(List<LectureRecord> records) {
  final pages = LectureTimeline(records).pages;
  if (pages.isEmpty) return '';
  if (pages.length == 1) return transcriptForExport(pages.first);
  return '${pages.first.title}\n\n${[
    for (var i = 0; i < pages.length; i++)
      'Страница ${i + 1}\n${(pages[i].manifest?.chunks ?? const <LectureChunk>[]).map((chunk) => '${chunk.isFormula ? 'Формула: ' : ''}${chunk.text}').join('\n')}',
  ].join('\n\n')}\n';
}

String fullTimedTranscriptForExport(
    List<LectureRecord> records, List<Duration> audioDurations) {
  final pages = LectureTimeline(records).pages;
  if (pages.length != audioDurations.length) {
    throw const FormatException('Не совпадает число страниц и аудиозаписей');
  }
  var offset = 0.0;
  final lines = <String>[
    '[ti:${pages.isEmpty ? 'Лекция' : pages.first.title}]'
  ];
  for (var i = 0; i < pages.length; i++) {
    final chunks = pages[i].manifest?.chunks ?? const <LectureChunk>[];
    for (final chunk in chunks) {
      lines.add(
          '${_stamp(offset + chunk.startTime)}${chunk.spokenText.isEmpty ? chunk.text : chunk.spokenText}');
    }
    offset += audioDurations[i].inMicroseconds / 1000000;
  }
  return '${lines.join('\n')}\n';
}

abstract final class LectureExport {
  static List<LectureRecord> _readyPages(List<LectureRecord> records) {
    final pages = LectureTimeline(records).pages;
    if (pages.isEmpty) throw const FormatException('В лекции нет страниц');
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].manifest?.status != 'completed') {
        throw FormatException('Дождитесь обработки страницы ${i + 1}');
      }
    }
    return pages;
  }

  static Future<void> text(List<LectureRecord> records) async {
    final pages = _readyPages(records);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}lecture_${pages.first.lectureId}.txt');
    await file.writeAsString(fullTranscriptForExport(pages), flush: true);
    await SharePlus.instance.share(ShareParams(
      title: pages.first.title,
      files: [XFile(file.path, mimeType: 'text/plain')],
    ));
  }

  /// MP3 and an LRC sidecar let compatible players display timed lines.
  static Future<void> audioWithTranscript(List<LectureRecord> records) async {
    final pages = _readyPages(records);
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].audioPath.isEmpty ||
          !await File(pages[i].audioPath).exists()) {
        throw FileSystemException('Аудио страницы ${i + 1} ещё не сохранено');
      }
    }
    final dir = await getTemporaryDirectory();
    final audio = pages.length == 1
        ? File(pages.first.audioPath)
        : File(
            '${dir.path}${Platform.pathSeparator}lecture_${pages.first.lectureId}_full.mp3');
    final durations = pages.length == 1
        ? [
            Duration(
                milliseconds:
                    ((pages.first.manifest?.totalDuration ?? 0) * 1000).round())
          ]
        : await Mp3Joiner.join(
            [for (final page in pages) File(page.audioPath)], audio);
    final lrc = File(
        '${dir.path}${Platform.pathSeparator}lecture_${pages.first.lectureId}.lrc');
    await lrc.writeAsString(fullTimedTranscriptForExport(pages, durations),
        flush: true);
    await SharePlus.instance.share(ShareParams(
      title: pages.first.title,
      files: [
        XFile(audio.path, mimeType: 'audio/mpeg'),
        XFile(lrc.path, mimeType: 'text/plain'),
      ],
    ));
  }
}
