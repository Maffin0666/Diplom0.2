import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'storage.dart';

/// A portable ZIP with only library metadata and files owned by this app.
/// Server addresses and accessibility preferences stay on the current phone.
abstract final class LibraryBackup {
  static const _maxEntryBytes = 150 * 1024 * 1024;
  static const _maxTotalBytes = 2 * 1024 * 1024 * 1024;
  static const _mediaName = r'^media/[A-Za-z0-9_.-]+$';

  static String _archivePath(String path, LectureStorage storage) {
    final file = File(path);
    final root = storage.root.absolute.path.replaceAll('\\', '/').toLowerCase();
    final actual = file.absolute.path.replaceAll('\\', '/').toLowerCase();
    if (!actual.startsWith('$root/')) {
      throw const FormatException('Файл лекции находится вне хранилища приложения');
    }
    final name = file.uri.pathSegments.last;
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name)) {
      throw const FormatException('Неверное имя файла лекции');
    }
    return 'media/$name';
  }

  static Future<File> create(
      LectureStorage storage, List<LectureRecord> records,
      {Directory? outputDirectory}) async {
    if (records.isEmpty) {
      throw const FormatException('В библиотеке пока нет лекций для сохранения');
    }
    final files = <String, File>{};
    final data = <Map<String, dynamic>>[];
    for (final record in records) {
      final json = Map<String, dynamic>.from(record.toJson());
      for (final key in ['image_path', 'audio_path']) {
        final path = json[key] as String? ?? '';
        if (path.isEmpty) continue;
        final name = _archivePath(path, storage);
        final file = File(path);
        if (!await file.exists()) {
          throw FormatException('Не найден файл для лекции «${record.title}»');
        }
        files[name] = file;
        json[key] = name;
      }
      data.add(json);
    }
    final temp = outputDirectory ?? await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final zipFile = File('${temp.path}${Platform.pathSeparator}lektoria-$stamp.zip');
    final metadata = File('${temp.path}${Platform.pathSeparator}lektoria-index-$stamp.json');
    await metadata.writeAsString(jsonEncode({'version': 1, 'records': data}), flush: true);
    final encoder = ZipFileEncoder();
    try {
      encoder.create(zipFile.path);
      await encoder.addFile(metadata, 'library.json');
      for (final entry in files.entries) {
        await encoder.addFile(entry.value, entry.key, ZipFileEncoder.STORE);
      }
      await encoder.close();
      return zipFile;
    } catch (_) {
      try { await encoder.close(); } catch (_) {}
      rethrow;
    } finally {
      if (await metadata.exists()) await metadata.delete();
    }
  }

  /// Merges new task IDs. Existing lectures never get overwritten.
  static Future<int> restore(LectureStorage storage,
      List<LectureRecord> existing, String zipPath) async {
    final input = InputFileStream(zipPath);
    final written = <File>[];
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      if (archive.files.length > 3000) {
        throw const FormatException('В архиве слишком много файлов');
      }
      final entries = <String, ArchiveFile>{};
      var total = 0;
      for (final entry in archive.files) {
        if (!entry.isFile || entries.containsKey(entry.name) ||
            (entry.name != 'library.json' &&
                !RegExp(_mediaName).hasMatch(entry.name))) {
          throw const FormatException('Архив содержит недопустимые файлы');
        }
        if (entry.size < 0 || entry.size > _maxEntryBytes) {
          throw const FormatException('Файл в архиве слишком большой');
        }
        total += entry.size;
        if (total > _maxTotalBytes) {
          throw const FormatException('Архив превышает допустимый размер');
        }
        entries[entry.name] = entry;
      }
      final metadata = entries['library.json'];
      if (metadata == null || metadata.size > 4 * 1024 * 1024) {
        throw const FormatException('В архиве нет списка лекций');
      }
      final document = jsonDecode(utf8.decode(metadata.content as List<int>));
      if (document is! Map<String, dynamic> || document['version'] != 1 ||
          document['records'] is! List) {
        throw const FormatException('Неподдерживаемый формат копии');
      }
      final ids = existing.map((record) => record.taskId).toSet();
      final incoming = <LectureRecord>[];
      final needed = <String>{};
      for (final raw in document['records'] as List) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Повреждён список лекций');
        }
        final id = raw['task_id'];
        if (id is! String || !RegExp(r'^[A-Za-z0-9-]{8,64}$').hasMatch(id)) {
          throw const FormatException('Неверный идентификатор лекции');
        }
        if (ids.contains(id)) continue;
        ids.add(id);
        final json = Map<String, dynamic>.from(raw);
        for (final key in ['image_path', 'audio_path']) {
          final archiveName = json[key] as String? ?? '';
          if (archiveName.isEmpty && key == 'audio_path') continue;
          if (!RegExp(_mediaName).hasMatch(archiveName) ||
              !entries.containsKey(archiveName)) {
            throw const FormatException('В копии отсутствует снимок или аудио');
          }
          needed.add(archiveName);
          final name = archiveName.substring('media/'.length);
          json[key] = '${storage.root.path}${Platform.pathSeparator}$name';
        }
        incoming.add(LectureRecord.fromJson(json));
      }
      for (final name in needed) {
        final target = File('${storage.root.path}${Platform.pathSeparator}${name.substring(6)}');
        if (await target.exists()) {
          throw const FormatException('Файл из копии уже есть в библиотеке');
        }
        final bytes = entries[name]!.content as List<int>;
        if (bytes.length > _maxEntryBytes) {
          throw const FormatException('Файл в архиве слишком большой');
        }
        await target.writeAsBytes(bytes, flush: true);
        written.add(target);
      }
      if (incoming.isNotEmpty) await storage.saveAll([...existing, ...incoming]);
      return incoming.length;
    } catch (_) {
      for (final file in written) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    } finally {
      await input.close();
    }
  }
}
