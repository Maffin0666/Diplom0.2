import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'app_theme.dart';
import 'brand.dart';
import 'capture_page.dart';
import 'home_page.dart';
import 'lecture_view.dart';
import 'models.dart';
import 'speech_diagnostics.dart';
import 'storage.dart';
import 'voice_commands.dart';
import 'welcome_page.dart';

// The speech plugin keeps native callbacks after initialize(). Reuse one
// instance and route callbacks to the currently visible lecture screen.
final stt.SpeechToText _sharedSpeech = stt.SpeechToText();
bool _sharedSpeechReady = false;
void Function(String)? _speechStatusHandler;
void Function(String)? _speechErrorHandler;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LectureReaderApp());
}

class LectureReaderApp extends StatefulWidget {
  const LectureReaderApp({super.key});

  @override
  State<LectureReaderApp> createState() => _LectureReaderAppState();
}

class _LectureReaderAppState extends State<LectureReaderApp> {
  final _picker = ImagePicker();
  LectureStorage? _storage;
  List<LectureRecord> _records = [];
  String _server = '';
  String _loadError = '';
  ThemeMode _theme = ThemeMode.system;
  double _textScale = 1;
  bool _welcomeDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final storage = await LectureStorage.open();
      final settings = await storage.readSettings();
      final records = await storage.readAll();
      final lost = await _picker.retrieveLostData();
      if (!lost.isEmpty && lost.files != null && lost.files!.isNotEmpty) {
        final address = settings['server'] as String? ?? '';
        if (address.isNotEmpty) {
          final recovered =
              await _makeRecord(storage, address, lost.files!.first);
          records.insert(0, recovered);
          await storage.saveAll(records);
        }
      }
      if (!mounted) return;
      setState(() {
        _storage = storage;
        _records = records;
        _server = settings['server'] as String? ?? '';
        _theme = ThemeMode.values.firstWhere(
          (mode) => mode.name == settings['theme'],
          orElse: () => ThemeMode.system,
        );
        _textScale = ((settings['text_scale'] as num?)?.toDouble() ?? 1)
            .clamp(1.0, 2.0)
            .toDouble();
        _welcomeDone = settings['welcome_done'] == true;
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _loadError = 'Не удалось открыть локальные данные: $error');
      }
    }
  }

  Future<void> _saveSettings(
      String server, ThemeMode theme, double scale) async {
    RecognitionApi.parseServerAddress(server);
    await _storage!.saveSettings({
      'server': server.trim(),
      'theme': theme.name,
      'text_scale': scale,
      'welcome_done': _welcomeDone,
    });
    setState(() {
      _server = server.trim();
      _theme = theme;
      _textScale = scale;
    });
  }

  Future<LectureRecord> _makeRecord(
      LectureStorage storage, String server, XFile image) async {
    final taskId = const Uuid().v4();
    final path = await storage.saveImage(taskId, image);
    return LectureRecord(
      taskId: taskId,
      serverBase: server,
      imagePath: path,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _persist() async {
    await _storage!.saveAll(_records);
    if (mounted) {
      setState(
          () => _records.sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    }
  }

  Future<void> _pickAndOpen(BuildContext context, ImageSource source) async {
    if (_server.isEmpty) {
      _showMessage(context, 'Сначала укажите адрес сервера в настройках');
      return;
    }
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 3000,
        maxHeight: 3000,
        imageQuality: 88,
        requestFullMetadata: false,
      );
      if (image == null || !context.mounted) return;
      final record = await _makeRecord(_storage!, _server, image);
      _records.insert(0, record);
      await _persist();
      if (context.mounted) _open(context, record);
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, 'Не удалось выбрать снимок: $error');
      }
    }
  }

  Future<void> _retryFailed(BuildContext context, LectureRecord old) async {
    try {
      if (!await File(old.imagePath).exists()) {
        throw const FileSystemException('Снимок больше не сохранён');
      }
      final record = await _makeRecord(
        _storage!,
        old.serverBase,
        XFile(old.imagePath),
      );
      _records.insert(0, record);
      await _persist();
      if (context.mounted) {
        final navigator = Navigator.of(context);
        navigator.pop();
        _pushLecture(navigator, record);
      }
    } catch (error) {
      if (context.mounted) _showMessage(context, 'Повтор не удался: $error');
    }
  }

  void _open(BuildContext context, LectureRecord record) {
    _pushLecture(Navigator.of(context), record);
  }

  void _pushLecture(NavigatorState navigator, LectureRecord record) {
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => LecturePage(
        record: record,
        storage: _storage!,
        onChanged: _persist,
        onRetryFailed: (pageContext) => _retryFailed(pageContext, record),
      ),
    ));
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finishWelcome() async {
    await _storage!.saveSettings({
      'server': _server,
      'theme': _theme.name,
      'text_scale': _textScale,
      'welcome_done': true,
    });
    if (mounted) setState(() => _welcomeDone = true);
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        server: _server,
        theme: _theme,
        scale: _textScale,
        onSave: _saveSettings,
      ),
    ));
  }

  void _openCapture(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (captureContext) => CapturePage(
        onCamera: () => _pickAndOpen(captureContext, ImageSource.camera),
        onGallery: () => _pickAndOpen(captureContext, ImageSource.gallery),
      ),
    ));
  }

  Future<void> _deleteRecord(LectureRecord record) async {
    final previous = List<LectureRecord>.from(_records);
    _records.remove(record);
    try {
      await _persist();
      for (final path in [record.imagePath, record.audioPath]) {
        if (path.isNotEmpty) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      }
    } catch (_) {
      _records = previous;
      await _persist();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Лектория.Ai',
      debugShowCheckedModeBanner: false,
      themeMode: _theme,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            (MediaQuery.textScalerOf(context).scale(1) * _textScale)
                .clamp(1.0, 2.5),
          ),
        ),
        child: child!,
      ),
      home: Builder(builder: (context) {
        if (_loadError.isNotEmpty) {
          return Scaffold(
              body: Center(
                  child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_loadError),
          )));
        }
        if (_storage == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (!_welcomeDone) {
          return WelcomePage(
            onStart: () =>
                unawaited(_finishWelcome().catchError((Object error) {
              if (context.mounted) {
                _showMessage(context, 'Не удалось сохранить настройки: $error');
              }
            })),
            onSettings: () => _openSettings(context),
          );
        }
        return HomePage(
          records: _records,
          serverConfigured: _server.isNotEmpty,
          onOpen: (record) => _open(context, record),
          onCapture: () => _openCapture(context),
          onSettings: () => _openSettings(context),
          onDelete: _deleteRecord,
        );
      }),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton(
      {required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton.icon(
            onPressed: onPressed, icon: Icon(icon), label: Text(label)),
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {super.key,
      required this.server,
      required this.theme,
      required this.scale,
      required this.onSave});
  final String server;
  final ThemeMode theme;
  final double scale;
  final Future<void> Function(String, ThemeMode, double) onSave;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _address =
      TextEditingController(text: widget.server);
  late ThemeMode _theme = widget.theme;
  late double _scale = widget.scale;
  String _message = '';
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final api = RecognitionApi(_address.text);
      try {
        await api.checkHealth();
      } finally {
        api.close();
      }
      if (mounted) setState(() => _message = 'Сервер готов к работе');
    } catch (error) {
      if (mounted) setState(() => _message = 'Нет связи: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await widget.onSave(_address.text, _theme, _scale);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Настройки',
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(children: [
                  const LectoriaMascot(size: 72),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('Подстройте приложение под себя',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                              ))),
                ]),
                const SizedBox(height: 8),
                Text('Подключение и оформление можно изменить в любой момент.',
                    style: TextStyle(color: colors.onSurfaceVariant)),
                const SizedBox(height: 26),
                Text('Подключение',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _address,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Адрес сервера',
                            hintText: 'http://192.168.1.5:8000',
                            helperText: 'Адрес ноутбука в той же Wi-Fi-сети',
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _check,
                            icon: const Icon(Icons.wifi_find_rounded),
                            label: const Text('Проверить связь'),
                          ),
                        ),
                        if (_message.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Semantics(
                            liveRegion: true,
                            child: Text(_message,
                                style: TextStyle(
                                    color: _message.startsWith('Нет связи')
                                        ? colors.error
                                        : colors.primary)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text('Оформление',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Цветовая тема',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _ThemeChoice(
                          label: 'Как на устройстве',
                          icon: Icons.brightness_auto_rounded,
                          selected: _theme == ThemeMode.system,
                          onTap: () =>
                              setState(() => _theme = ThemeMode.system),
                        ),
                        const SizedBox(height: 8),
                        _ThemeChoice(
                          label: 'Светлая',
                          icon: Icons.light_mode_rounded,
                          selected: _theme == ThemeMode.light,
                          onTap: () => setState(() => _theme = ThemeMode.light),
                        ),
                        const SizedBox(height: 8),
                        _ThemeChoice(
                          label: 'Тёмная',
                          icon: Icons.dark_mode_rounded,
                          selected: _theme == ThemeMode.dark,
                          onTap: () => setState(() => _theme = ThemeMode.dark),
                        ),
                        const SizedBox(height: 24),
                        Text('Размер текста: ${(_scale * 100).round()}%',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('Дополнительное увеличение поверх системного.',
                            style: TextStyle(color: colors.onSurfaceVariant)),
                        Slider(
                          value: _scale,
                          min: 1,
                          max: 2.0,
                          divisions: 10,
                          label: '${(_scale * 100).round()}%',
                          onChanged: (value) => setState(() => _scale = value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                _WideButton(
                  icon: Icons.check_rounded,
                  label: 'Сохранить настройки',
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label тема',
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 14),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              if (selected)
                Icon(Icons.check_circle_rounded, color: colors.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

class LecturePage extends StatefulWidget {
  const LecturePage(
      {super.key,
      required this.record,
      required this.storage,
      required this.onChanged,
      required this.onRetryFailed});
  final LectureRecord record;
  final LectureStorage storage;
  final Future<void> Function() onChanged;
  final void Function(BuildContext) onRetryFailed;

  @override
  State<LecturePage> createState() => _LecturePageState();
}

class _LecturePageState extends State<LecturePage> {
  final AudioPlayer _player = AudioPlayer();
  final stt.SpeechToText _speech = _sharedSpeech;
  RecognitionApi? _api;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  bool _audioReady = false;
  bool _uploaded = false;
  bool _listening = false;
  bool _commandHandled = false;
  bool _closed = false;
  double _speed = 1.0;
  String _message = '';
  String _error = '';

  LectureRecord get record => widget.record;
  LectureManifest? get manifest => record.manifest;

  @override
  void initState() {
    super.initState();
    _positionSubscription = _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    unawaited(_resume());
  }

  @override
  void dispose() {
    _closed = true;
    _api?.close();
    _speechStatusHandler = null;
    _speechErrorHandler = null;
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    if (_sharedSpeechReady && _speech.isListening) unawaited(_speech.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  void _notice(String value) {
    if (mounted) setState(() => _message = value);
  }

  Future<void> _resume() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (record.manifestJson?['status'] == 'completed' &&
          record.audioPath.isNotEmpty &&
          await File(record.audioPath).exists()) {
        await _loadAudio();
        return;
      }
      _api ??= RecognitionApi(record.serverBase);
      if (record.manifestJson?['status'] != 'completed') {
        _notice('Проверяем состояние задачи');
        String status;
        try {
          status = await _api!.status(record.taskId);
          if (mounted) setState(() => _uploaded = true);
        } on ApiException catch (error) {
          if (error.statusCode != 404) rethrow;
          status = await _uploadWithQueueRetry();
        }
        while (!_closed && status != 'completed' && status != 'failed') {
          if (record.status != status) {
            record.status = status;
            await widget.onChanged();
          }
          _notice(status == 'processing'
              ? 'Распознаём и озвучиваем'
              : 'Ожидаем в очереди');
          await Future<void>.delayed(const Duration(seconds: 2));
          if (_closed) return;
          status = await _api!.status(record.taskId);
        }
        if (_closed) return;
        record.status = status;
        record.manifestJson = await _api!.result(record.taskId);
        await widget.onChanged();
      }
      if (record.status == 'failed' ||
          record.manifestJson?['status'] == 'failed') {
        _notice('Ошибка распознавания');
        return;
      }
      final audioUrl = manifest?.audioUrl ?? '';
      if (audioUrl.isEmpty) {
        throw const FormatException('В результате нет ссылки на аудио');
      }
      _notice('Сохраняем аудио для прослушивания без сети');
      final file = widget.storage.audioFile(record.taskId);
      if (!await file.exists()) await _api!.downloadAudio(audioUrl, file);
      record.audioPath = file.path;
      await widget.onChanged();
      if (_closed) return;
      await _loadAudio();
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось продолжить: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _uploadWithQueueRetry() async {
    if (!await File(record.imagePath).exists()) {
      throw const FileSystemException('Локальный снимок не найден');
    }
    for (var attempt = 0; attempt < 4 && !_closed; attempt++) {
      try {
        _notice('Отправляем снимок на сервер');
        await _api!.upload(record.taskId, record.imagePath);
        if (mounted) setState(() => _uploaded = true);
        return 'pending';
      } on ApiException catch (error) {
        if (error.statusCode != 429 || attempt == 3) rethrow;
        _notice('Очередь заполнена. Повторяем отправку');
        await Future<void>.delayed(
            error.retryAfter ?? const Duration(seconds: 5));
      } on SocketException {
        // The upload may have succeeded while its response was lost. The next
        // user retry checks this UUID before sending the same image again.
        rethrow;
      }
    }
    throw const ApiException('Отправка прервана');
  }

  Future<void> _loadAudio() async {
    await _player.setFilePath(record.audioPath);
    if (mounted) {
      setState(() {
        _audioReady = true;
        _message = 'Лекция готова';
      });
    }
  }

  void _playOrPause() {
    if (!_audioReady) return;
    HapticFeedback.selectionClick();
    if (_playing) {
      unawaited(_player.pause());
    } else {
      unawaited(_startPlayback());
    }
  }

  Future<void> _startPlayback() async {
    try {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    } catch (error) {
      if (mounted) setState(() => _error = 'Ошибка воспроизведения: $error');
    }
  }

  Future<void> _seekTo(int index) async {
    final chunks = manifest?.chunks ?? [];
    if (!_audioReady || index < 0 || index >= chunks.length) return;
    final time =
        Duration(milliseconds: (chunks[index].startTime * 1000).round());
    try {
      await _player.seek(time);
      await HapticFeedback.selectionClick();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось перейти к фрагменту: $error');
      }
    }
  }

  Future<void> _changeSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
      if (mounted) setState(() => _speed = speed);
      await HapticFeedback.selectionClick();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось изменить скорость: $error');
      }
    }
  }

  Future<void> _toggleBookmark(int current) async {
    if (current < 0) return;
    final previous = record.bookmarkIndex;
    record.bookmarkIndex = previous == current ? null : current;
    try {
      await widget.onChanged();
      if (mounted) setState(() {});
      await HapticFeedback.mediumImpact();
    } catch (error) {
      record.bookmarkIndex = previous;
      if (mounted) {
        setState(() => _error = 'Не удалось сохранить закладку: $error');
      }
    }
  }

  Future<void> _handleCommand(VoiceCommand command) async {
    final chunks = manifest?.chunks ?? [];
    final current = manifest?.chunkAt(_position) ?? -1;
    switch (command) {
      case VoiceCommand.play:
        if (!_playing) _playOrPause();
        return;
      case VoiceCommand.pause:
        if (_playing) _playOrPause();
        return;
      case VoiceCommand.next:
        if (current + 1 < chunks.length) {
          await _seekTo(current + 1);
          if (!_playing) _playOrPause();
        }
        return;
      case VoiceCommand.previous:
        await _seekTo(current > 0 ? current - 1 : 0);
        if (!_playing) _playOrPause();
        return;
      case VoiceCommand.repeatFormula:
        final index = manifest?.nearestFormulaAtOrBefore(current);
        if (index == null) {
          _notice('До этого места формул нет');
        } else {
          await _seekTo(index);
          if (!_playing) _playOrPause();
        }
        return;
      case VoiceCommand.unknown:
        _notice('Команда не распознана');
        return;
    }
  }

  Future<void> _listen() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (mounted) setState(() => _error = '');
    try {
      // Pause first so the recognizer does not hear the lecture itself.
      if (_playing) {
        await _player.pause();
      }
      _speechStatusHandler = (status) {
        if (mounted && (status == 'notListening' || status == 'done')) {
          setState(() => _listening = false);
        }
      };
      _speechErrorHandler = (message) {
        if (mounted) {
          setState(() {
            _listening = false;
            _error = speechFailureMessage(message);
          });
        }
      };
      final available = _sharedSpeechReady ||
          await _speech.initialize(
            onStatus: (status) => _speechStatusHandler?.call(status),
            onError: (error) => _speechErrorHandler?.call(error.errorMsg),
            // Some Android builds do not publish a default speech recognizer.
            // Ask the plugin to look up an installed recognition service instead.
            options: Platform.isAndroid
                ? [
                    stt.SpeechToText.androidIntentLookup,
                    stt.SpeechToText.androidNoBluetooth
                  ]
                : null,
          );
      _sharedSpeechReady = available;
      if (!available) {
        if (mounted) {
          setState(() => _error = 'Служба распознавания речи недоступна '
              'или не разрешён микрофон. Проверьте настройки Android.');
        }
        return;
      }
      _commandHandled = false;
      if (mounted) {
        setState(() {
          _listening = true;
          _message = 'Слушаю команду';
        });
      }
      final locales = await _speech.locales();
      final russian = locales
          .where((locale) => locale.localeId.toLowerCase().startsWith('ru'));
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: russian.isEmpty ? null : russian.first.localeId,
          partialResults: false,
          cancelOnError: true,
          contextualPhrases: const [
            'воспроизвести',
            'пауза',
            'следующий',
            'предыдущий',
            'повтори формулу',
          ],
        ),
        onResult: (result) {
          if (!result.finalResult || _commandHandled) return;
          _commandHandled = true;
          unawaited(_speech.stop());
          if (mounted) setState(() => _listening = false);
          unawaited(_handleCommand(parseVoiceCommand(result.recognizedWords))
              .catchError((Object error) {
            if (mounted) {
              setState(() => _error = 'Команда не выполнена: $error');
            }
          }));
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = speechFailureMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => LectureView(
        record: record,
        position: _position,
        playing: _playing,
        loading: _loading,
        audioReady: _audioReady,
        uploaded: _uploaded,
        listening: _listening,
        message: _message,
        error: _error,
        speed: _speed,
        onPlayPause: _playOrPause,
        onSeek: (index) => unawaited(_seekTo(index)),
        onSeekTime: (time) => unawaited(_player.seek(time)),
        onListen: () => unawaited(_listen()),
        onRetry: () => unawaited(_resume()),
        onReprocess: () => widget.onRetryFailed(context),
        onSpeed: (speed) => unawaited(_changeSpeed(speed)),
        onBookmark: () =>
            unawaited(_toggleBookmark(manifest?.chunkAt(_position) ?? -1)),
      );
}
