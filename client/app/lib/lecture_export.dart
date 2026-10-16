import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';

String transcriptForExport(LectureRecord record) {
  final chunks = record.manifest?.chunks ?? const <LectureChunk>[];
  return '${record.title}\n\n${chunks.map((chunk) => '${chunk.isFormula ? 'Формула: ' : ''}${chunk.text}').join('\n')}\n';
}

String timedTranscriptForExport(LectureRecord record) {
  final chunks = record.manifest?.chunks ?? const <LectureChunk>[];
  String stamp(double seconds) {
    final centiseconds = (seconds * 100).round();
    final minutes = centiseconds ~/ 6000;
    final wholeSeconds = centiseconds ~/ 100 % 60;
    final rest = centiseconds % 100;
    return '[${minutes.toString().padLeft(2, '0')}:${wholeSeconds.toString().padLeft(2, '0')}.${rest.toString().padLeft(2, '0')}]';
  }

  return '[ti:${record.title}]\n'
      '${chunks.map((chunk) => '${stamp(chunk.startTime)}${chunk.spokenText.isEmpty ? chunk.text : chunk.spokenText}').join('\n')}\n';
}

abstract final class LectureExport {
  static Future<void> text(LectureRecord record) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}lecture_${record.taskId}.txt');
    await file.writeAsString(transcriptForExport(record), flush: true);
    await SharePlus.instance.share(ShareParams(
      title: record.title,
      files: [XFile(file.path, mimeType: 'text/plain')],
    ));
  }

  /// MP3 and an LRC sidecar let compatible players display timed lines.
  static Future<void> audioWithTranscript(LectureRecord record) async {
    if (record.audioPath.isEmpty || !await File(record.audioPath).exists()) {
      throw const FileSystemException('Аудиозапись не сохранена');
    }
    final dir = await getTemporaryDirectory();
    final lrc = File(
        '${dir.path}${Platform.pathSeparator}lecture_${record.taskId}.lrc');
    await lrc.writeAsString(timedTranscriptForExport(record), flush: true);
    await SharePlus.instance.share(ShareParams(
      title: record.title,
      files: [
        XFile(record.audioPath, mimeType: 'audio/mpeg'),
        XFile(lrc.path, mimeType: 'text/plain'),
      ],
    ));
  }
}
