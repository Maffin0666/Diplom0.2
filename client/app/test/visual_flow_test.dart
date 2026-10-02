import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/app_theme.dart';
import 'package:lecture_reader/home_page.dart';
import 'package:lecture_reader/lecture_view.dart';
import 'package:lecture_reader/models.dart';

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
            'index': 0,
            'text': 'Лекция по математике',
            'is_formula': false,
            'start_time': 0,
            'end_time': 6,
          },
          {
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
  test('тип лекции определяется по реальным фрагментам', () {
    final record = sampleRecord();
    expect(lectureKind(record), LectureKind.mixed);
    record.bookmarkIndex = 1;
    expect(LectureRecord.fromJson(record.toJson()).bookmarkIndex, 1);
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
    await tester.pumpAndSettle();
    expect(find.text('Найдено: 1'), findsOneWidget);
    await tester.tap(find.text('Формулы'));
    await tester.pumpAndSettle();
    expect(find.text('Найдено: 0'), findsOneWidget);
    await tester.tap(find.text('Смешанные'));
    await tester.pumpAndSettle();
    expect(find.text('Найдено: 1'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'несуществующее');
    await tester.pumpAndSettle();
    expect(find.text('Найдено: 0'), findsOneWidget);
    await tester.tap(find.byTooltip('Вернуться к лекциям'));
    await tester.pumpAndSettle();
    expect(find.text('Недавние лекции'), findsOneWidget);
  });

  testWidgets('плеер доступен на узком экране с крупным текстом',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final record = sampleRecord();
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
          onRetry: () {},
          onReprocess: () {},
          onSpeed: (_) {},
          onBookmark: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Лекция по математике'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
