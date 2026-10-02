import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// All lecture data stays in the application's private documents directory.
class LectureStorage {
  LectureStorage(this.root);

  final Directory root;
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
    // Recover an interrupted index replacement from the last valid copy.
    final backup = File('${_index.path}.bak');
    if (!await _index.exists() && await backup.exists()) {
      await backup.rename(_index.path);
    }
    if (!await _index.exists()) return [];
    final data = jsonDecode(await _index.readAsString());
    if (data is! List) throw const FormatException('Повреждён список лекций');
    final records = data
        .whereType<Map<String, dynamic>>()
        .map(LectureRecord.fromJson)
        .toList();
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records;
  }

  Future<void> saveAll(List<LectureRecord> records) =>
      _atomicWrite(_index, jsonEncode(records.map((r) => r.toJson()).toList()));

  Future<Map<String, dynamic>> readSettings() async {
    final backup = File('${_settings.path}.bak');
    if (!await _settings.exists() && await backup.exists()) {
      await backup.rename(_settings.path);
    }
    if (!await _settings.exists()) return {};
    return decodeObject(await _settings.readAsString());
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

  Future<void> _atomicWrite(File target, String content) async {
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
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }
}
