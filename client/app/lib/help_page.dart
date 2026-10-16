import 'dart:async';

import 'package:flutter/material.dart';

import 'lektoria_sprite.dart';
import 'visual_system.dart';
import 'voice_commands.dart';
import 'voice_navigation.dart';

/// The phrases here are exercised against the same parser used by the microphone.
const voiceHelpExamples = <(String, String, String)>[
  ('Навигация', 'главная', 'Вернуться на главный экран.'),
  ('Навигация', 'библиотека', 'Показать сохранённые лекции.'),
  ('Навигация', 'открой лекцию один', 'Открыть лекцию по номеру в библиотеке.'),
  ('Навигация', 'настройки', 'Открыть настройки.'),
  ('Навигация', 'назад', 'Вернуться на предыдущий экран.'),
  ('Лекция', 'воспроизвести', 'Продолжить прослушивание.'),
  ('Лекция', 'пауза', 'Остановить воспроизведение.'),
  ('Лекция', 'следующий фрагмент', 'Перейти к следующей строке.'),
  ('Лекция', 'предыдущий фрагмент', 'Вернуться к предыдущей строке.'),
  ('Лекция', 'фрагмент два', 'Перейти к указанному фрагменту.'),
  ('Лекция', 'последний фрагмент', 'Открыть последний фрагмент сразу.'),
  ('Лекция', 'открой расшифровку', 'Открыть исправление текста.'),
  (
    'Исправление',
    'фрагмент двадцать',
    'Сразу открыть нужный фрагмент в редакторе.'
  ),
  (
    'Исправление',
    'замени текст',
    'Слушать новую фразу для выбранного фрагмента.'
  ),
  ('Исправление', 'удали фрагмент', 'Исключить ошибочный фрагмент.'),
  ('Исправление', 'верни фрагмент', 'Вернуть исключённый фрагмент.'),
  ('Лекция', 'повтори формулу', 'Повторить ближайшую предыдущую формулу.'),
  ('Лекция', 'разбери формулу', 'Открыть пошаговое чтение формулы.'),
  ('Лекция', 'быстрее', 'Увеличить скорость на 0,25.'),
  ('Лекция', 'медленнее', 'Уменьшить скорость на 0,25.'),
  ('Лекция', 'покажи закладки', 'Показать закладки лекции.'),
  ('Съёмка', 'камера', 'Открыть камеру.'),
  ('Съёмка', 'сделай фото', 'Снять кадр, когда камера открыта.'),
  ('Съёмка', 'переснять', 'Вернуться к камере с экрана проверки.'),
  ('Съёмка', 'использовать снимок', 'Отправить проверенный кадр.'),
  ('Настройки', 'оформление', 'Открыть раздел оформления.'),
  ('Настройки', 'включи вибрацию', 'Включить тактильный отклик.'),
  ('Настройки', 'выключи панель голоса', 'Скрыть нижнюю голосовую панель.'),
  (
    'Настройки',
    'распознавай на ноутбуке',
    'Выбрать серверное распознавание команд.'
  ),
  ('Настройки', 'сохранить', 'Сохранить изменённые настройки.'),
  ('Настройки', 'проверь связь', 'Проверить соединение с ноутбуком.'),
];

class HelpPage extends StatefulWidget {
  const HelpPage({super.key, this.initialTopic});
  final String? initialTopic;

  static String? topicFor(String? words) {
    if (words == null) return null;
    if (words.contains('команд') || words.contains('голос')) {
      return 'commands';
    }
    if (words.contains('съем') ||
        words.contains('сним') ||
        words.contains('камер')) {
      return 'capture';
    }
    if (words.contains('прослуш') || words.contains('плеер')) {
      return 'listening';
    }
    if (words.contains('исправ') || words.contains('расшифров')) {
      return 'editing';
    }
    if (words.contains('подключ') || words.contains('сервер')) {
      return 'connection';
    }
    return null;
  }

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String? _topic;
  VoiceNavigation? _voice;
  bool _reading = false;
  int _readingEpoch = 0;

  static const _topics = <String, (String, IconData, String)>{
    'commands': (
      'Голосовые команды',
      Icons.record_voice_over_rounded,
      'Точные фразы, действия и экраны, на которых они работают.'
    ),
    'capture': (
      'Съёмка конспекта',
      Icons.center_focus_strong_rounded,
      'Как навести камеру, проверить кадр и отправить снимок.'
    ),
    'listening': (
      'Прослушивание',
      Icons.headphones_rounded,
      'Плеер, переход по фрагментам и закладки.'
    ),
    'editing': (
      'Исправление текста',
      Icons.edit_note_rounded,
      'Сверка с фотографией и повторное озвучивание.'
    ),
    'connection': (
      'Подключение',
      Icons.wifi_rounded,
      'Адрес ноутбука и проверка связи.'
    ),
  };

  @override
  void initState() {
    super.initState();
    _topic = widget.initialTopic;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(VoiceScope.maybeOf(context)?.announce(
              _topic == null
                  ? 'Это справка Лектории. Выберите тему. Для чтения вслух нажмите кнопку звука.'
                  : 'Раздел ${_topics[_topic]?.$1 ?? 'справки'}. Нажмите кнопку звука для подробностей.',
            ) ??
            Future<void>.value());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voice = VoiceScope.maybeOf(context);
  }

  @override
  void dispose() {
    _readingEpoch++;
    if (_reading) unawaited(_voice?.stopAnnouncement() ?? Future<void>.value());
    super.dispose();
  }

  void _select(String? topic) {
    if (topic != null && !_topics.containsKey(topic)) return;
    _readingEpoch++;
    if (_reading) unawaited(_voice?.stopAnnouncement() ?? Future<void>.value());
    setState(() {
      _topic = topic;
      _reading = false;
    });
    final title = topic == null ? 'Выберите тему справки.' : _topics[topic]!.$1;
    unawaited(
        VoiceScope.maybeOf(context)?.announce(title) ?? Future<void>.value());
  }

  Future<bool> _command(AppVoiceIntent intent) async {
    if (intent.command == AppCommand.helpTopic) {
      final topic = HelpPage.topicFor(intent.section);
      if (topic == null) return false;
      _select(topic);
      return true;
    }
    if (intent.command == AppCommand.help) {
      _select('commands');
      return true;
    }
    if (intent.command == AppCommand.back && _topic != null) {
      _select(null);
      return true;
    }
    return false;
  }

  String _spokenContent() {
    if (_topic == 'commands') {
      return 'Голосовые команды. ${voiceHelpExamples.map((item) => '${item.$2}: ${item.$3}').join(' ')}';
    }
    return switch (_topic) {
      'capture' =>
        'Съёмка. Нажмите плюс, откройте камеру и поместите текст целиком в рамку. Сделайте снимок кнопкой, касанием экрана или клавишей громкости. Проверьте резкость и края, затем используйте снимок или переснимите.',
      'listening' =>
        'Прослушивание. Нажмите строку расшифровки или кнопки плеера для перехода. Можно поставить закладку, изменить скорость и продолжить с сохранённого места.',
      'editing' =>
        'Исправление. В открытой лекции откройте расшифровку. Выберите фрагмент по номеру, поиску или командой последний фрагмент. Сверьте его с выделенной областью фото. Скажите замени текст, затем произнесите исправленную фразу. Скажите сохранить: сервер заново создаст аудио.',
      'connection' =>
        'Подключение. Телефон и ноутбук должны быть в одной сети. В настройках подключения введите только адрес ноутбука и нажмите Проверить связь. Обычный порт восемь тысяч уже указан. Для другого порта включите расширенный адрес.',
      _ =>
        'Справка Лектории. Начните со снимка конспекта. Проверьте расшифровку, затем слушайте лекцию и переходите между строками. Для выбора темы скажите: помощь команды, помощь съёмка, помощь прослушивание, помощь исправления или помощь подключение.',
    };
  }

  Future<void> _readAloud() async {
    final voice = _voice;
    if (voice == null) return;
    if (_reading) {
      _readingEpoch++;
      await voice.stopAnnouncement();
      if (mounted) setState(() => _reading = false);
      return;
    }
    final epoch = ++_readingEpoch;
    setState(() => _reading = true);
    try {
      if (_topic == 'commands') {
        await voice.announce(
            'Голосовые команды. Произносите по одной фразе после нажатия микрофона.',
            force: true);
        for (final category in [
          'Навигация',
          'Лекция',
          'Исправление',
          'Съёмка',
          'Настройки'
        ]) {
          if (!mounted || !_reading || epoch != _readingEpoch) break;
          final examples =
              voiceHelpExamples.where((item) => item.$1 == category);
          await voice.announce(
              '$category. ${examples.map((item) => '${item.$2}: ${item.$3}').join(' ')}',
              force: true);
        }
      } else {
        await voice.announce(_spokenContent(), force: true);
      }
    } finally {
      if (mounted && epoch == _readingEpoch) {
        setState(() => _reading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => VoicePage(
        onCommand: _command,
        child: PopScope(
          canPop: _topic == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _topic != null) _select(null);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_topic == null ? 'Помощь' : _topics[_topic]!.$1),
              leading: BackButton(onPressed: () {
                if (_topic == null) {
                  Navigator.of(context).pop();
                } else {
                  _select(null);
                }
              }),
              actions: [
                IconButton(
                  tooltip:
                      _reading ? 'Остановить чтение' : 'Прочитать раздел вслух',
                  onPressed: () => unawaited(_readAloud()),
                  icon: Icon(
                      _reading ? Icons.stop_rounded : Icons.volume_up_rounded),
                ),
              ],
            ),
            body: EditorialBackdrop(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: _topic == null
                          ? _overview(context)
                          : _details(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  List<Widget> _overview(BuildContext context) => [
        const EditorialHeading(
          kicker: 'первые шаги',
          title: 'Снимите. Проверьте. Слушайте.',
          subtitle:
              'Нажмите плюс внизу экрана, сфотографируйте конспект и проверьте снимок. После распознавания исправьте нужные строки и слушайте лекцию.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Голосом: «помощь команды», «помощь съёмка», «помощь прослушивание», «помощь исправления», «помощь подключение».',
        ),
        const SizedBox(height: 12),
        const Center(child: LectoriaSprite(pose: LectoriaPose.hint, size: 92)),
        const SizedBox(height: 12),
        for (final entry in _topics.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Icon(entry.value.$2, size: 32),
                title: Text(entry.value.$1,
                    style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text(entry.value.$3),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _select(entry.key),
              ),
            ),
          ),
      ];

  List<Widget> _details(BuildContext context) {
    final title = _topics[_topic]!.$1;
    final content = <Widget>[
      EditorialHeading(
        kicker: 'подробная справка',
        title: title,
        subtitle: _topics[_topic]!.$3,
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: () => unawaited(_readAloud()),
        icon: Icon(_reading ? Icons.stop_rounded : Icons.volume_up_rounded),
        label: Text(_reading ? 'Остановить чтение' : 'Прослушать этот раздел'),
      ),
      const SizedBox(height: 18),
    ];
    if (_topic == 'commands') {
      content.add(const Text(
        'Произносите одну фразу после нажатия «Сказать Лектории». Команды лекции работают, когда открыта лекция; команды съёмки — на соответствующем экране. После изменения настроек скажите «сохранить».',
      ));
      for (final category in [
        'Навигация',
        'Лекция',
        'Исправление',
        'Съёмка',
        'Настройки'
      ]) {
        content.add(Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(category, style: Theme.of(context).textTheme.titleLarge),
        ));
        for (final example
            in voiceHelpExamples.where((e) => e.$1 == category)) {
          content.add(Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: '«${example.$2}»\n',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: example.$3),
              ])),
            ),
          ));
        }
      }
    } else {
      content.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(_spokenContent(),
              style: Theme.of(context).textTheme.bodyLarge),
        ),
      ));
      if (_topic == 'capture') {
        content.add(const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
              'Подсказка камеры оценивает кадр приблизительно. Перед отправкой убедитесь, что текст виден и снимок не смазан.'),
        ));
      }
      if (_topic == 'connection') {
        content.add(const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
              'Если телефон не слышит команду, выберите распознавание на ноутбуке в настройках голоса. Для работы на телефоне нужна служба «Распознавание и синтез речи от Google».'),
        ));
      }
    }
    return content;
  }
}
