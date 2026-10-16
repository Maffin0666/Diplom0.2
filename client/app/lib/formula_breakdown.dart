import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'models.dart';

class FormulaStep {
  const FormulaStep(this.title, this.speech);
  final String title, speech;
}

List<FormulaStep> formulaSteps(LectureChunk chunk) {
  final spoken = chunk.spokenText.trim().isEmpty
      ? chunk.text.trim()
      : chunk.spokenText.trim();
  final steps = <FormulaStep>[FormulaStep('Формула целиком', spoken)];
  final structured = RegExp(
          r'дробь: числитель (.*?); знаменатель (.*?); конец дроби',
          dotAll: true)
      .firstMatch(spoken);
  if (structured != null) {
    steps.add(FormulaStep('Числитель', structured.group(1)!.trim()));
    steps.add(FormulaStep('Знаменатель', structured.group(2)!.trim()));
  } else {
    final simple = RegExp(r'дробь (.+?) на (.+)').firstMatch(spoken);
    if (simple != null) {
      steps.add(FormulaStep('Числитель', simple.group(1)!.trim()));
      steps.add(FormulaStep('Знаменатель', simple.group(2)!.trim()));
    }
  }
  const names = {
    'a': 'а',
    'b': 'бэ',
    'c': 'цэ',
    'd': 'дэ',
    'e': 'е',
    'f': 'эф',
    'g': 'гэ',
    'h': 'аш',
    'i': 'и',
    'j': 'йот',
    'k': 'ка',
    'l': 'эль',
    'm': 'эм',
    'n': 'эн',
    'o': 'о',
    'p': 'пэ',
    'q': 'ку',
    'r': 'эр',
    's': 'эс',
    't': 'тэ',
    'u': 'у',
    'v': 'вэ',
    'w': 'дубль вэ',
    'x': 'икс',
    'y': 'игрек',
    'z': 'зет',
  };
  final seen = <String>{};
  for (final match
      in RegExp(r'(?<![A-Za-z])[A-Za-z](?![A-Za-z])').allMatches(chunk.text)) {
    final letter = match.group(0)!;
    if (!seen.add(letter)) continue;
    final caseName =
        letter == letter.toUpperCase() ? 'верхний регистр' : 'нижний регистр';
    steps.add(FormulaStep('Переменная $letter',
        'Латинская буква ${names[letter.toLowerCase()]}, $caseName'));
  }
  return steps;
}

class FormulaBreakdownPage extends StatefulWidget {
  const FormulaBreakdownPage({super.key, required this.chunk});
  final LectureChunk chunk;

  @override
  State<FormulaBreakdownPage> createState() => _FormulaBreakdownPageState();
}

class _FormulaBreakdownPageState extends State<FormulaBreakdownPage> {
  final _tts = FlutterTts();
  int? _speaking;

  Future<void> _speak(int index, FormulaStep step) async {
    try {
      await _tts.stop();
      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(.42);
      await _tts.awaitSpeakCompletion(true);
      if (mounted) setState(() => _speaking = index);
      await _tts.speak(step.speech);
    } finally {
      if (mounted) setState(() => _speaking = null);
    }
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = formulaSteps(widget.chunk);
    return Scaffold(
      appBar: AppBar(title: const Text('Разбор формулы')),
      body: SafeArea(
          child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.chunk.text,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          const Text('Нажмите часть выражения, чтобы прослушать её отдельно.'),
          const SizedBox(height: 18),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                  child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                title: Text(steps[i].title),
                subtitle: Text(steps[i].speech),
                trailing: Icon(_speaking == i
                    ? Icons.graphic_eq_rounded
                    : Icons.volume_up_rounded),
                onTap: () => unawaited(_speak(i, steps[i])),
              )),
            ),
        ],
      )),
    );
  }
}
