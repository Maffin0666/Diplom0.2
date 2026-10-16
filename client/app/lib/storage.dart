import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// All lecture data stays in the application's private documents directory.
class LectureStorage {
  LectureStorage(this.root);

  final Directory root;
  Future<void> _pendingWrite = Future<void>.value();
  late final File _index =
      File('${root.path}${Platform.pathSeparator}lectures.json');
  late final File _settings =
      File('${root.path}${Platform.pathSeparator}settings.json');

  static Future<LectureStorage> open() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}${Platform.pathSeparator}lectures');
    await root.create(recursive: true);
    return LectureStorage(root);
  }

  Future<List<LectureRecord>> readAll() async {
    final records =
        await _readRecoverable(_index, () => <LectureRecord>[], (body) {
      final data = jsonDecode(body);
      if (data is! List || data.any((item) => item is! Map<String, dynamic>)) {
        throw const FormatException('Повреждён список лекций');
      }
      return data
          .cast<Map<String, dynamic>>()
          .map(LectureRecord.fromJson)
          .toList();
    });
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  Future<void> saveAll(List<LectureRecord> records) =>
      _atomicWrite(_index, jsonEncode(records.map((r) => r.toJson()).toList()));

  Future<Map<String, dynamic>> readSettings() async {
    return _readRecoverable(_settings, () => <String, dynamic>{}, decodeObject);
  }

  Future<T> _readRecoverable<T>(
      File target, T Function() empty, T Function(String) parse) async {
    Object? originalError;
    if (await target.exists()) {
      try {
        return parse(await target.readAsString());
      } catch (error) {
        originalError = error;
      }
    }
    final backup = File('${target.path}.bak');
    final hasBackup = await backup.exists();
    if (hasBackup) {
      try {
        final value = parse(await backup.readAsString());
        await backup.copy(target.path);
        return value;
      } catch (_) {
        // Do not silently replace a corrupt index with an empty library.
      }
    }
    if (originalError != null || hasBackup) {
      throw const FormatException(
          'Не удалось открыть библиотеку. Проверьте сохранённые данные приложения.');
    }
    return empty();
  }

  Future<void> saveSettings(Map<String, dynamic> settings) =>
      _atomicWrite(_settings, jsonEncode(settings));

  Future<String> saveImage(String taskId, XFile image) async {
    if (await image.length() > 15 * 1024 * 1024) {
      throw const FormatException(
          'Снимок больше 15 МиБ. Выберите другое изображение');
    }
    final extension = image.name.split('.').last.toLowerCase();
    if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
      throw const FormatException('Выберите JPEG, PNG или WEBP');
    }
    final target =
        File('${root.path}${Platform.pathSeparator}$taskId.$extension');
    await File(image.path).copy(target.path);
    return target.path;
  }

  File audioFile(String taskId) =>
      File('${root.path}${Platform.pathSeparator}$taskId.mp3');

  /// New TTS revisions use distinct files so the previous recording survives.
  File correctedAudioFile(String taskId, String audioUrl) {
    final name = audioUrl.split('/').last;
    if (!RegExp(r'^lecture_[A-Za-z0-9_-]+\.mp3$').hasMatch(name)) {
      throw const FormatException('Неверное имя исправленной аудиозаписи');
    }
    return File('${root.path}${Platform.pathSeparator}${taskId}_$name');
  }

  /// Finds old audio revisions left after a transcript is corrected. The
  /// current audio for every saved lecture is always protected.
  Future<List<File>> unusedAudioFiles(List<LectureRecord> records) async {
    final active = records
        .where((record) => record.audioPath.isNotEmpty)
        .map((record) => File(record.audioPath).absolute.path.toLowerCase())
        .toSet();
    final taskIds =
        records.map((record) => record.taskId.toLowerCase()).toSet();
    final unused = <File>[];
    await for (final entry in root.list()) {
      final name = entry.uri.pathSegments.last.toLowerCase();
      final belongsToSavedLecture = taskIds.any((id) =>
          name == '$id.mp3' ||
          (name.startsWith('${id}_lecture_') && name.endsWith('.mp3')));
      if (entry is File &&
          belongsToSavedLecture &&
          !active.contains(entry.absolute.path.toLowerCase())) {
        unused.add(entry);
      }
    }
    return unused;
  }

  Future<int> unusedAudioBytes(List<LectureRecord> records) async {
    var total = 0;
    for (final file in await unusedAudioFiles(records)) {
      total += await file.length();
    }
    return total;
  }

  Future<int> clearUnusedAudio(List<LectureRecord> records) async {
    var freed = 0;
    for (final file in await unusedAudioFiles(records)) {
      freed += await file.length();
      await file.delete();
    }
    return freed;
  }

  Future<void> _atomicWrite(File target, String content) {
    final write = _pendingWrite.then((_) => _writeNow(target, content));
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeNow(File target, String content) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(content, flush: true);
    // On Windows rename cannot replace an existing file. Back up first so a
    // failed rename still leaves a readable copy.
    final backup = File('${target.path}.bak');
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
    }
    try {
      await temp.rename(target.path);
      // Keep the previous valid revision for recovery from later corruption.
    } catch (_) {
      if (await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }
}
