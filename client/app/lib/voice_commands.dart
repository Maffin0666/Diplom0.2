enum VoiceCommand { play, pause, next, previous, repeatFormula, unknown }

enum AppCommand {
  home,
  library,
  notes,
  settings,
  capture,
  usePhoto,
  camera,
  gallery,
  back,
  help,
  helpTopic,
  start,
  openLecture,
  fragment,
  firstFragment,
  lastFragment,
  dictate,
  removeFragment,
  restoreFragment,
  edit,
  save,
  bookmark,
  bookmarks,
  faster,
  slower,
  light,
  dark,
  contrast,
  larger,
  smaller,
  clearStorage,
  section,
  setOption,
  voiceMode,
  checkConnection,
  scrollUp,
  scrollDown,
  stopVoice,
  play,
  pause,
  next,
  previous,
  repeatFormula,
  explainFormula,
  unknown,
}

class AppVoiceIntent {
  const AppVoiceIntent(this.command,
      {this.number,
      this.section,
      this.option,
      this.enabled,
      this.value,
      this.utterance});
  final AppCommand command;
  final int? number;
  final String? section;
  final String? option;
  final bool? enabled;
  final String? value;

  /// Original recognized words, needed when the editor is taking dictation.
  final String? utterance;
}

const _numberWords = [
  'один',
  'два',
  'три',
  'четыре',
  'пять',
  'шесть',
  'семь',
  'восемь',
  'девять',
  'десять',
  'одиннадцать',
  'двенадцать',
  'тринадцать',
  'четырнадцать',
  'пятнадцать',
  'шестнадцать',
  'семнадцать',
  'восемнадцать',
  'девятнадцать',
  'двадцать'
];

AppVoiceIntent parseAppVoiceCommand(String words) {
  final text = words
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[.,!?]'), '')
      .trim();
  int? number = int.tryParse(RegExp(r'\d+').firstMatch(text)?.group(0) ?? '');
  final tokens = text.split(' ');
  if (number == null) {
    const tens = [
      'двадцать',
      'тридцать',
      'сорок',
      'пятьдесят',
      'шестьдесят',
      'семьдесят',
      'восемьдесят',
      'девяносто'
    ];
    for (var i = 0; i < tens.length; i++) {
      if (tokens.contains(tens[i])) {
        number = (i + 2) * 10;
        for (var unit = 0; unit < 9; unit++) {
          if (tokens.contains(_numberWords[unit])) number = number! + unit + 1;
        }
        break;
      }
    }
    for (var i = 18; number == null && i >= 0; i--) {
      if (tokens.contains(_numberWords[i])) number = i + 1;
    }
  }
  if (text == 'вниз' || text == 'прокрути вниз') {
    return const AppVoiceIntent(AppCommand.scrollDown);
  }
  if (text == 'вверх' || text == 'прокрути вверх') {
    return const AppVoiceIntent(AppCommand.scrollUp);
  }
  if (text == 'хватит' ||
      text == 'выключи голос' ||
      text == 'заверши управление') {
    return const AppVoiceIntent(AppCommand.stopVoice);
  }
  if (text.startsWith('помощь ') || text.startsWith('справка ')) {
    return AppVoiceIntent(AppCommand.helpTopic, section: text);
  }
  if (text == 'открой расшифровку' ||
      text == 'покажи расшифровку' ||
      text == 'открой текст лекции') {
    return const AppVoiceIntent(AppCommand.edit);
  }
  if (text.contains('распознавай на ноутбуке') ||
      text.contains('команды на ноутбуке')) {
    return const AppVoiceIntent(AppCommand.voiceMode, value: 'server');
  }
  if (text.contains('распознавай на телефоне') ||
      text.contains('команды на телефоне')) {
    return const AppVoiceIntent(AppCommand.voiceMode, value: 'android');
  }
  if (text.contains('распознавай автоматически')) {
    return const AppVoiceIntent(AppCommand.voiceMode, value: 'auto');
  }
  if (text == 'проверь связь' || text == 'проверить связь') {
    return const AppVoiceIntent(AppCommand.checkConnection);
  }
  final switchOn = text.startsWith('включи ') ||
      text.startsWith('показывай ') ||
      text.startsWith('включить ');
  final switchOff = text.startsWith('выключи ') ||
      text.startsWith('скрой ') ||
      text.startsWith('убери ') ||
      text.startsWith('отключи ');
  if (switchOn || switchOff) {
    const options = <String, List<String>>{
      'show_voice_dock': [
        'панель голоса',
        'голосовую панель',
        'панель микрофона'
      ],
      'spoken_hints': ['голосовые подсказки', 'озвучивание подсказок'],
      'haptics': ['вибрацию', 'виброотклик'],
      'earcons': ['звуковые сигналы', 'короткие звуки'],
      'auto_capture': ['автосъемку', 'автоматический снимок'],
      'camera_guidance': ['подсказки камеры', 'помощь камеры'],
      'continuous_voice': ['серию команд'],
      'auto_play': ['автовоспроизведение', 'автоматическое воспроизведение'],
      'show_mascot': ['лекторию', 'маскота'],
      'reading_guide': ['линейку чтения'],
      'bold_text': ['жирный текст'],
      'high_contrast': ['высокий контраст', 'контрастный режим'],
      'reduce_motion': ['уменьшение анимации', 'меньше движения'],
    };
    for (final entry in options.entries) {
      if (entry.value.any(text.contains)) {
        return AppVoiceIntent(AppCommand.setOption,
            option: entry.key, enabled: switchOn);
      }
    }
  }
  if (text.contains('открой лекцию') || text.startsWith('лекция ')) {
    return AppVoiceIntent(AppCommand.openLecture, number: number);
  }
  if (text == 'диктовать текст' ||
      text == 'замени текст' ||
      text == 'исправить текст голосом') {
    return const AppVoiceIntent(AppCommand.dictate);
  }
  if (text == 'удали фрагмент' || text == 'исключи фрагмент') {
    return const AppVoiceIntent(AppCommand.removeFragment);
  }
  if (text == 'верни фрагмент' || text == 'восстанови фрагмент') {
    return const AppVoiceIntent(AppCommand.restoreFragment);
  }
  if (text.contains('последн') && text.contains('фрагмент')) {
    return const AppVoiceIntent(AppCommand.lastFragment);
  }
  if (text.contains('перв') && text.contains('фрагмент')) {
    return const AppVoiceIntent(AppCommand.firstFragment);
  }
  if (text.contains('фрагмент') && number != null) {
    return AppVoiceIntent(AppCommand.fragment, number: number);
  }
  if (text.contains('главн') || text == 'домой') {
    return const AppVoiceIntent(AppCommand.home);
  }
  if (text.contains('библиотек')) {
    return const AppVoiceIntent(AppCommand.library);
  }
  if (text.contains('все заметки') ||
      text.contains('мои заметки') ||
      text.contains('все закладки')) {
    return const AppVoiceIntent(AppCommand.notes);
  }
  if (text.contains('настройк')) {
    return const AppVoiceIntent(AppCommand.settings);
  }
  if (text.contains('доступность') ||
      text.contains('оформление') ||
      text.contains('подключение') ||
      text.contains('голосовое управление') ||
      text.contains('хранилище') ||
      text.contains('озвучивание')) {
    return AppVoiceIntent(AppCommand.section, section: text);
  }
  if (text.contains('камера') || text.contains('открой камеру')) {
    return const AppVoiceIntent(AppCommand.camera);
  }
  if (text.contains('использовать снимок') ||
      text.contains('отправить снимок') ||
      text.contains('подтвердить снимок')) {
    return const AppVoiceIntent(AppCommand.usePhoto);
  }
  if (text.contains('сделай фото') ||
      text.contains('сфотографируй') ||
      text == 'снимок') {
    return const AppVoiceIntent(AppCommand.capture);
  }
  if (text.contains('переснять') || text.contains('другое фото')) {
    return const AppVoiceIntent(AppCommand.capture);
  }
  if (text.contains('галере')) return const AppVoiceIntent(AppCommand.gallery);
  if (text.contains('добавить лекцию') || text.contains('новая лекция')) {
    return const AppVoiceIntent(AppCommand.camera);
  }
  if (text == 'назад' || text == 'закрыть' || text == 'отмена') {
    return const AppVoiceIntent(AppCommand.back);
  }
  if (text == 'справка' ||
      text.contains('помощь') ||
      text.contains('список команд')) {
    return const AppVoiceIntent(AppCommand.help);
  }
  if (text == 'начать') return const AppVoiceIntent(AppCommand.start);
  if (text.contains('исправить') || text.contains('редактировать')) {
    return const AppVoiceIntent(AppCommand.edit);
  }
  if (text.contains('разбери формулу') ||
      text.contains('объясни формулу') ||
      text.contains('покажи формулу') ||
      text.contains('разбор формулы')) {
    return const AppVoiceIntent(AppCommand.explainFormula);
  }
  if (text.contains('сохранить')) return const AppVoiceIntent(AppCommand.save);
  if (text.contains('освободить место') ||
      text.contains('очистить старые записи')) {
    return const AppVoiceIntent(AppCommand.clearStorage);
  }
  if (text.contains('закладк')) {
    if (text == 'закладки' ||
        text.contains('список') ||
        text.contains('открой') ||
        text.contains('покажи')) {
      return const AppVoiceIntent(AppCommand.bookmarks);
    }
    return AppVoiceIntent(AppCommand.bookmark, number: number);
  }
  if (text.contains('быстрее')) return const AppVoiceIntent(AppCommand.faster);
  if (text.contains('медленнее')) {
    return const AppVoiceIntent(AppCommand.slower);
  }
  if (text.contains('светлая тема')) {
    return const AppVoiceIntent(AppCommand.light);
  }
  if (text.contains('темная тема')) {
    return const AppVoiceIntent(AppCommand.dark);
  }
  if (text.contains('контраст')) {
    return const AppVoiceIntent(AppCommand.contrast);
  }
  if (text.contains('крупнее') || text.contains('увеличить текст')) {
    return const AppVoiceIntent(AppCommand.larger);
  }
  if (text.contains('мельче') || text.contains('уменьшить текст')) {
    return const AppVoiceIntent(AppCommand.smaller);
  }
  final playback = parseVoiceCommand(text);
  return AppVoiceIntent(switch (playback) {
    VoiceCommand.play => AppCommand.play,
    VoiceCommand.pause => AppCommand.pause,
    VoiceCommand.next => AppCommand.next,
    VoiceCommand.previous => AppCommand.previous,
    VoiceCommand.repeatFormula => AppCommand.repeatFormula,
    VoiceCommand.unknown => AppCommand.unknown,
  });
}

VoiceCommand parseVoiceCommand(String words) {
  final text = words.toLowerCase().replaceAll('ё', 'е').trim();
  if (text.contains('повтори формул') ||
      text.contains('повторить формул') ||
      text.contains('формулу еще раз')) {
    return VoiceCommand.repeatFormula;
  }
  if (text.contains('следующ') || text.contains('дальше')) {
    return VoiceCommand.next;
  }
  if (text.contains('предыдущ') || text.contains('назад')) {
    return VoiceCommand.previous;
  }
  if (text.contains('пауз') || text.contains('останови') || text == 'стоп') {
    return VoiceCommand.pause;
  }
  if (text.contains('воспроизвед') ||
      text.contains('воспроизвести') ||
      text.contains('включи') ||
      text.contains('продолжи') ||
      text.contains('слушать')) {
    return VoiceCommand.play;
  }
  return VoiceCommand.unknown;
}
