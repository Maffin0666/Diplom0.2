import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/app_preferences.dart';
import 'package:lecture_reader/app_theme.dart';
import 'package:lecture_reader/help_page.dart';
import 'package:lecture_reader/lecture_view.dart';
import 'package:lecture_reader/lyrics_player.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/settings_page.dart';
import 'package:lecture_reader/text_frame_assessment.dart';
import 'package:lecture_reader/voice_commands.dart';
import 'package:lecture_reader/voice_navigation.dart';

LectureRecord record() => LectureRecord(
        taskId: 'test',
        serverBase: 'http://localhost:8000',
        imagePath: 'missing.jpg',
        createdAt: DateTime(2026),
        status: 'completed',
        manifestJson: {
          'status': 'completed',
          'full_text': 'Одна и та же лекция',
          'total_duration': 30,
          'chunks': [
            {
              'id': 'short',
              'index': 0,
              'text': 'Короткая строка',
              'start_time': 0,
              'end_time': 10
            },
            {
              'id': 'long',
              'index': 1,
              'text': List.filled(45, 'Длинный фрагмент конспекта.').join(' '),
              'start_time': 10,
              'end_time': 30
            },
          ],
        });

void main() {
  test('предложения читаются раздельно без изменения фрагмента', () {
    expect(readableTranscriptText('Первая мысль. Вторая мысль! И третья.'),
        'Первая мысль.\nВторая мысль!\nИ третья.');
  });
  test('команды навигации, настройки и переход к номеру', () {
    expect(parseAppVoiceCommand('открой лекцию два').number, 2);
    expect(parseAppVoiceCommand('открой лекцию двадцать один').number, 21);
    expect(parseAppVoiceCommand('Фрагмент 17').command, AppCommand.fragment);
    expect(parseAppVoiceCommand('тёмная тема').command, AppCommand.dark);
    expect(parseAppVoiceCommand('доступность').command, AppCommand.section);
    expect(parseAppVoiceCommand('сделай фото').command, AppCommand.capture);
    expect(parseAppVoiceCommand('назад').command, AppCommand.back);
    expect(parseAppVoiceCommand('предыдущий').command, AppCommand.previous);
    expect(parseAppVoiceCommand('разбери формулу').command,
        AppCommand.explainFormula);
    expect(parseAppVoiceCommand('закладки').command, AppCommand.bookmarks);
    expect(parseAppVoiceCommand('библиотека').command, AppCommand.library);
    expect(
        parseAppVoiceCommand('прокрути вниз').command, AppCommand.scrollDown);
    expect(parseAppVoiceCommand('выключи голос').command, AppCommand.stopVoice);
    expect(parseAppVoiceCommand('совсем неизвестная фраза').command,
        AppCommand.unknown);
    expect(parseAppVoiceCommand('открой расшифровку').command, AppCommand.edit);
    expect(parseAppVoiceCommand('следующий фрагмент').command, AppCommand.next);
    expect(parseAppVoiceCommand('предыдущий фрагмент').command,
        AppCommand.previous);
    expect(parseAppVoiceCommand('последний фрагмент').command,
        AppCommand.lastFragment);
    expect(parseAppVoiceCommand('первый фрагмент').command,
        AppCommand.firstFragment);
    expect(parseAppVoiceCommand('замени текст').command, AppCommand.dictate);
    expect(parseAppVoiceCommand('удали фрагмент').command,
        AppCommand.removeFragment);
    expect(
        parseAppVoiceCommand('помощь команды').command, AppCommand.helpTopic);
    expect(HelpPage.topicFor(parseAppVoiceCommand('помощь съёмка').section),
        'capture');
    expect(
        HelpPage.topicFor(parseAppVoiceCommand('помощь подключение').section),
        'connection');
    expect(parseAppVoiceCommand('выключи панель голоса').option,
        'show_voice_dock');
    expect(parseAppVoiceCommand('выключи панель голоса').enabled, isFalse);
    expect(parseAppVoiceCommand('включи вибрацию').option, 'haptics');
    expect(parseAppVoiceCommand('распознавай на ноутбуке').value, 'server');
    expect(parseAppVoiceCommand('проверь связь').command,
        AppCommand.checkConnection);
  });

  test('каждая фраза из справки распознаётся приложением', () {
    for (final example in voiceHelpExamples) {
      expect(
          parseAppVoiceCommand(example.$2).command, isNot(AppCommand.unknown),
          reason: example.$2);
    }
  });

  test('контрастная тема и настройки сохраняют доступность', () {
    final theme = AppTheme.dark(highContrast: true);
    expect(theme.colorScheme.surface, Colors.black);
    expect(theme.colorScheme.onSurface, Colors.white);
    expect(theme.colorScheme.outlineVariant, Colors.white);
    expect(AppTheme.light(boldText: true).textTheme.bodyLarge?.fontWeight,
        FontWeight.w700);
    final prefs = AppPreferences.fromJson(const AppPreferences(
            highContrast: true,
            reduceMotion: true,
            continuousVoice: true,
            playbackSpeed: 1.5)
        .toJson());
    expect(prefs.highContrast && prefs.reduceMotion && prefs.continuousVoice,
        isTrue);
    expect(prefs.playbackSpeed, 1.5);
    expect(AppPreferences.fromJson({}).spokenHints, isTrue);
  });

  testWidgets('длинный чанк не сдвигает кнопки плеера', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lecture = record();
    Widget page(int seconds) => MaterialApp(
        theme: AppTheme.light(),
        home: LectureView(
          record: lecture,
          position: Duration(seconds: seconds),
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
          onEditTranscript: () {},
        ));
    await tester.pumpWidget(page(1));
    final before = tester.getTopLeft(find.byTooltip('Воспроизвести'));
    final transcriptHeight = tester
        .getSize(find.byKey(const ValueKey('lyrics_transcript_scroll')))
        .height;
    await tester.pumpWidget(page(11));
    await tester.pump();
    expect(tester.getTopLeft(find.byTooltip('Воспроизвести')), before);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('lyrics_transcript_scroll')))
            .height,
        transcriptHeight);
    await tester.drag(find.byKey(const ValueKey('lyrics_transcript_scroll')),
        const Offset(0, -150));
    await tester.pump();
    expect(tester.getTopLeft(find.byTooltip('Воспроизвести')), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('голосовая панель помещается при крупном тексте', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final voice = VoiceNavigation();
    addTearDown(voice.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(highContrast: true),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
            bottomNavigationBar: VoiceDock(
          voice: voice,
          onHelp: () {},
        )),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Помощь'), findsOneWidget);
    final before = tester.getTopLeft(find.text('Сказать Лектории'));
    voice.message = 'Не знаю такой команды. Скажите помощь.';
    voice.feedbackVisible = true;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(highContrast: true),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          bottomNavigationBar: VoiceDock(voice: voice, onHelp: () {}),
        ),
      ),
    ));
    expect(tester.getTopLeft(find.text('Сказать Лектории')), before);
    expect(find.textContaining('Не знаю такой команды'), findsOneWidget);
  });

  testWidgets('справка разделяет краткое руководство и команды',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpPage()));
    expect(find.text('Снимите. Проверьте. Слушайте.'), findsOneWidget);
    await tester.tap(find.text('Голосовые команды'));
    await tester.pumpAndSettle();
    expect(find.text('Навигация'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Снимите. Проверьте. Слушайте.'), findsOneWidget);
  });

  testWidgets('голос работает в разделе настроек и исключает скрытый экран',
      (tester) async {
    final voice = VoiceNavigation();
    final navigator = GlobalKey<NavigatorState>();
    var hiddenCalls = 0;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) => VoiceScope(controller: voice, child: child!),
        home: VoicePage(
            onCommand: (_) async {
              hiddenCalls++;
              return true;
            },
            child: const Scaffold(body: Text('Главная')))));
    navigator.currentState!.push(MaterialPageRoute(
        builder: (_) => SettingsPage(
            server: '',
            theme: ThemeMode.system,
            scale: 1,
            onSave: (_, __, ___) async {})));
    await tester.pumpAndSettle();
    expect(await voice.dispatch(parseAppVoiceCommand('доступность')), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Высокая контрастность'), findsOneWidget);
    expect(hiddenCalls, 0);
    await voice.dispatch(parseAppVoiceCommand('назад'));
    await tester.pumpAndSettle();
    expect(find.text('Подстроим под вас'), findsOneWidget);
    expect(hiddenCalls, 0);
    await tester.pumpWidget(const SizedBox());
    voice.dispose();
  });

  test('камера отличает строки от чистой страницы, сетки и тени', () {
    const w = 180, h = 240;
    final white = Uint8List(w * h)..fillRange(0, w * h, 230);
    expect(assessTextFrame(white, w, h).textLikely, isFalse);
    final grid = Uint8List.fromList(white);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (y % 20 == 0 || x % 20 == 0) grid[y * w + x] = 80;
      }
    }
    expect(assessTextFrame(grid, w, h).textLikely, isFalse);
    final text = Uint8List.fromList(white);
    for (var row = 45; row < 200; row += 24) {
      for (var y = row; y < row + 5; y++) {
        for (var x = 24; x < 156; x++) {
          if (x % 9 < 5) text[y * w + x] = 35;
        }
      }
    }
    expect(assessTextFrame(text, w, h).textLikely, isTrue);
    final chalkboard = Uint8List(w * h)..fillRange(0, w * h, 30);
    for (var row = 45; row < 200; row += 24) {
      for (var y = row; y < row + 5; y++) {
        for (var x = 24; x < 156; x++) {
          if (x % 9 < 5) chalkboard[y * w + x] = 210;
        }
      }
    }
    expect(assessTextFrame(chalkboard, w, h).textLikely, isTrue);
    final shadow = Uint8List.fromList(white);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < 60; x++) {
        shadow[y * w + x] = 70;
      }
    }
    expect(assessTextFrame(shadow, w, h).textLikely, isFalse);

    // Repeated light marks on a large dark object can resemble character
    // strokes. The changing background must prevent an automatic shot.
    final texturedObject = Uint8List.fromList(white);
    for (var y = 30; y < 205; y++) {
      if (y >= 100 && y < 130) continue;
      for (var x = 14; x < 166; x++) {
        texturedObject[y * w + x] = 25;
      }
    }
    for (final row in [40, 62, 145, 167]) {
      for (var y = row; y < row + 5; y++) {
        for (var x = 24; x < 156; x++) {
          if (x % 9 < 5) texturedObject[y * w + x] = 220;
        }
      }
    }
    final objectAssessment = assessTextFrame(texturedObject, w, h);
    expect(objectAssessment.lines, greaterThanOrEqualTo(2));
    expect(objectAssessment.backgroundConsistent, isFalse);
    expect(objectAssessment.textLikely, isFalse);
  });
}
