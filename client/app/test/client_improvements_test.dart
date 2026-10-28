import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/capture_review_page.dart';
import 'package:lecture_reader/home_page.dart';
import 'package:lecture_reader/photo_line_preview.dart';
import 'package:lecture_reader/storage.dart';
import 'package:lecture_reader/transcript_editor.dart';
import 'package:lecture_reader/voice_commands.dart';
import 'package:lecture_reader/voice_navigation.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('фрагмент хранит координаты и флаг необходимости проверки', () {
    final manifest = LectureManifest.fromJson({
      'image_width': 4000,
      'image_height': 3000,
      'chunks': [
        {
          'id': 'line',
          'index': 0,
          'text': 'слова',
          'confidence': .32,
          'bbox': [100, 200, 1800, 320],
        }
      ]
    });
    expect(manifest.imageWidth, 4000);
    expect(manifest.chunks.single.bbox, [100, 200, 1800, 320]);
    expect(manifest.chunks.single.needsReview, isTrue);
    expect(
        LectureRecord(
          taskId: 't',
          serverBase: '',
          imagePath: '',
          createdAt: DateTime(2026),
          lastPositionMs: 12345,
        ).toJson()['last_position_ms'],
        12345);
    expect(parseAppVoiceCommand('использовать снимок').command,
        AppCommand.usePhoto);
    expect(parseAppVoiceCommand('переснять').command, AppCommand.capture);
  });

  test('полоса фото масштабируется из координат оригинала', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(Colors.white, ui.BlendMode.src);
    final image = await recorder.endRecording().toImage(1000, 750);
    addTearDown(image.dispose);
    final chunk = LectureChunk.fromJson({
      'id': 'a',
      'bbox': [400, 600, 1200, 800],
    });
    final rect = lineSourceRect(chunk, 4000, 3000, image)!;
    final region = photoRegionRect(chunk, 4000, 3000, image)!;
    expect(region.left, 100);
    expect(region.top, 150);
    expect(region.right, 300);
    expect(region.bottom, 200);
    expect(rect.left, lessThan(100));
    expect(rect.right, greaterThan(300));
    expect(rect.top, lessThan(150));
    expect(rect.bottom, greaterThan(200));
  });

  test('проверка снимка читает фотографию и даёт понятные подсказки', () async {
    final dir = await Directory.systemTemp.createTemp('lektoria_capture_');
    addTearDown(() => dir.delete(recursive: true));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(Colors.white, ui.BlendMode.src);
    final image = await recorder.endRecording().toImage(320, 240);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${dir.path}${Platform.pathSeparator}page.png');
    await file.writeAsBytes(data!.buffer.asUint8List());
    final notes = await inspectCapture(XFile(file.path));
    expect(notes, contains(contains('Строки видны неуверенно')));
  });

  test('повреждённый индекс восстанавливается из прошлой копии', () async {
    final dir = await Directory.systemTemp.createTemp('lektoria_storage_');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LectureStorage(dir);
    LectureRecord record(String id) => LectureRecord(
          taskId: id,
          serverBase: 'http://localhost:8000',
          imagePath: '',
          createdAt: DateTime(2026),
        );
    await storage.saveAll([record('first')]);
    await storage.saveAll([record('second')]);
    await File('${dir.path}${Platform.pathSeparator}lectures.json')
        .writeAsString('{broken');
    expect((await storage.readAll()).single.taskId, 'first');
    await storage.saveSettings({'theme': 'light'});
    await storage.saveSettings({'theme': 'dark'});
    await File('${dir.path}${Platform.pathSeparator}settings.json')
        .writeAsString('{broken');
    expect((await storage.readSettings())['theme'], 'light');
  });

  test('очистка старой озвучки сохраняет текущую запись и снимок', () async {
    final dir = await Directory.systemTemp.createTemp('lektoria_audio_');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LectureStorage(dir);
    final current =
        File('${dir.path}${Platform.pathSeparator}t_lecture_current.mp3');
    final old = File('${dir.path}${Platform.pathSeparator}t.mp3');
    final image = File('${dir.path}${Platform.pathSeparator}page.jpg');
    await current.writeAsBytes([1, 2, 3]);
    await old.writeAsBytes([4, 5]);
    await image.writeAsBytes([6]);
    final records = [
      LectureRecord(
        taskId: 't',
        serverBase: '',
        imagePath: image.path,
        audioPath: current.path,
        createdAt: DateTime(2026),
      ),
    ];
    expect(await storage.unusedAudioBytes(records), 2);
    expect(await storage.clearUnusedAudio(records), 2);
    expect(await old.exists(), isFalse);
    expect(await current.exists(), isTrue);
    expect(await image.exists(), isTrue);
  });

  testWidgets('сомнительная строка выделяется и неверный номер не роняет экран',
      (tester) async {
    final voice = VoiceNavigation();
    addTearDown(voice.dispose);
    final manifest = LectureManifest.fromJson({
      'task_id': 'test',
      'status': 'completed',
      'chunks': [
        {
          'id': 'line',
          'index': 0,
          'text': 'Сомнительное слово',
          'confidence': .2,
        }
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: VoiceScope(
        controller: voice,
        child: TranscriptEditor(
          manifest: manifest,
          imagePath: 'missing.jpg',
          onSave: (_) async {},
        ),
      ),
    ));
    expect(find.text('Фрагмент 1 из 1'), findsOneWidget);
    expect(find.text('Проверьте эту строку по фото'), findsOneWidget);
    await expectLater(
        voice.dispatch(const AppVoiceIntent(AppCommand.fragment, number: 99)),
        throwsA(isA<VoiceActionFeedback>().having(
            (error) => error.message, 'сообщение',
            'Такого фрагмента в лекции нет')));
    await tester.pump();
    expect(find.text('Фрагмент 1 из 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('библиотека показывает место продолжения лекции', (tester) async {
    final record = LectureRecord(
      taskId: 'resume',
      serverBase: '',
      imagePath: '',
      createdAt: DateTime(2026),
      status: 'completed',
      lastPositionMs: 83000,
      manifestJson: {'status': 'completed', 'full_text': 'Конспект'},
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LectureTile(record: record, onTap: () {}, onMenu: () {}),
      ),
    ));
    expect(find.text('Продолжить с 1:23'), findsOneWidget);
  });

  testWidgets(
      'просмотр снимка доступен с крупным текстом и допускает пересъёмку',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final voice = VoiceNavigation();
    addTearDown(voice.dispose);
    CaptureDecision? decision;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(3)),
        child: VoiceScope(controller: voice, child: child!),
      ),
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () async => decision = await Navigator.of(context)
                .push<CaptureDecision>(MaterialPageRoute(
              builder: (_) => CaptureReviewPage(
                photo: XFile('missing.jpg'),
                retryLabel: 'Переснять',
              ),
            )),
            child: const Text('Открыть'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Проверить снимок'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
        await voice.dispatch(const AppVoiceIntent(AppCommand.capture)), isTrue);
    await tester.pumpAndSettle();
    expect(decision, CaptureDecision.retry);
  });
}
