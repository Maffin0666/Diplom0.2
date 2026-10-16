import 'package:flutter/services.dart';

bool speechServiceUnavailable(Object error) =>
    error is PlatformException && error.code == 'recognizerNotAvailable';

/// Turns platform-specific speech errors into instructions the student can use.
String speechFailureMessage(Object error) {
  final code = error is PlatformException ? error.code : error.toString();
  switch (code) {
    case 'recognizerNotAvailable':
      return 'Android не нашёл службу, которая превращает речь в текст. '
          'Проверьте приложение «Распознавание и синтез речи от Google» '
          '(Speech Recognition & Synthesis) в Google Play '
          'и включите «Голосовой ввод Google»: Настройки → Общие настройки → '
          'Список клавиатур и клавиатура по умолчанию. '
          'Лектория также может распознавать короткие команды на ноутбуке.';
    case 'error_permission':
      return 'Разрешите приложению доступ к микрофону в настройках Android.';
    case 'error_network':
      return 'Службе распознавания речи требуется сеть. Проверьте подключение '
          'телефона и повторите команду.';
    case 'error_no_match':
    case 'error_speech_timeout':
      return 'Команда не расслышана. Нажмите микрофон и повторите её.';
  }
  return 'Не удалось распознать команду. Проверьте доступ к микрофону и попробуйте ещё раз. Если проблема повторится, выберите распознавание на ноутбуке в настройках.';
}
