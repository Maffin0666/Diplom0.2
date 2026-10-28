import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_preferences.dart';
import 'models.dart';
import 'user_error.dart';
import 'voice_commands.dart';
import 'voice_navigation.dart';

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
  final _scroll = ScrollController();
  int? _speaking;
  int _selected = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && PreferencesScope.of(context).spokenHints &&
          !MediaQuery.accessibleNavigationOf(context)) {
        final steps = formulaSteps(widget.chunk);
        if (steps.isNotEmpty) unawaited(_speak(0, steps.first));
      }
    });
  }

  Future<bool> _speak(int index, FormulaStep step) async {
    try {
      await _tts.stop();
      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(.42);
      await _tts.awaitSpeakCompletion(true);
      if (mounted) {
        setState(() {
          _selected = index;
          _speaking = index;
          _error = '';
        });
      }
      await _tts.speak(step.speech);
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = userError(error));
      return false;
    } finally {
      if (mounted) setState(() => _speaking = null);
    }
  }

  Future<bool> _command(AppVoiceIntent intent) async {
    final steps = formulaSteps(widget.chunk);
    final target = switch (intent.command) {
      AppCommand.next => _selected + 1,
      AppCommand.previous => _selected - 1,
      AppCommand.firstFragment => 0,
      AppCommand.lastFragment => steps.length - 1,
      AppCommand.fragment => (intent.number ?? 0) - 1,
      AppCommand.play ||
      AppCommand.repeatFormula ||
      AppCommand.explainFormula =>
        _selected,
      _ => null,
    };
    if (intent.command == AppCommand.pause) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = null);
      return true;
    }
    if (target == null) return false;
    if (target < 0 || target >= steps.length) {
      throw VoiceActionFeedback(
          target < 0 ? 'Это первый шаг разбора' : 'Это последний шаг разбора');
    }
    if (!await _speak(target, steps[target])) {
      throw const VoiceActionFeedback(
          'Не удалось озвучить шаг. Проверьте синтез речи в настройках телефона.');
    }
    return true;
  }

  @override
  void dispose() {
    unawaited(_stopQuietly());
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _stopQuietly() async {
    try {
      await _tts.stop();
    } catch (_) {
      // The system speech service may already be gone while closing.
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = formulaSteps(widget.chunk);
    return VoicePage(
        scrollController: _scroll,
        onCommand: _command,
      beforeListen: () async {
        await _tts.stop();
        if (mounted) setState(() => _speaking = null);
      },
        child: Scaffold(
          appBar: AppBar(title: const Text('Разбор формулы'), actions: [
            IconButton(
              tooltip: 'Остановить чтение формулы',
              onPressed:
                  _speaking == null ? null : () => unawaited(_tts.stop()),
              icon: const Icon(Icons.stop_rounded),
            ),
          ]),
          body: SafeArea(
              child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            children: [
              Text(widget.chunk.text,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              const Text('Нажмите часть выражения или скажите «следующий шаг», '
                  '«предыдущий шаг», «шаг два». Для повторения скажите «воспроизвести».'),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 18),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                      child: ListTile(
                    selected: _selected == i,
                    contentPadding: const EdgeInsets.all(12),
                    title: Text(
                        'Шаг ${i + 1} из ${steps.length}. ${steps[i].title}'),
                    subtitle: Text(steps[i].speech),
                    trailing: Icon(_speaking == i
                        ? Icons.graphic_eq_rounded
                        : Icons.volume_up_rounded),
                    onTap: () => unawaited(_speak(i, steps[i])),
                  )),
                ),
            ],
          )),
        ));
  }
}
