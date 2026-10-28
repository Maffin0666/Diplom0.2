import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.retryAfter});
  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

class RecognitionApi {
  RecognitionApi(String address, {http.Client? client})
      : base = parseServerAddress(address),
        _client = client ?? http.Client();

  final Uri base;
  final http.Client _client;

  static Uri parseServerAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Укажите адрес вида http://192.168.1.5:8000');
    }
    return uri.replace(path: '/');
  }

  Uri _url(String path) => base.resolve(path);

  Future<void> checkHealth() async {
    final response =
        await _client.get(_url('/health')).timeout(const Duration(seconds: 12));
    _check(response);
    final data = decodeObject(response.body);
    if (data['models_loaded'] != true) {
      throw const ApiException('Сервер ещё загружает модели');
    }
  }

  Future<String> upload(String taskId, String imagePath) async {
    final request =
        http.MultipartRequest('POST', _url('/api/v1/recognition/upload'));
    request.headers['X-Upload-Id'] = taskId;
    final extension = imagePath.split('.').last.toLowerCase();
    final subtype = switch (extension) {
      'jpg' || 'jpeg' => 'jpeg',
      'png' => 'png',
      'webp' => 'webp',
      _ => throw const FormatException('Нужен снимок JPEG, PNG или WEBP'),
    };
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      imagePath,
      contentType: MediaType('image', subtype),
    ));
    final streamed =
        await _client.send(request).timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamed);
    _check(response, accepted: {202});
    final returnedId = decodeObject(response.body)['task_id'];
    if (returnedId != taskId) {
      throw const FormatException('Сервер вернул другой номер задачи');
    }
    return taskId;
  }

  Future<String> status(String taskId) async {
    final response = await _client
        .get(_url('/api/v1/recognition/status/$taskId'))
        .timeout(const Duration(seconds: 15));
    _check(response);
    return decodeObject(response.body)['status'] as String? ?? 'pending';
  }

  Future<Map<String, dynamic>> result(String taskId) async {
    final response = await _client
        .get(_url('/api/v1/recognition/result/$taskId'))
        .timeout(const Duration(seconds: 20));
    _check(response);
    final manifest = decodeObject(response.body);
    if (manifest['task_id'] != taskId) {
      throw const FormatException('Номер результата не совпадает с задачей');
    }
    return manifest;
  }

  Future<Map<String, dynamic>> renderCorrection(
      String taskId, List<ChunkCorrection> chunks) async {
    final response = await _client
        .post(
          _url('/api/v1/recognition/result/$taskId/correction'),
          headers: const {'content-type': 'application/json; charset=utf-8'},
          body: jsonEncode(
              {'chunks': chunks.map((chunk) => chunk.toJson()).toList()}),
        )
        .timeout(const Duration(minutes: 5));
    _check(response);
    final manifest = decodeObject(response.body);
    if (manifest['task_id'] != taskId || manifest['status'] != 'completed') {
      throw const FormatException(
          'Сервер вернул неверный исправленный результат');
    }
    return manifest;
  }

  /// Sends a short microphone recording to the laptop's offline command model.
  Future<String> recognizeVoiceCommand(String wavPath,
      {bool dictation = false}) async {
    final request = http.MultipartRequest(
        'POST',
        _url(dictation
            ? '/api/v1/voice/command?mode=dictation'
            : '/api/v1/voice/command'));
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      wavPath,
      contentType: MediaType('audio', 'wav'),
    ));
    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 25));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 404) {
      throw const ApiException(
          'На ноутбуке запущена старая версия сервера без голосовых команд');
    }
    _check(response);
    final words = decodeObject(response.body)['text'];
    if (words is! String) {
      throw const FormatException('Сервер вернул неверную команду');
    }
    return words.trim();
  }

  Future<Uri> helpSpeech(String text) async {
    final response = await _client
        .post(_url('/api/v1/help/speech'),
            headers: const {'content-type': 'application/json; charset=utf-8'},
            body: jsonEncode({'text': text}))
        .timeout(const Duration(seconds: 20));
    _check(response);
    final path = decodeObject(response.body)['audio_url'];
    if (path is! String ||
        !RegExp(r'^/audio/help_[a-f0-9]{24}\.mp3$').hasMatch(path)) {
      throw const FormatException(
          'Сервер вернул неверный адрес озвучки справки');
    }
    return _url(path);
  }

  Future<void> downloadAudio(String relativeUrl, File target) async {
    final path = Uri.tryParse(relativeUrl);
    if (path == null ||
        path.hasScheme ||
        path.hasAuthority ||
        path.hasQuery ||
        path.hasFragment ||
        !RegExp(r'^/audio/[A-Za-z0-9_-]+\.mp3$').hasMatch(relativeUrl)) {
      throw const FormatException('Сервер вернул неверный адрес аудио');
    }
    final response = await _client
        .send(http.Request('GET', _url(relativeUrl)))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException('Аудио пока недоступно',
          statusCode: response.statusCode);
    }
    final temporary = File('${target.path}.part');
    final sink = temporary.openWrite();
    var length = 0;
    try {
      await for (final bytes
          in response.stream.timeout(const Duration(seconds: 30))) {
        length += bytes.length;
        if (length > 100 * 1024 * 1024) {
          throw const FormatException('Аудиофайл слишком большой');
        }
        sink.add(bytes);
      }
      await sink.flush();
      await sink.close();
      if (length == 0) throw const FormatException('Получен пустой аудиофайл');
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } catch (_) {
      await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  void close() => _client.close();

  void _check(http.Response response, {Set<int> accepted = const {200}}) {
    if (accepted.contains(response.statusCode)) return;
    String detail = '';
    try {
      final value = decodeObject(response.body)['detail'];
      if (value is String) detail = value;
    } catch (_) {}
    final message = switch (response.statusCode) {
      404 => 'Задача не найдена на сервере',
      409 =>
        detail.isNotEmpty ? detail : 'Номер задачи уже занят другим снимком',
      422 => detail.isNotEmpty ? detail : 'Проверьте исправленный текст',
      413 => detail.isNotEmpty ? detail : 'Файл слишком большой',
      415 => detail.isNotEmpty ? detail : 'Неверный формат файла',
      429 => 'Очередь сервера заполнена',
      503 => detail.isNotEmpty ? detail : 'Сервер пока не готов',
      _ =>
        detail.isNotEmpty ? detail : 'Ошибка сервера: ${response.statusCode}',
    };
    final wait = int.tryParse(response.headers['retry-after'] ?? '');
    throw ApiException(message,
        statusCode: response.statusCode,
        retryAfter:
            wait == null ? null : Duration(seconds: wait.clamp(1, 60).toInt()));
  }
}
