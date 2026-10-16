import 'package:flutter/material.dart';
import 'app_haptics.dart';
import 'api.dart';
import 'app_preferences.dart';
import 'app_theme.dart';
import 'voice_navigation.dart';
import 'voice_commands.dart';
import 'lektoria_sprite.dart';
import 'visual_system.dart';
import 'user_error.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {super.key,
      required this.server,
      required this.theme,
      required this.scale,
      required this.onSave,
      this.preferences = const AppPreferences(),
      this.onSaveAll,
      this.themePreview,
      this.unusedAudioBytes,
      this.clearUnusedAudio});
  final String server;
  final ThemeMode theme;
  final double scale;
  final AppPreferences preferences;
  final Future<void> Function(String, ThemeMode, double) onSave;
  final Future<void> Function(String, ThemeMode, double, AppPreferences)?
      onSaveAll;
  final ValueNotifier<ThemeData?>? themePreview;
  final Future<int> Function()? unusedAudioBytes;
  final Future<int> Function()? clearUnusedAudio;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _address = TextEditingController(text: widget.server);
  late final _host =
      TextEditingController(text: Uri.tryParse(widget.server)?.host ?? '');
  late bool _advancedAddress = _needsAdvancedAddress(widget.server);
  late ThemeMode _theme = widget.theme;
  late double _scale = widget.scale;
  late final Map<String, dynamic> _draft = widget.preferences.toJson();
  final _scroll = ScrollController();
  Future<int>? _unusedAudio;
  String? _section;
  void _selectSection(String? section) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _section = section);
  }

  String _message = '';
  bool _busy = false;
  static bool _needsAdvancedAddress(String address) {
    if (address.isEmpty) return false;
    final uri = Uri.tryParse(address);
    return uri == null || uri.scheme != 'http' || uri.port != 8000;
  }

  String _effectiveAddress() {
    if (_advancedAddress) return _address.text.trim();
    final host = _host.text.trim();
    if (host.isEmpty) return '';
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.-]*$').hasMatch(host)) {
      throw const FormatException(
          'Введите только IP-адрес или имя ноутбука без порта');
    }
    return 'http://$host:8000';
  }

  static const _sections = {
    'Оформление': (Icons.palette_outlined, 'Тема и размер текста'),
    'Доступность': (
      Icons.accessibility_new_rounded,
      'Контраст, жирный текст, движение и отклик'
    ),
    'Озвучивание': (Icons.headphones_rounded, 'Скорость и запуск лекции'),
    'Голосовое управление': (
      Icons.mic_none_rounded,
      'Служба, серия команд и подсказки'
    ),
    'Камера': (Icons.center_focus_strong_rounded, 'Подсказки при наведении'),
    'Подключение': (Icons.wifi_rounded, 'Адрес ноутбука и проверка связи'),
    'Хранилище': (Icons.storage_rounded, 'Старые версии озвучки'),
  };

  @override
  void initState() {
    super.initState();
    _unusedAudio = widget.unusedAudioBytes?.call();
  }

  Future<void> _clearAudio() async {
    if (widget.clearUnusedAudio == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => VoicePage(
        onCommand: (intent) async {
          if (intent.command == AppCommand.clearStorage ||
              intent.command == AppCommand.save) {
            Navigator.of(dialogContext).pop(true);
            return true;
          }
          if (intent.command == AppCommand.back) {
            Navigator.of(dialogContext).pop(false);
            return true;
          }
          return false;
        },
        child: AlertDialog(
          title: const Text('Освободить место?'),
          content: const Text(
              'Удалятся только старые версии озвучки. Текущие лекции и их снимки сохранятся.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Очистить')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final freed = await widget.clearUnusedAudio!();
      if (mounted) {
        setState(() {
          _unusedAudio = widget.unusedAudioBytes?.call();
          _message = freed == 0
              ? 'Старых записей нет'
              : 'Место освобождено. Ваши лекции сохранены.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = userError(error));
    }
  }

  @override
  void dispose() {
    widget.themePreview?.value = null;
    _address.dispose();
    _host.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final address = _effectiveAddress();
      if (address.isNotEmpty) {
        RecognitionApi.parseServerAddress(address);
      }
      if (widget.onSaveAll != null) {
        await widget.onSaveAll!(
            address, _theme, _scale, AppPreferences.fromJson(_draft));
      } else {
        await widget.onSave(address, _theme, _scale);
      }
      if (mounted) Navigator.of(context).pop();
      return true;
    } catch (error) {
      if (mounted) setState(() => _message = userError(error));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _message = '';
    });
    RecognitionApi? api;
    try {
      api = RecognitionApi(_effectiveAddress());
      await api.checkHealth();
      if (mounted) setState(() => _message = 'Сервер готов к работе');
    } catch (error) {
      if (mounted) setState(() => _message = userError(error));
    } finally {
      api?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _command(AppVoiceIntent intent) async {
    switch (intent.command) {
      case AppCommand.camera:
        _selectSection('Камера');
        return true;
      case AppCommand.section:
        for (final title in _sections.keys) {
          if (intent.section?.contains(title.toLowerCase()) == true) {
            _selectSection(title);
            return true;
          }
        }
        return false;
      case AppCommand.clearStorage:
        await _clearAudio();
        return true;
      case AppCommand.back:
        if (_section == null) return false;
        _selectSection(null);
        return true;
      case AppCommand.save:
        if (await _save()) {
          return true;
        }
        throw VoiceActionFeedback(_message.isEmpty
            ? 'Настройки не сохранены. Повторите попытку.'
            : _message);
      case AppCommand.light:
        setState(() => _theme = ThemeMode.light);
        return true;
      case AppCommand.dark:
        setState(() => _theme = ThemeMode.dark);
        return true;
      case AppCommand.contrast:
        setState(() => _draft['high_contrast'] = true);
        return true;
      case AppCommand.larger:
        setState(() => _scale = (_scale + .1).clamp(.8, 3));
        return true;
      case AppCommand.smaller:
        setState(() => _scale = (_scale - .1).clamp(.8, 3));
        return true;
      case AppCommand.setOption:
        if (intent.option == null ||
            intent.enabled == null ||
            _draft[intent.option] is! bool) {
          return false;
        }
        setState(() => _draft[intent.option!] = intent.enabled);
        return true;
      case AppCommand.voiceMode:
        if (!['auto', 'android', 'server'].contains(intent.value)) return false;
        setState(() => _draft['voice_mode'] = intent.value);
        return true;
      case AppCommand.checkConnection:
        await _check();
        if (_message != 'Сервер готов к работе') {
          throw VoiceActionFeedback(_message);
        }
        return true;
      default:
        return false;
    }
  }

  Widget _toggle(String key, String title, String subtitle) =>
      SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        title: Text(title),
        subtitle: Text(subtitle),
        value: _draft[key] == true,
        onChanged: _busy ? null : (v) => setState(() => _draft[key] = v),
      );

  List<Widget> _content(BuildContext context) => switch (_section) {
        'Оформление' => [
            for (final choice in [
              (
                ThemeMode.system,
                'Как на устройстве',
                Icons.brightness_auto_rounded
              ),
              (ThemeMode.light, 'Светлая', Icons.light_mode_rounded),
              (ThemeMode.dark, 'Тёмная', Icons.dark_mode_rounded)
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _themeChoice(context, choice.$1, choice.$2, choice.$3),
              ),
            const SizedBox(height: 20),
            Text('Размер текста: ${(_scale * 100).round()}%',
                style: Theme.of(context).textTheme.titleMedium),
            Row(children: [
              IconButton.outlined(
                  tooltip: 'Уменьшить текст',
                  onPressed: _scale <= .8
                      ? null
                      : () =>
                          setState(() => _scale = (_scale - .1).clamp(.8, 3)),
                  icon: const Icon(Icons.remove)),
              Expanded(
                  child: Slider(
                      value: _scale,
                      min: .8,
                      max: 3,
                      divisions: 22,
                      onChanged: (v) => setState(() => _scale = v))),
              IconButton.outlined(
                  tooltip: 'Увеличить текст',
                  onPressed: _scale >= 3
                      ? null
                      : () =>
                          setState(() => _scale = (_scale + .1).clamp(.8, 3)),
                  icon: const Icon(Icons.add)),
            ]),
            Text('Лекция начинается с вас',
                style: TextStyle(fontSize: 18 * _scale)),
            const SizedBox(height: 8),
            const Text('Системное увеличение текста тоже учитывается.'),
          ],
        'Доступность' => [
            _toggle('high_contrast', 'Высокая контрастность',
                'Чёрный или белый фон, отчётливые границы, контрастные подписи.'),
            Text('Цветовая палитра',
                style: Theme.of(context).textTheme.titleMedium),
            for (final choice in [
              ('standard', 'Обычная'),
              ('black_yellow', 'Чёрная и жёлтая'),
              ('inverse', 'Инверсная'),
              ('monochrome', 'Монохромная'),
              ('protanopia', 'Для протанопии'),
              ('deuteranopia', 'Для дейтеранопии'),
              ('tritanopia', 'Для тританопии'),
            ])
              ListTile(
                title: Text(choice.$2),
                leading: Icon(_draft['palette'] == choice.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                onTap: () => setState(() => _draft['palette'] = choice.$1),
              ),
            _toggle('bold_text', 'Жирный текст',
                'Усилить начертание подписей и текста лекций.'),
            _toggle('reduce_motion', 'Меньше движения',
                'Отключить анимацию Лектории и переходов.'),
            SwitchListTile.adaptive(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              title: const Text('Отключить маскота'),
              subtitle:
                  const Text('Скрыть спрайты Лектории во всём приложении.'),
              value: _draft['show_mascot'] == false,
              onChanged: _busy
                  ? null
                  : (disabled) =>
                      setState(() => _draft['show_mascot'] = !disabled),
            ),
            _toggle('reading_guide', 'Линейка чтения',
                'Приглушать соседние строки и выделять текущий фрагмент.'),
            const SizedBox(height: 14),
            Text('Шрифт для чтения',
                style: Theme.of(context).textTheme.titleMedium),
            for (final choice in [
              ('system', 'Системный'),
              ('open_dyslexic', 'OpenDyslexic'),
              ('atkinson', 'Atkinson Hyperlegible Next (латиница)'),
            ])
              ListTile(
                title: Text(choice.$2),
                leading: Icon(_draft['font_mode'] == choice.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                onTap: () => setState(() => _draft['font_mode'] = choice.$1),
              ),
            const Text(
                'Atkinson Hyperlegible Next пока не содержит кириллицу: русский текст останется системным. OpenDyslexic поддерживает русский текст.'),
            Text(
                'Расстояние между буквами: ${(_draft['letter_spacing'] as num).toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: (_draft['letter_spacing'] as num).toDouble(),
              min: 0,
              max: 3,
              divisions: 12,
              onChanged: (v) => setState(() => _draft['letter_spacing'] = v),
            ),
            Text(
                'Интервал между строками: ${(_draft['line_height'] as num).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: (_draft['line_height'] as num).toDouble(),
              min: 1.2,
              max: 2,
              divisions: 8,
              onChanged: (v) => setState(() => _draft['line_height'] = v),
            ),
            _toggle('haptics', 'Тактильный отклик',
                'Вибрация при действиях, переходах и обнаружении строк камерой.'),
            _toggle('earcons', 'Звуковые сигналы',
                'Короткие звуки при готовности кадра, ошибке и переходе к формуле.'),
            OutlinedButton.icon(
              onPressed: _draft['haptics'] == true
                  ? () async {
                      final accepted = await AppHaptics.vibrate(test: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(accepted
                                  ? 'Сигнал отправлен. Если вибрации нет, проверьте в Android: Настройки → Звуки и вибрация → Вибрация.'
                                  : 'Телефон не принял сигнал вибрации. Проверьте Настройки → Звуки и вибрация → Вибрация и перезапустите приложение.')),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.vibration_rounded),
              label: const Text('Проверить вибрацию'),
            ),
            const Text(
                'Все основные кнопки подписаны для TalkBack. В Android: Настройки → Специальные возможности → TalkBack. Голосовая кнопка остаётся на каждом экране.'),
          ],
        'Озвучивание' => [
            Text(
                'Начальная скорость: ${(_draft['playback_speed'] as num).toStringAsFixed(2)}×',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
                value: (_draft['playback_speed'] as num).toDouble(),
                min: .75,
                max: 3,
                divisions: 9,
                onChanged: (v) => setState(() => _draft['playback_speed'] = v)),
            _toggle('auto_play', 'Начинать автоматически',
                'Воспроизводить лекцию после загрузки аудио.'),
            const Text(
                'Скорость также можно менять в плеере. Исправление расшифровки создаёт новую озвучку с метками переходов.'),
          ],
        'Голосовое управление' => [
            _toggle('show_voice_dock', 'Показывать голосовую панель',
                'Скрыть нижнюю кнопку микрофона, если вы не используете голосовое управление.'),
            Text('Где распознавать команды',
                style: Theme.of(context).textTheme.titleMedium),
            for (final choice in [
              ('auto', 'Автоматически'),
              ('android', 'На телефоне'),
              ('server', 'На ноутбуке')
            ])
              ListTile(
                  title: Text(choice.$2),
                  leading: Icon(_draft['voice_mode'] == choice.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  onTap: () =>
                      setState(() => _draft['voice_mode'] = choice.$1)),
            _toggle('continuous_voice', 'Серия команд',
                'После выполненной команды слушать следующую. Запуск кнопкой микрофона; остановка повторным нажатием.'),
            _toggle('spoken_hints', 'Голосовые подсказки',
                'Произносить результат навигации и подсказки камеры. При использовании TalkBack можно выключить.'),
            Text(
                'Длительность команды на ноутбуке: ${_draft['command_seconds']} с'),
            Slider(
                value: (_draft['command_seconds'] as num).toDouble(),
                min: 3,
                max: 8,
                divisions: 5,
                onChanged: (v) =>
                    setState(() => _draft['command_seconds'] = v.round())),
            const Text(
                'Для Android установите или включите «Распознавание и синтез речи от Google» (Speech Recognition & Synthesis). На Galaxy: Настройки → Общие настройки → Список клавиатур и клавиатура по умолчанию → Голосовой ввод Google. Для работы через ноутбук нужна связь с сервером; интернет после установки модели Vosk не требуется.'),
          ],
        'Камера' => [
            _toggle('auto_capture', 'Автоматический снимок',
                'Снимать страницу после устойчивого обнаружения текста и неподвижного кадра. Можно выключить для ручного контроля.'),
            _toggle('camera_guidance', 'Помогать при наведении',
                'Искать структуру строк внутри рамки и сообщать о ней звуком и вибрацией.'),
            const Text(
                'Отклик помогает навести камеру. Он не гарантирует резкость, полноту страницы или точность распознавания. Держите страницу ровно и избегайте бликов.'),
          ],
        'Подключение' => [
            TextField(
                controller: _advancedAddress ? _address : _host,
                keyboardType:
                    _advancedAddress ? TextInputType.url : TextInputType.text,
                autocorrect: false,
                decoration: InputDecoration(
                    labelText: _advancedAddress
                        ? 'Полный адрес сервера'
                        : 'Адрес сервера',
                    hintText: _advancedAddress
                        ? 'http://192.168.1.5:8000'
                        : '192.168.1.5',
                    prefixText: _advancedAddress ? null : 'http://',
                    suffixText: _advancedAddress ? null : ':8000',
                    helperText:
                        'Телефон и ноутбук должны быть в одной сети Wi-Fi')),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Расширенный адрес'),
              subtitle: const Text(
                  'Включите, только если сервер использует другой порт или HTTPS.'),
              value: _advancedAddress,
              onChanged: (value) => setState(() {
                if (value && !_advancedAddress) {
                  _address.text = _host.text.trim().isEmpty
                      ? ''
                      : 'http://${_host.text.trim()}:8000';
                } else if (!value && _advancedAddress) {
                  _host.text = Uri.tryParse(_address.text)?.host ?? '';
                }
                _advancedAddress = value;
              }),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: _busy ? null : _check,
                icon: const Icon(Icons.wifi_find),
                label: const Text('Проверить связь')),
          ],
        'Хранилище' => [
            const Text(
                'Исправления расшифровки создают новые аудиозаписи. Прежние версии можно убрать, когда они больше не нужны.'),
            const SizedBox(height: 16),
            if (_unusedAudio != null)
              FutureBuilder<int>(
                future: _unusedAudio,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text('Считаем старые записи…');
                  }
                  final mb = snapshot.data! / (1024 * 1024);
                  return Text('Старые записи: ${mb.toStringAsFixed(1)} МБ',
                      style: Theme.of(context).textTheme.titleMedium);
                },
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.clearUnusedAudio == null ? null : _clearAudio,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Освободить место'),
            ),
            const Text('Текущие аудиозаписи, снимки и заметки сохраняются.'),
          ],
        _ => [
            for (final item in _sections.entries.toList().asMap().entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: _sectionTile(context, item.key + 1, item.value.key,
                    item.value.value.$1, item.value.value.$2),
              ),
          ],
      };

  Widget _themeChoice(
      BuildContext context, ThemeMode mode, String label, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    final selected = _theme == mode;
    final swatch = mode == ThemeMode.dark
        ? const Color(0xFF20284D)
        : mode == ThemeMode.light
            ? const Color(0xFFF8F5EF)
            : const Color(0xFF7370A9);
    return Semantics(
      button: true,
      selected: selected,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => setState(() => _theme = mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Icon(icon,
                    color: mode == ThemeMode.light
                        ? const Color(0xFF30366B)
                        : Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.titleMedium)),
              Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? colors.primary : colors.outline),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sectionTile(BuildContext context, int number, String title,
      IconData icon, String detail) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectSection(title),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
          child: Row(children: [
            Text(number.toString().padLeft(2, '0'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.secondary, fontWeight: FontWeight.w800)),
            const SizedBox(width: 14),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                    bottomLeft: Radius.circular(4)),
              ),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(width: 13),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant)),
              ],
            )),
            const SizedBox(width: 3),
            Icon(Icons.arrow_forward_rounded, color: colors.primary),
          ]),
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 13, 15),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
            bottomRight: Radius.circular(26),
            bottomLeft: Radius.circular(7)),
      ),
      child: Row(children: [
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionKicker('предпросмотр'),
            const SizedBox(height: 8),
            Text('Читать и слушать удобно',
                style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontSize: 17 * _scale,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('Тема и размер видны сразу. Сохраните выбор внизу экрана.',
                style: TextStyle(color: colors.onPrimaryContainer)),
          ],
        )),
        const SizedBox(width: 7),
        const LectoriaSprite(pose: LectoriaPose.listening, size: 74),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _theme == ThemeMode.dark ||
        (_theme == ThemeMode.system &&
            Theme.of(context).brightness == Brightness.dark);
    final preview = dark
        ? AppTheme.dark(
            highContrast: _draft['high_contrast'] == true,
            boldText: _draft['bold_text'] == true,
            palette: _draft['palette'] as String,
            fontMode: _draft['font_mode'] as String,
            letterSpacing: (_draft['letter_spacing'] as num).toDouble(),
            lineHeight: (_draft['line_height'] as num).toDouble())
        : AppTheme.light(
            highContrast: _draft['high_contrast'] == true,
            boldText: _draft['bold_text'] == true,
            palette: _draft['palette'] as String,
            fontMode: _draft['font_mode'] as String,
            letterSpacing: (_draft['letter_spacing'] as num).toDouble(),
            lineHeight: (_draft['line_height'] as num).toDouble());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.themePreview != null &&
          (widget.themePreview!.value?.colorScheme != preview.colorScheme ||
              widget.themePreview!.value?.textTheme != preview.textTheme)) {
        widget.themePreview?.value = preview;
      }
    });
    return VoicePage(
        scrollController: _scroll,
        onCommand: _command,
        child: PreferencesScope(
          preferences: AppPreferences.fromJson(_draft),
          child: Theme(
            data: preview,
            child: Builder(
                builder: (context) => PopScope(
                      canPop: _section == null,
                      onPopInvokedWithResult: (didPop, _) {
                        if (!didPop && _section != null) _selectSection(null);
                      },
                      child: Scaffold(
                        appBar: AppBar(
                            title: Text(_section ?? 'Настройки',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            leading: BackButton(onPressed: () {
                              if (_section != null) {
                                _selectSection(null);
                              } else {
                                Navigator.of(context).pop();
                              }
                            })),
                        body: EditorialBackdrop(
                            child: SafeArea(
                                child: Center(
                                    child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 720),
                                        child: ListView(
                                          controller: _scroll,
                                          padding: const EdgeInsets.fromLTRB(
                                              20, 12, 20, 24),
                                          children: [
                                            if (_section == null) ...[
                                              const EditorialHeading(
                                                kicker: 'ваш способ учиться',
                                                title: 'Подстроим под вас',
                                                subtitle:
                                                    'Выберите раздел. Изменения применятся после сохранения.',
                                              ),
                                              const SizedBox(height: 20),
                                              _preview(context),
                                              const SizedBox(height: 23),
                                              const SectionKicker('разделы'),
                                              const SizedBox(height: 11),
                                            ] else ...[
                                              EditorialHeading(
                                                kicker:
                                                    'настройки / ${_sections.keys.toList().indexOf(_section!) + 1}',
                                                title: _section!,
                                                subtitle:
                                                    _sections[_section!]?.$2,
                                              ),
                                              const SizedBox(height: 23),
                                            ],
                                            ..._content(context),
                                            const SizedBox(height: 22),
                                            if (_message.isNotEmpty)
                                              _message ==
                                                      'Сервер готов к работе'
                                                  ? Text(_message,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium)
                                                  : ErrorNotice(
                                                      message: _message),
                                          ],
                                        ))))),
                        bottomNavigationBar: SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              border: Border(
                                  top: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant)),
                            ),
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _save,
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Сохранить настройки'),
                            ),
                          ),
                        ),
                      ),
                    )),
          ),
        ));
  }
}
