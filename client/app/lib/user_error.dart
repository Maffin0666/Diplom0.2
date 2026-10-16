import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';

/// Hides technical exception strings and gives a practical next step.
String userError(Object error) {
  if (error is ApiException) {
    if (error.message.contains('старая версия сервера')) {
      return 'Голосовые команды недоступны на ноутбуке. Обновите сервер и запустите его заново.';
    }
    return switch (error.statusCode) {
      413 =>
        'Снимок слишком большой. Сделайте фото ещё раз или выберите изображение меньшего размера.',
      415 =>
        'Этот формат снимка не поддерживается. Выберите JPEG, PNG или WEBP.',
      429 =>
        'Ноутбук сейчас обрабатывает другие снимки. Подождите немного и повторите попытку.',
      503 => 'Сервер ещё запускается. Подождите минуту и повторите попытку.',
      404 =>
        'Лекция не найдена на ноутбуке. Проверьте, что подключён тот же сервер, на котором она создавалась.',
      422 =>
        'Проверьте исправленный текст: в лекции должен остаться хотя бы один непустой фрагмент.',
      _ =>
        'Не удалось получить ответ от ноутбука. Проверьте подключение и повторите попытку.',
    };
  }
  if (error is SocketException || error is HttpException) {
    return 'Нет связи с ноутбуком. Подключите телефон и ноутбук к одной сети Wi-Fi и проверьте адрес сервера в настройках.';
  }
  if (error is TimeoutException) {
    return 'Ноутбук долго не отвечает. Проверьте соединение и повторите попытку через минуту.';
  }
  if (error is FileSystemException) {
    return 'Не удалось открыть сохранённый файл. Проверьте свободное место на телефоне или добавьте снимок заново.';
  }
  if (error is PlatformException) {
    if (error.code.toLowerCase().contains('permission')) {
      return 'Нужно разрешение на эту функцию. Откройте настройки Android → Приложения → Лектория.Ai → Разрешения.';
    }
    return 'Функция сейчас недоступна на телефоне. Перезапустите приложение и попробуйте ещё раз.';
  }
  if (error is FormatException) {
    if (error.message.contains('IP-адрес')) {
      return 'Введите только IP-адрес или имя ноутбука, например 192.168.1.5. Протокол и порт приложение добавит само.';
    }
    if (error.message.contains('адрес')) {
      return 'Проверьте адрес ноутбука. Пример: http://192.168.1.5:8000';
    }
    return 'Данные не удалось прочитать. Проверьте адрес сервера или попробуйте другой снимок.';
  }
  return 'Не удалось выполнить действие. Попробуйте ещё раз; если ошибка повторится, перезапустите приложение.';
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          border: Border.all(color: scheme.error, width: 2),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 16))),
        ]),
      ),
    );
  }
}
