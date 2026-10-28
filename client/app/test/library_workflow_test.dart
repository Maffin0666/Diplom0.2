import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/library_backup.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/photo_line_preview.dart';
import 'package:lecture_reader/storage.dart';
import 'package:lecture_reader/voice_commands.dart';

void main() {
  test('review progress and page metadata survive storage round trip', () {
    final record = LectureRecord(
      taskId: '12345678-1234-1234-1234-123456789abc',
      serverBase: 'http://localhost:8000',
      imagePath: 'photo.jpg',
      createdAt: DateTime.utc(2026, 10, 19),
      seriesId: 'group-one',
      pageOrder: 2,
      reviewedChunkIds: ['line-1'],
      manifestJson: {
        'chunks': [
          {'id': 'line-1', 'index': 0, 'text': 'Первая строка', 'confidence': .2},
          {'id': 'line-2', 'index': 1, 'text': 'Вторая строка', 'confidence': .3},
        ],
      },
    );
    final restored = LectureRecord.fromJson(record.toJson());
    expect(restored.lectureId, 'group-one');
    expect(restored.pageOrder, 2);
    expect(restored.remainingReviewCount, 1);
  });

  test('photo tap picks the matching OCR line', () {
    final chunks = [
      const LectureChunk(id: 'a', index: 0, text: 'А', spokenText: 'А',
          isFormula: false, startTime: 0, endTime: 1, bbox: [10, 20, 80, 40]),
      const LectureChunk(id: 'b', index: 1, text: 'Б', spokenText: 'Б',
          isFormula: false, startTime: 1, endTime: 2, bbox: [10, 60, 80, 80]),
    ];
    expect(photoChunkAt(const Offset(45, 70), const Size(100, 100),
        const Size(100, 100), chunks, 100, 100), 1);
    expect(photoChunkAt(const Offset(99, 99), const Size(100, 100),
        const Size(100, 100), chunks, 100, 100), isNull);
  });

  test('voice commands for review and transcript search', () {
    expect(parseAppVoiceCommand('следующий сомнительный').command,
        AppCommand.nextUncertain);
    expect(parseAppVoiceCommand('фрагмент верен').command,
        AppCommand.confirmFragment);
    final search = parseAppVoiceCommand('найди интеграл');
    expect(search.command, AppCommand.searchLecture);
    expect(search.value, 'интеграл');
    expect(parseAppVoiceCommand('следующая страница').command,
        AppCommand.nextPage);
    expect(parseAppVoiceCommand('добавь страницу').command,
        AppCommand.addPage);
  });

  test('backup restores media, edits and bookmarks once', () async {
    final temp = await Directory.systemTemp.createTemp('lektoria-backup-test-');
    try {
      final source = LectureStorage(await Directory('${temp.path}/source').create());
      final target = LectureStorage(await Directory('${temp.path}/target').create());
      const id = '12345678-1234-1234-1234-123456789abc';
      final photo = File('${source.root.path}/$id.jpg');
      final audio = File('${source.root.path}/$id.mp3');
      await photo.writeAsBytes([1, 2, 3]);
      await audio.writeAsBytes([4, 5, 6]);
      final record = LectureRecord(
        taskId: id,
        serverBase: 'http://localhost:8000',
        imagePath: photo.path,
        audioPath: audio.path,
        createdAt: DateTime.utc(2026, 10, 19),
        customTitle: 'Исправленный конспект',
        reviewedChunkIds: ['line-1'],
        bookmarkedChunkIds: ['line-1'],
        manifestJson: {
          'chunks': [
            {'id': 'line-1', 'index': 0, 'text': 'Проверенный текст', 'confidence': .2},
          ],
        },
      );
      final zip = await LibraryBackup.create(source, [record], outputDirectory: temp);
      expect(await LibraryBackup.restore(target, [], zip.path), 1);
      final restored = await target.readAll();
      expect(restored.single.title, 'Исправленный конспект');
      expect(restored.single.reviewedChunkIds, ['line-1']);
      expect(restored.single.bookmarkedChunkIds, ['line-1']);
      expect(await File(restored.single.imagePath).readAsBytes(), [1, 2, 3]);
      expect(await LibraryBackup.restore(target, restored, zip.path), 0);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
