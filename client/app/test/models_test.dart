import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/voice_commands.dart';

void main() {
  test('переходы учитывают паузу и индекс фрагмента', () {
    final manifest = LectureManifest.fromJson({
      'task_id': '1',
      'status': 'completed',
      'chunks': [
        {
          'index': 1,
          'text': 'x=1',
          'is_formula': true,
          'start_time': 3.0,
          'end_time': 5.0
        },
        {
          'index': 0,
          'text': 'Текст',
          'is_formula': false,
          'start_time': 0.0,
          'end_time': 2.0
        },
      ],
    });
    expect(manifest.chunkAt(const Duration(milliseconds: 2500)), 0);
    expect(manifest.chunkAt(const Duration(seconds: 4)), 1);
    expect(manifest.nearestFormulaAtOrBefore(1), 1);
    expect(manifest.nearestFormulaAtOrBefore(0), isNull);
  });

  test('голосовая команда распознаётся без точного совпадения строки', () {
    expect(parseVoiceCommand('Повтори формулу'), VoiceCommand.repeatFormula);
    expect(
        parseVoiceCommand('перейди к следующему фрагменту'), VoiceCommand.next);
    expect(parseVoiceCommand('поставь на паузу'), VoiceCommand.pause);
  });
}
