import 'package:flutter/services.dart';

/// Turns platform-specific speech errors into instructions the student can use.
String speechFailureMessage(Object error) {
  final code = error is PlatformException ? error.code : error.toString();
  switch (code) {
    case 'recognizerNotAvailable':
      return 'На телефоне не найдена служба распознавания речи. '
          'Проверьте в настройках Android, что служба голосового ввода '
          'установлена и включена. Затем снова откройте приложение. '
          'Пока можно пользоваться кнопками воспроизведения и навигации.';
    case 'error_permission':
      return 'Разрешите приложению доступ к микрофону в настройках Android.';
    case 'error_network':
      return 'Службе распознавания речи требуется сеть. Проверьте подключение '
          'телефона и повторите команду.';
    case 'error_no_match':
    case 'error_speech_timeout':
      return 'Команда не расслышана. Нажмите микрофон и повторите её.';
  }
  return 'Не удалось принять голосовую команду: $error';
}
