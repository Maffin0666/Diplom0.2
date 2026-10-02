import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/speech_diagnostics.dart';

void main() {
  test('недоступная служба речи объясняется без PlatformException', () {
    final message = speechFailureMessage(PlatformException(
      code: 'recognizerNotAvailable',
      message: 'Speech recognition not available on this device',
    ));
    expect(message, contains('служба распознавания речи'));
    expect(message, contains('кнопками'));
    expect(message, isNot(contains('PlatformException')));
  });

  test('отказ микрофона показывает действие для пользователя', () {
    expect(speechFailureMessage('error_permission'), contains('микрофону'));
  });
}
