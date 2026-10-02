import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lecture_reader/api.dart';

void main() {
  test('адрес сервера не допускает путь и стороннюю схему', () {
    expect(RecognitionApi.parseServerAddress('http://192.168.1.5:8000').host,
        '192.168.1.5');
    expect(() => RecognitionApi.parseServerAddress('file:///tmp/data'),
        throwsFormatException);
    expect(() => RecognitionApi.parseServerAddress('http://host/other'),
        throwsFormatException);
  });

  test('повторяемая загрузка отправляет UUID и верный MIME-тип', () async {
    final directory =
        await Directory.systemTemp.createTemp('lecture_client_test_');
    try {
      final image = File('${directory.path}${Platform.pathSeparator}note.jpg');
      await image.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);
      const id = '00000000-0000-4000-8000-000000000001';
      final api = RecognitionApi('http://localhost:8000',
          client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/recognition/upload');
        expect(request.headers['x-upload-id'] ?? request.headers['X-Upload-Id'],
            id);
        expect(latin1.decode(request.bodyBytes), contains('image/jpeg'));
        return http.Response('{"task_id":"$id","status":"pending"}', 202);
      }));
      try {
        expect(await api.upload(id, image.path), id);
      } finally {
        api.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('заполненная очередь сохраняет интервал Retry-After', () async {
    final api = RecognitionApi('http://localhost:8000',
        client: MockClient((request) async {
      return http.Response('{"detail":"Очередь заполнена"}', 429, headers: {
        'retry-after': '5',
        'content-type': 'application/json; charset=utf-8',
      });
    }));
    try {
      await expectLater(
          api.status('id'),
          throwsA(isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 429)
              .having((error) => error.retryAfter, 'retryAfter',
                  const Duration(seconds: 5))));
    } finally {
      api.close();
    }
  });
}
