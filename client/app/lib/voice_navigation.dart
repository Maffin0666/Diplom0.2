import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'app_haptics.dart';
import 'user_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  Future<void> stopAnnouncement() async {
    try {
      await _tts?.stop();
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
          !wasDictating && handled && intent.command == AppCommand.dictate;
      error = '';
      message = handled
          ? wasDictating
              ? intent.command == AppCommand.back
                  ? 'Диктовка отменена.'
                  : 'Текст фрагмента записан. Скажите «сохранить» для новой озвучки.'
              : intent.command == AppCommand.dictate
                  ? 'Теперь назовите новый текст фрагмента.'
                  : 'Выполнено: $words'
          : intent.command == AppCommand.unknown
              ? 'Не знаю команды «$words». Скажите «помощь».'
              : 'Здесь команда «$words» недоступна. Скажите «помощь».';
      if (_disposed) return;
      busy = false;
      _showFeedback();
      if ((!handled ||
          ![
            AppCommand.play,
            AppCommand.next,
            AppCommand.previous,
            AppCommand.fragment,
            AppCommand.firstFragment,
            AppCommand.lastFragment,
            AppCommand.repeatFormula,
            AppCommand.help,
            AppCommand.helpTopic
          ].contains(intent.command))) {
        await announce(message);
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
    unawaited(announce(reason));
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
    if (_ready) unawaited(_speech.cancel());
    if (_recorder != null) unawaited(_recorder!.dispose());
    if (_tts != null) unawaited(_tts!.stop());
    super.dispose();
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
  const VoiceDock({super.key, required this.voice, required this.onHelp});
  final VoiceNavigation voice;
  final VoidCallback onHelp;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: voice,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        return Material(
            color: colors.surfaceContainerLow,
            child: SafeArea(
                top: false,
                child: Stack(clipBehavior: Clip.none, children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: SizedBox(
                          height: 58,
                          child: Row(children: [
                            Expanded(
                                child: FilledButton.icon(
                              onPressed: () => unawaited(
                                  voice.busy ? voice.stop() : voice.toggle()),
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
                                      ? 'Отменить ввод'
                                      : voice.listening
                                          ? 'Завершить команду'
                                          : 'Сказать Лектории',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center),
                            )),
                            const SizedBox(width: 8),
                            IconButton.outlined(
                                onPressed: onHelp,
                                icon: const Icon(Icons.help_outline_rounded),
                                tooltip: 'Помощь'),
                          ]))),
                  if (voice.listening || voice.busy || voice.feedbackVisible)
                    Positioned(
                        bottom: 68,
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
