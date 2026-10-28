import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'app_haptics.dart';
import 'user_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'app_preferences.dart';
import 'speech_diagnostics.dart';
import 'voice_commands.dart';

typedef VoiceHandler = Future<bool> Function(AppVoiceIntent intent);

/// A valid phrase cannot be performed in the current lecture or screen.
class VoiceActionFeedback implements Exception {
  const VoiceActionFeedback(this.message);
  final String message;
}

/// One microphone owner survives route changes. Screens register only actions.
class VoiceNavigation extends ChangeNotifier with WidgetsBindingObserver {
  VoiceNavigation() {
    WidgetsBinding.instance.addObserver(this);
  }
  final _speech = stt.SpeechToText();
  AudioRecorder? _recorder;
  FlutterTts? _tts;
  AudioPlayer? _actionPlayer;
  final Map<String, Future<File?>> _actionDownloads = {};
  final List<_VoiceBinding> _bindings = [];
  AppPreferences preferences = const AppPreferences();
  String server = '';
  VoiceHandler? globalHandler;
  bool listening = false, busy = false, usesServer = false;
  bool _ready = false, _unavailable = false, _disposed = false;
  bool _recording = false, _session = false;
  bool _dictationSession = false;
  int _speaking = 0;
  bool get speaking => _speaking > 0;
  bool feedbackVisible = false;
  int _turn = 0;
  String message = 'Навигация голосом', error = '';
  Timer? _timer, _nextTimer, _feedbackTimer;
  String? _recordPath;

  void _update() {
    if (!_disposed) notifyListeners();
  }

  Future<void> announce(String text, {bool force = false}) async {
    if ((!preferences.spokenHints && !force) || listening || _disposed) return;
    _speaking++;
    _update();
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage('ru-RU');
      await tts.setSpeechRate(.48);
      await tts.awaitSpeakCompletion(true);
      await tts.speak(text).timeout(Duration(seconds: force ? 90 : 8));
    } catch (_) {
      // TalkBack semantics and vibration remain available.
    } finally {
      _speaking--;
      _update();
    }
  }

  /// Short confirmations are cached on the phone. The first use is spoken
  /// immediately by Android while the server prepares its voice in background.
  Future<void> preloadAction(String text) async {
    if (!preferences.spokenActions || server.trim().isEmpty || _disposed) {
      return;
    }
    try {
      final key = _actionKey(server.trim(), text);
      final folder = Directory(
          '${(await getApplicationSupportDirectory()).path}/action_speech');
      final file = File('${folder.path}/$key.mp3');
      if (await file.exists()) return;
      await _actionDownloads
          .putIfAbsent(key, () => _downloadAction(text, file))
          .whenComplete(() => _actionDownloads.remove(key));
    } catch (_) {
      // Local Android speech remains available when the server is offline.
    }
  }

  Future<void> announceAction(String text) async {
    if (!preferences.spokenActions || listening || busy || _disposed) return;
    final address = server.trim();
    if (address.isEmpty) {
      await announce(text, force: true);
      return;
    }
    try {
      final key = _actionKey(address, text);
      final folder = Directory(
          '${(await getApplicationSupportDirectory()).path}/action_speech');
      final file = File('${folder.path}/$key.mp3');
      if (!await file.exists()) {
        unawaited(preloadAction(text));
        await announce(text, force: true);
        return;
      }
      _speaking++;
      _update();
      try {
        final player = _actionPlayer ??= AudioPlayer();
        await player.setAudioSource(
            AudioSource.file(file.path, tag: MediaItem(id: key, title: text)));
        await player.play().timeout(const Duration(seconds: 12));
      } finally {
        _speaking--;
        _update();
      }
    } catch (_) {
      await announce(text, force: true);
    }
  }

  Future<File?> _downloadAction(String text, File file) async {
    RecognitionApi? api;
    try {
      await file.parent.create(recursive: true);
      api = RecognitionApi(server);
      final url = await api.helpSpeech(text);
      await api.downloadAudio(url.path, file);
      return file;
    } catch (_) {
      // The next action retries; offline use remains immediate through Android.
      return null;
    } finally {
      api?.close();
    }
  }

  String _actionKey(String address, String text) {
    var hash = 0x811c9dc5;
    for (final code in '$address\n$text'.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<void> stopAnnouncement() async {
    try {
      await _tts?.stop();
      await _actionPlayer?.stop();
    } catch (_) {
      // The speech engine may have already stopped.
    }
  }

  Future<bool> dispatch(AppVoiceIntent intent) async {
    for (final binding in _bindings.reversed.toList()) {
      if (binding.active() && await binding.handler(intent)) return true;
    }
    return await globalHandler?.call(intent) ?? false;
  }

  Future<void> toggle({bool forceServer = false}) async {
    if (busy) return;
    if (listening) {
      _session = false;
      if (_recording) {
        await _finishRecording();
      } else {
        await stop();
      }
      return;
    }
    _session = true;
    await _start(forceServer: forceServer);
  }

  /// The editor's microphone button can start directly with free-form speech.
  Future<void> beginDictation() async {
    if (busy || listening) return;
    _dictationSession = true;
    await toggle();
  }

  Future<void> stop() async {
    _turn++;
    _session = false;
    _dictationSession = false;
    _timer?.cancel();
    _nextTimer?.cancel();
    if (_ready) await _speech.cancel();
    if (_recording) {
      _recording = false;
      await _recorder?.cancel();
    }
    listening = false;
    busy = false;
    message = 'Голосовой ввод остановлен';
    _update();
  }

  Future<void> _start({bool forceServer = false}) async {
    if (_disposed || busy || listening) return;
    final turn = ++_turn;
    busy = true;
    error = '';
    feedbackVisible = false;
    _feedbackTimer?.cancel();
    _update();
    try {
      await _tts?.stop();
      for (final binding in _bindings.reversed.toList()) {
        if (binding.active()) {
          await binding.beforeListen?.call();
          break;
        }
      }
      usesServer = forceServer ||
          preferences.voiceMode == 'server' ||
          (_unavailable && preferences.voiceMode == 'auto');
      if (!usesServer && !_ready) {
        try {
          _ready = await _speech.initialize(
            onStatus: (status) {
              if ((status == 'done' || status == 'notListening') &&
                  listening &&
                  !_recording) {
                // Final results can arrive after the status notification.
                _timer?.cancel();
                _timer = Timer(const Duration(milliseconds: 900), () {
                  if (listening && !_recording) {
                    _fail(
                        'Команда не расслышана. Нажмите микрофон и повторите.');
                  }
                });
              }
            },
            onError: (error) => _fail(speechFailureMessage(error.errorMsg)),
            options: Platform.isAndroid
                ? [
                    stt.SpeechToText.androidIntentLookup,
                    stt.SpeechToText.androidNoBluetooth
                  ]
                : null,
          );
        } catch (error) {
          if (!speechServiceUnavailable(error)) rethrow;
        }
        _unavailable = !_ready;
        if (!_ready) {
          if (preferences.voiceMode == 'android') {
            throw StateError(speechFailureMessage('recognizerNotAvailable'));
          }
          usesServer = true;
        }
      }
      if (turn != _turn || _disposed) return;
      if (usesServer) {
        if (server.isEmpty) {
          throw const ApiException(
              'Укажите адрес ноутбука в настройках подключения');
        }
        if (!await (_recorder ??= AudioRecorder()).hasPermission()) {
          throw PlatformException(code: 'error_permission');
        }
        final dir = await getTemporaryDirectory();
        _recordPath =
            '${dir.path}${Platform.pathSeparator}voice_${const Uuid().v4()}.wav';
        await _recorder!.start(
            const RecordConfig(
                encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
            path: _recordPath!);
        if (turn != _turn || _disposed) {
          await _recorder?.cancel();
          return;
        }
        _recording = true;
        _timer = Timer(Duration(seconds: preferences.commandSeconds),
            () => unawaited(_finishRecording()));
      }
      listening = true;
      busy = false;
      message = usesServer
          ? 'Говорите. Повторное нажатие отправит команду.'
          : 'Слушаю команду';
      _update();
      if (preferences.haptics) unawaited(AppHaptics.vibrate());
      if (!usesServer) {
        final locales = await _speech.locales();
        final russian =
            locales.where((l) => l.localeId.toLowerCase().startsWith('ru'));
        await _speech.listen(
          listenOptions: stt.SpeechListenOptions(
              listenFor: const Duration(seconds: 10),
              localeId: russian.isEmpty ? null : russian.first.localeId,
              partialResults: false,
              cancelOnError: true),
          onResult: (result) {
            if (result.finalResult && turn == _turn && listening) {
              listening = false;
              busy = true;
              _timer?.cancel();
              _update();
              unawaited(_complete(result.recognizedWords));
            }
          },
        );
      }
    } catch (error) {
      _fail(speechFailureMessage(error));
    }
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _recording = false;
    _timer?.cancel();
    listening = false;
    busy = true;
    message = 'Распознаю на ноутбуке';
    _update();
    final turn = _turn;
    RecognitionApi? api;
    final path = _recordPath;
    _recordPath = null;
    try {
      final saved = await _recorder!.stop();
      if (saved == null) {
        throw const FormatException('Микрофон не сохранил запись');
      }
      api = RecognitionApi(server);
      final words =
          await api.recognizeVoiceCommand(saved, dictation: _dictationSession);
      if (turn == _turn && !_disposed) await _complete(words);
    } catch (error) {
      if (turn == _turn) _fail(userError(error));
    } finally {
      api?.close();
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _complete(String words) async {
    try {
      if (words.isEmpty || words == '[unk]') {
        _fail('Команда не расслышана. Повторите её.');
        return;
      }
      final parsed = parseAppVoiceCommand(words);
      final intent = AppVoiceIntent(parsed.command,
          number: parsed.number,
          section: parsed.section,
          option: parsed.option,
          enabled: parsed.enabled,
          value: parsed.value,
          utterance: words);
      if (intent.command == AppCommand.stopVoice) {
        await stop();
        await announce('Голосовой ввод остановлен');
        return;
      }
      final handled = await dispatch(intent);
      final wasDictating = _dictationSession;
      _dictationSession =
          !wasDictating && handled &&
              (intent.command == AppCommand.dictate ||
                  intent.command == AppCommand.dictateSpeech);
      error = '';
      message = handled
          ? wasDictating
              ? intent.command == AppCommand.back
                  ? 'Диктовка отменена.'
                  : 'Фраза записана. Скажите «сохранить» для новой озвучки.'
              : intent.command == AppCommand.dictate
                  ? 'Теперь назовите новый текст фрагмента.'
                  : intent.command == AppCommand.dictateSpeech
                      ? 'Теперь произнесите нужное произношение формулы или текста.'
                  : 'Выполнено: $words'
          : intent.command == AppCommand.unknown
              ? 'Не знаю команды «$words». Скажите «помощь».'
              : 'Здесь команда «$words» недоступна. Скажите «помощь».';
      if (_disposed) return;
      busy = false;
      _showFeedback();
      if (!handled) {
        await announce(message, force: true);
      } else if (preferences.spokenActions &&
          ![
            AppCommand.play,
            AppCommand.next,
            AppCommand.previous,
            AppCommand.fragment,
            AppCommand.firstFragment,
            AppCommand.lastFragment,
            AppCommand.repeatFormula,
            AppCommand.explainFormula,
            AppCommand.help,
            AppCommand.helpTopic
          ].contains(intent.command)) {
        await announce(message, force: true);
      }
      if (_session &&
          (preferences.continuousVoice ||
              _dictationSession ||
              (wasDictating && handled && intent.command != AppCommand.back))) {
        _nextTimer =
            Timer(const Duration(milliseconds: 800), () => unawaited(_start()));
      }
    } catch (error) {
      _fail(error is VoiceActionFeedback ? error.message : userError(error));
    }
  }

  void _showFeedback() {
    feedbackVisible = true;
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 5), () {
      feedbackVisible = false;
      error = '';
      _update();
    });
    _update();
  }

  void _fail(String reason) {
    if (_disposed) return;
    _timer?.cancel();
    _nextTimer?.cancel();
    listening = false;
    busy = false;
    _session = false;
    _dictationSession = false;
    error = reason;
    _showFeedback();
    unawaited(announce(reason, force: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && (listening || busy)) {
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _turn++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _nextTimer?.cancel();
    _feedbackTimer?.cancel();
    if (_ready) unawaited(_ignorePlatformFailure(_speech.cancel));
    if (_recorder != null) {
      unawaited(_ignorePlatformFailure(_recorder!.dispose));
    }
    if (_tts != null) unawaited(_ignorePlatformFailure(_tts!.stop));
    if (_actionPlayer != null) {
      unawaited(_ignorePlatformFailure(_actionPlayer!.dispose));
    }
    super.dispose();
  }

  Future<void> _ignorePlatformFailure(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (_) {
      // The OS can release a speech service before this widget is disposed.
    }
  }
}

class _VoiceBinding {
  _VoiceBinding(this.active, this.handler, this.beforeListen);
  final bool Function() active;
  final VoiceHandler handler;
  final Future<void> Function()? beforeListen;
}

class VoiceScope extends InheritedNotifier<VoiceNavigation> {
  const VoiceScope(
      {super.key, required VoiceNavigation controller, required super.child})
      : super(notifier: controller);
  static VoiceNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VoiceScope>()?.notifier;
}

/// Bind actions to the current route, excluding covered pages and dialogs.
class VoicePage extends StatefulWidget {
  const VoicePage(
      {super.key,
      required this.child,
      required this.onCommand,
      this.beforeListen,
      this.scrollController});
  final Widget child;
  final VoiceHandler onCommand;
  final Future<void> Function()? beforeListen;
  final ScrollController? scrollController;
  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  VoiceNavigation? _voice;
  _VoiceBinding? _binding;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final voice = VoiceScope.maybeOf(context);
    if (voice != _voice) {
      if (_binding != null) _voice?._bindings.remove(_binding);
      _voice = voice;
      _binding = _VoiceBinding(
          () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
          (intent) async {
        final scroll = widget.scrollController;
        if ((intent.command == AppCommand.scrollUp ||
                intent.command == AppCommand.scrollDown) &&
            scroll?.hasClients == true) {
          final direction = intent.command == AppCommand.scrollDown ? 1 : -1;
          final target = (scroll!.offset +
                  direction * scroll.position.viewportDimension * .7)
              .clamp(0.0, scroll.position.maxScrollExtent);
          await scroll.animateTo(target,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? const Duration(milliseconds: 1)
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOut);
          return true;
        }
        return widget.onCommand(intent);
      }, () async => await widget.beforeListen?.call());
      if (_binding != null) _voice?._bindings.add(_binding!);
    }
  }

  @override
  void dispose() {
    if (_binding != null) _voice?._bindings.remove(_binding);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class VoiceDock extends StatelessWidget {
  const VoiceDock(
      {super.key,
      required this.voice,
      required this.onHelp,
      this.compact = false});
  final VoiceNavigation voice;
  final VoidCallback onHelp;
  final bool compact;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: voice,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        if (compact) {
          final label = voice.busy
              ? 'Отменить распознавание'
              : voice.listening
                  ? voice.usesServer
                      ? 'Отправить голосовую команду'
                      : 'Остановить прослушивание'
                  : 'Сказать Лектории';
          return Column(mainAxisSize: MainAxisSize.min, children: [
            if (voice.listening || voice.busy || voice.feedbackVisible)
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: voice.error.isNotEmpty
                      ? ErrorNotice(message: voice.error)
                      : Semantics(
                          liveRegion: true,
                          child: Card(
                              color: colors.primaryContainer,
                              child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(voice.message,
                                      textAlign: TextAlign.center))))),
            Material(
                color: colors.surfaceContainerHigh,
                elevation: 4,
                borderRadius: BorderRadius.circular(32),
                child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton.filled(
                          tooltip: label,
                          constraints:
                              const BoxConstraints(minWidth: 64, minHeight: 64),
                          onPressed: () => unawaited(
                              voice.busy ? voice.stop() : voice.toggle()),
                          icon: Icon(voice.listening
                              ? Icons.stop_circle_outlined
                              : Icons.mic_rounded)),
                      IconButton(
                          tooltip: 'Помощь',
                          constraints:
                              const BoxConstraints(minWidth: 64, minHeight: 64),
                          onPressed: onHelp,
                          icon: const Icon(Icons.help_outline_rounded)),
                    ]))),
          ]);
        }
        final landscape = MediaQuery.sizeOf(context).width >
            MediaQuery.sizeOf(context).height;
        return Material(
            color: colors.surfaceContainerLow,
            child: SafeArea(
                top: false,
                child: Stack(clipBehavior: Clip.none, children: [
                  Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: SizedBox(
                                  height: landscape ? 64 : 64,
                                  child: Row(children: [
                                    Expanded(
                                        child: FilledButton.icon(
                                      onPressed: () => unawaited(voice.busy
                                          ? voice.stop()
                                          : voice.toggle()),
                                      icon: voice.busy
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : Icon(voice.listening
                                              ? Icons.stop_circle_outlined
                                              : Icons.mic_rounded),
                                      label: Text(
                                          voice.busy
                                              ? 'Отменить распознавание'
                                              : voice.listening
                                                  ? voice.usesServer
                                                      ? 'Отправить команду'
                                                      : 'Остановить ввод'
                                                  : 'Сказать Лектории',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center),
                                    )),
                                    const SizedBox(width: 8),
                                    IconButton.outlined(
                                        onPressed: onHelp,
                                        icon: const Icon(
                                            Icons.help_outline_rounded),
                                        constraints: const BoxConstraints(
                                            minWidth: 64, minHeight: 64),
                                        tooltip: 'Помощь'),
                                  ]))))),
                  if (voice.listening || voice.busy || voice.feedbackVisible)
                    Positioned(
                        bottom: landscape ? 74 : 74,
                        left: 12,
                        right: 12,
                        child: voice.error.isNotEmpty
                            ? ErrorNotice(message: voice.error)
                            : Semantics(
                                liveRegion: true,
                                child: Material(
                                    elevation: 4,
                                    color: colors.primaryContainer,
                                    borderRadius: BorderRadius.circular(14),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Text(voice.message,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: colors.onPrimaryContainer,
                                              fontWeight: FontWeight.w700)),
                                    )))),
                ])));
      });
}
