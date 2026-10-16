import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/app_theme.dart';
import 'package:lecture_reader/capture_page.dart';
import 'package:lecture_reader/home_page.dart';
import 'package:lecture_reader/lecture_view.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/welcome_page.dart';
import 'package:lecture_reader/bookmarks_page.dart';

LectureRecord sampleRecord() => LectureRecord(
      taskId: 'demo',
      serverBase: 'http://localhost:8000',
      imagePath: 'missing.jpg',
      createdAt: DateTime(2026, 10, 2),
      status: 'completed',
      manifestJson: {
        'status': 'completed',
        'full_text': 'Лекция по математике',
        'total_duration': 12.0,
        'chunks': [
          {
            'id': 'chunk-0',
            'index': 0,
            'text': 'Лекция по математике',
            'is_formula': false,
            'start_time': 0,
            'end_time': 6,
          },
          {
            'id': 'chunk-1',
            'index': 1,
            'text': 'x + 1 = 2',
            'is_formula': true,
            'start_time': 6,
            'end_time': 12,
          },
        ],
      },
    );

void main() {
  testWidgets('приветствие и камера работают в тёмной теме при крупном тексте',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget app(Widget page) => MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: page,
          ),
        );
    await tester.pumpWidget(app(
      WelcomePage(onStart: () {}, onSettings: () {}),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ваш конспект\nзазвучит'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(
      CapturePage(onCamera: () {}, onGallery: () {}),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('Открыть камеру'), 180);
    expect(find.text('Открыть камеру'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('тип лекции определяется по реальным фрагментам', () {
    final record = sampleRecord();
    expect(lectureKind(record), LectureKind.mixed);
    record.bookmarkIndex = 1;
    expect(LectureRecord.fromJson(record.toJson()).bookmarkIndex, 1);
  });

  test('несколько закладок переживают сохранение и удаление фрагмента', () {
    final record = sampleRecord();
    record.toggleBookmark(0);
    record.toggleBookmark(1);
    final restored = LectureRecord.fromJson(record.toJson());
    expect(restored.bookmarkIndexes, [0, 1]);
    restored.manifestJson = {
      ...restored.manifestJson!,
      'chunks': [restored.manifestJson!['chunks'][1]],
    };
    restored.retainExistingBookmarks();
    expect(restored.bookmarkIndexes, [0]);
    expect(restored.bookmarkedChunkIds, ['chunk-1']);
  });

  testWidgets('закладка открывает нужный фрагмент', (tester) async {
    final record = sampleRecord()..toggleBookmark(1);
    var selected = -1;
    await tester.pumpWidget(MaterialApp(
        home: BookmarksPage(
      record: record,
      onSelect: (index) => selected = index,
      onRemove: (index) async => record.toggleBookmark(index),
    )));
    await tester.tap(find.text('x + 1 = 2'));
    expect(selected, 1);
  });

  testWidgets('главная страница не переполняется в тёмной теме на узком экране',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: HomePage(
          records: [sampleRecord()],
          serverConfigured: true,
          onOpen: (_) {},
          onCapture: () {},
          onSettings: () {},
          onDelete: (_) async {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('библиотека ищет и фильтрует сохранённые лекции', (tester) async {
    final record = sampleRecord();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: HomePage(
        records: [record],
        serverConfigured: true,
        onOpen: (_) {},
        onCapture: () {},
        onSettings: () {},
        onDelete: (_) async {},
      ),
    ));
    await tester.tap(find.text('Библиотека').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Найдено: 1'), findsOneWidget);
    await tester.tap(find.text('Формулы'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Найдено: 0'), findsOneWidget);
    await tester.tap(find.text('Смешанные'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Найдено: 1'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'несуществующее');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Найдено: 0'), findsOneWidget);
    await tester.tap(find.byTooltip('Вернуться к лекциям'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(find.text('Недавние лекции'), 180);
    expect(find.text('Недавние лекции'), findsOneWidget);
  });

  testWidgets('плеер доступен на узком экране с крупным текстом',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = sampleRecord();
    var editOpened = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: LectureView(
          record: record,
          position: Duration.zero,
          playing: false,
          loading: false,
          audioReady: true,
          uploaded: true,
          listening: false,
          message: '',
          error: '',
          speed: 1,
          onPlayPause: () {},
          onSeek: (_) {},
          onSeekTime: (_) {},
          onListen: () {},
          onServerVoice: () {},
          onVoiceHelp: () {},
          onRetry: () {},
          onReprocess: () {},
          onSpeed: (_) {},
          onBookmark: () {},
          onEditTranscript: () => editOpened = true,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Лекция по математике'), findsWidgets);
    await tester.tap(find.byTooltip('Исправить расшифровку'));
    expect(editOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('нажатие на строку расшифровки выбирает её в аудио',
      (tester) async {
    var selected = -1;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: LectureView(
        record: sampleRecord(),
        position: Duration.zero,
        playing: false,
        loading: false,
        audioReady: true,
        uploaded: true,
        listening: false,
        message: '',
        error: '',
        speed: 1,
        onPlayPause: () {},
        onSeek: (index) => selected = index,
        onSeekTime: (_) {},
        onListen: () {},
        onServerVoice: () {},
        onVoiceHelp: () {},
        onRetry: () {},
        onReprocess: () {},
        onSpeed: (_) {},
        onBookmark: () {},
        onEditTranscript: () {},
      ),
    ));
    await tester.tap(find.text('x + 1 = 2'));
    expect(selected, 1);
  });
}
