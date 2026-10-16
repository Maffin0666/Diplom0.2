import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/app_haptics.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/saved_notes_page.dart';
import 'package:lecture_reader/settings_page.dart';

LectureRecord _record() => LectureRecord(
      taskId: 'demo',
      serverBase: 'http://localhost:8000',
      imagePath: 'sample.jpg',
      createdAt: DateTime(2026, 10, 12),
      manifestJson: {
        'status': 'completed',
        'full_text': 'Исходное название',
        'chunks': [
          {
            'id': 'a',
            'index': 0,
            'text': 'Важная строка',
            'is_formula': false,
            'start_time': 0,
            'end_time': 3
          },
        ],
      },
    )..toggleBookmark(0);

void main() {
  test('переименование сохраняется без изменения расшифровки', () {
    final record = _record()..customTitle = 'Моя лекция';
    final restored = LectureRecord.fromJson(record.toJson());
    expect(restored.title, 'Моя лекция');
    expect(restored.manifest!.fullText, 'Исходное название');
    expect(restored.bookmarkIndexes, [0]);
  });

  testWidgets('все заметки открывают закладку нужной лекции', (tester) async {
    final record = _record();
    String? selected;
    await tester.pumpWidget(MaterialApp(
        home: SavedNotesPage(
      records: [record],
      onOpen: (_, chunkId) => selected = chunkId,
      onRename: (_, __) async {},
    )));
    await tester.tap(find.text('Важная строка'));
    expect(selected, 'a');
  });

  testWidgets('тема нижней панели получает предпросмотр до сохранения',
      (tester) async {
    final preview = ValueNotifier<ThemeData?>(null);
    addTearDown(preview.dispose);
    await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
      server: 'http://localhost:8000',
      theme: ThemeMode.light,
      scale: 1,
      onSave: (_, __, ___) async {},
      themePreview: preview,
    )));
    await tester.pump();
    await tester.tap(find.text('Оформление').last);
    await tester.pump();
    await tester.tap(find.text('Тёмная'));
    await tester.pump();
    expect(preview.value?.brightness, Brightness.dark);
  });

  testWidgets('проверка вибрации передаёт Android явный сигнал',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('lektoria/haptics');
    int? duration;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        duration = (call.arguments as Map)['durationMs'] as int;
        return true;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(await AppHaptics.vibrate(test: true), isTrue);
    expect(duration, 180);
    debugDefaultTargetPlatformOverride = null;
  });
}
