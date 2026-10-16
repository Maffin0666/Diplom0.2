import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/app_preferences.dart';
import 'package:lecture_reader/app_theme.dart';
import 'package:lecture_reader/formula_breakdown.dart';
import 'package:lecture_reader/home_page.dart';
import 'package:lecture_reader/lecture_export.dart';
import 'package:lecture_reader/lektoria_sprite.dart';
import 'package:lecture_reader/lyrics_player.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/settings_page.dart';

LectureRecord _lecture() => LectureRecord(
      taskId: 'sample',
      serverBase: 'http://localhost:8000',
      imagePath: 'missing.jpg',
      createdAt: DateTime(2026),
      manifestJson: {
        'status': 'completed',
        'full_text': 'Первая строка',
        'total_duration': 6,
        'chunks': [
          {
            'id': 'text',
            'index': 0,
            'text': 'Первое второе третье',
            'spoken_text': 'Первое второе третье',
            'start_time': 0,
            'end_time': 3,
          },
          {
            'id': 'formula',
            'index': 1,
            'text': 'A/b',
            'spoken_text': 'дробь: числитель а; знаменатель б; конец дроби',
            'is_formula': true,
            'start_time': 3,
            'end_time': 6,
          },
        ],
      },
    );

void main() {
  test('новые предпочтения и скорость 3× переживают сохранение', () {
    final prefs = AppPreferences.fromJson(const AppPreferences(
      showMascot: false,
      autoCapture: true,
      earcons: false,
      palette: 'black_yellow',
      fontMode: 'atkinson',
      playbackSpeed: 3,
    ).toJson());
    expect(prefs.showMascot, isFalse);
    expect(prefs.autoCapture, isTrue);
    expect(prefs.earcons, isFalse);
    expect(prefs.palette, 'black_yellow');
    expect(prefs.fontMode, 'atkinson');
    expect(prefs.playbackSpeed, 3);
    expect(AppPreferences.fromJson({'playback_speed': 20}).playbackSpeed, 3);
  });

  test('разбор дроби и экспорт используют исправленный текст и метки', () {
    final record = _lecture();
    final formula = record.manifest!.chunks.last;
    final steps = formulaSteps(formula);
    expect(steps.map((step) => step.title),
        containsAll(['Числитель', 'Знаменатель', 'Переменная A']));
    expect(transcriptForExport(record), contains('Формула: A/b'));
    expect(timedTranscriptForExport(record), contains('[00:03.00]'));
    expect(timedTranscriptForExport(record), contains('знаменатель б'));
  });

  test('подсветка слова ограничена временем текстового фрагмента', () {
    final chunks = _lecture().manifest!.chunks;
    expect(
        estimatedWordIndex(chunks.first, const Duration(milliseconds: 100)), 0);
    expect(estimatedWordIndex(chunks.first, const Duration(milliseconds: 1500)),
        1);
    expect(
        estimatedWordIndex(chunks.first, const Duration(seconds: 4)), isNull);
    expect(estimatedWordIndex(chunks.last, const Duration(seconds: 4)), isNull);
  });

  testWidgets('отключение маскота скрывает каждый спрайт', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PreferencesScope(
        preferences: AppPreferences(showMascot: false),
        child:
            Scaffold(body: LectoriaSprite(pose: LectoriaPose.idle, size: 90)),
      ),
    ));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('переключатель маскота сразу обновляет предпросмотр',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        server: '',
        theme: ThemeMode.light,
        scale: 1,
        onSave: (_, __, ___) async {},
      ),
    ));
    expect(find.byType(Image), findsWidgets);
    await tester.tap(find.text('Доступность'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Отключить маскота'), 250);
    await tester.tap(find.text('Отключить маскота'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('плеер помещается на узком экране при масштабе 300%',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3)),
        child: PreferencesScope(
          preferences: const AppPreferences(showMascot: false),
          child: LyricsPlayer(
            record: _lecture(),
            position: Duration.zero,
            playing: false,
            loading: false,
            speed: 1,
            onPlayPause: () {},
            onSeek: (_) {},
            onSeekTime: (_) {},
            onSpeed: (_) {},
            onBookmark: () {},
            onEditTranscript: () {},
            pose: LectoriaPose.idle,
            message: '',
            error: '',
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Воспроизвести'), findsOneWidget);
  });

  testWidgets('главная и настройки не переполняются при масштабе 300%',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget scaled(Widget page) => MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: PreferencesScope(
                preferences: const AppPreferences(showMascot: false),
                child: page),
          ),
        );
    await tester.pumpWidget(scaled(HomePage(
      records: [_lecture()],
      serverConfigured: true,
      onOpen: (_) {},
      onCapture: () {},
      onSettings: () {},
      onDelete: (_) async {},
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(scaled(SettingsPage(
      server: '',
      theme: ThemeMode.light,
      scale: 3,
      onSave: (_, __, ___) async {},
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
