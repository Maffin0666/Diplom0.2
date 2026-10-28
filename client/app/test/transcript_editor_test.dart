import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/transcript_editor.dart';
import 'package:lecture_reader/voice_commands.dart';
import 'package:lecture_reader/voice_navigation.dart';

void main() {
  testWidgets('исправленный фрагмент передаётся для новой озвучки',
      (tester) async {
    List<ChunkCorrection>? submitted;
    final manifest = LectureManifest.fromJson({
      'task_id': 'task-1',
      'status': 'completed',
      'chunks': [
        {
          'id': 'line-1',
          'index': 0,
          'text': 'Ошибочный текст',
          'spoken_text': 'Ошибочный текст',
          'is_formula': false,
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: TranscriptEditor(
        manifest: manifest,
        imagePath: 'missing.jpg',
        onSave: (corrections) async {
          submitted = corrections;
        },
      ),
    ));
    final saveButton =
        find.widgetWithText(FilledButton, 'Сохранить и озвучить');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    await tester.enterText(
        find.byKey(const ValueKey('transcript_text_0')), 'Верный текст');
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.tap(find.text('Сохранить и озвучить'));
    await tester.pump();
    expect(submitted, isNotNull);
    expect(submitted!.single.id, 'line-1');
    expect(submitted!.single.text, 'Верный текст');
    expect(submitted!.single.spokenText, isNull);
  });

  testWidgets('ручное произношение требует явного ввода', (tester) async {
    List<ChunkCorrection>? submitted;
    final manifest = LectureManifest.fromJson({
      'task_id': 'task-2',
      'status': 'completed',
      'chunks': [
        {
          'id': 'line-2',
          'index': 0,
          'text': 'x^2',
          'spoken_text': 'икс два',
          'is_formula': true,
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: TranscriptEditor(
        manifest: manifest,
        imagePath: 'missing.jpg',
        onSave: (corrections) async {
          submitted = corrections;
        },
      ),
    ));
    await tester.ensureVisible(find.text('Настроить произношение вручную'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настроить произношение вручную'));
    await tester.pump();
    expect(find.text('икс два'), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('transcript_speech_0')), 'икс в квадрате');
    await tester.tap(find.text('Сохранить и озвучить'));
    await tester.pump();
    expect(submitted?.single.spokenText, 'икс в квадрате');
  });

  testWidgets('ложный фрагмент исключается из повторной озвучки',
      (tester) async {
    List<ChunkCorrection>? submitted;
    final manifest = LectureManifest.fromJson({
      'task_id': 'task-3',
      'status': 'completed',
      'chunks': [
        {
          'id': 'valid',
          'index': 0,
          'text': 'Верный текст',
          'is_formula': false
        },
        {'id': 'noise', 'index': 1, 'text': 'Шум', 'is_formula': false},
      ],
    });
    await tester.pumpWidget(MaterialApp(
        home: TranscriptEditor(
      manifest: manifest,
      imagePath: 'missing.jpg',
      onSave: (value) async => submitted = value,
    )));
    await tester.tap(find.text('Последний'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Исключить ошибочный фрагмент'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Исключить ошибочный фрагмент'));
    await tester.pump();
    await tester.ensureVisible(find.text('Сохранить и озвучить'));
    await tester.tap(find.text('Сохранить и озвучить'));
    await tester.pump();
    expect(submitted?[0].remove, isFalse);
    expect(submitted?[1].remove, isTrue);
  });

  testWidgets('дальний фрагмент открывается и исправляется голосом',
      (tester) async {
    final voice = VoiceNavigation();
    addTearDown(voice.dispose);
    List<ChunkCorrection>? submitted;
    final manifest = LectureManifest.fromJson({
      'task_id': 'long',
      'status': 'completed',
      'chunks': [
        for (var i = 0; i < 60; i++)
          {'id': 'line-$i', 'index': i, 'text': 'Текст $i'}
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: VoiceScope(
        controller: voice,
        child: TranscriptEditor(
          manifest: manifest,
          imagePath: 'missing.jpg',
          onSave: (value) async => submitted = value,
        ),
      ),
    ));
    expect(find.byType(TextFormField), findsOneWidget);
    expect(await voice.dispatch(const AppVoiceIntent(AppCommand.lastFragment)),
        isTrue);
    await tester.pump();
    expect(find.text('Фрагмент 60 из 60'), findsOneWidget);
    expect(find.byKey(const ValueKey('transcript_text_59')), findsOneWidget);
    expect(
        await voice.dispatch(const AppVoiceIntent(AppCommand.dictate)), isTrue);
    expect(
        await voice.dispatch(const AppVoiceIntent(AppCommand.unknown,
            utterance: 'Исправленная последняя строка')),
        isTrue);
    await tester.pump();
    await tester.tap(find.text('Сохранить и озвучить'));
    await tester.pump();
    expect(submitted?.last.text, 'Исправленная последняя строка');
    expect(submitted?.first.text, 'Текст 0');
  });

  testWidgets('голосом меняются тип фрагмента и его произношение',
      (tester) async {
    final voice = VoiceNavigation();
    addTearDown(voice.dispose);
    List<ChunkCorrection>? submitted;
    final manifest = LectureManifest.fromJson({
      'task_id': 'formula',
      'status': 'completed',
      'chunks': [
        {'id': 'line', 'index': 0, 'text': 'x^2', 'is_formula': false}
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: VoiceScope(
        controller: voice,
        child: TranscriptEditor(
          manifest: manifest,
          imagePath: 'missing.jpg',
          onSave: (value) async => submitted = value,
        ),
      ),
    ));
    expect(await voice.dispatch(const AppVoiceIntent(AppCommand.markFormula)),
        isTrue);
    expect(await voice.dispatch(const AppVoiceIntent(AppCommand.dictateSpeech)),
        isTrue);
    expect(
        await voice.dispatch(const AppVoiceIntent(AppCommand.unknown,
            utterance: 'икс в квадрате')),
        isTrue);
    await tester.pump();
    expect(find.text('икс в квадрате'), findsOneWidget);
    await tester.ensureVisible(find.text('Сохранить и озвучить'));
    await tester.tap(find.text('Сохранить и озвучить'));
    await tester.pump();
    expect(submitted?.single.isFormula, isTrue);
    expect(submitted?.single.spokenText, 'икс в квадрате');
  });
}
