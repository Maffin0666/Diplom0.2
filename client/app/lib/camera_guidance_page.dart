import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'app_haptics.dart';
import 'package:flutter/services.dart';
import 'app_preferences.dart';
import 'text_frame_assessment.dart';
import 'voice_commands.dart';
import 'voice_navigation.dart';
import 'user_error.dart';

class CameraGuidancePage extends StatefulWidget {
  const CameraGuidancePage({super.key});
  @override
  State<CameraGuidancePage> createState() => _CameraGuidancePageState();
}

class _CameraGuidancePageState extends State<CameraGuidancePage>
    with WidgetsBindingObserver {
  static const _cameraKeys = MethodChannel('lektoria/camera');
  CameraController? _camera;
  String _error = '', _hint = 'Наведите рамку на текст';
  bool _taking = false, _torch = false, _ready = false;
  int _generation = 0, _positiveFrames = 0;
  int _stableFrames = 0;
  bool _autoTriggered = false;
  Uint8List? _previousGray;
  Future<void>? _initializing;
  Future<void> _disposingCamera = Future<void>.value();
  DateTime _lastFrame = DateTime(2000), _lastFeedback = DateTime(2000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraKeys.setMethodCallHandler((call) async {
      if (call.method == 'capture' && mounted) await _capture();
    });
    unawaited(_cameraKeys.invokeMethod<void>(
        'captureKeys', {'enabled': true}).catchError((Object _) {}));
    unawaited(_ensureCamera());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _cameraKeys.setMethodCallHandler(null);
    unawaited(_cameraKeys.invokeMethod<void>(
        'captureKeys', {'enabled': false}).catchError((Object _) {}));
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(camera.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A permission dialog makes the activity inactive. Releasing the camera
    // then cancels its first initialization on some Android devices.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _generation++;
      final camera = _camera;
      _camera = null;
      if (camera != null) {
        _disposingCamera = camera.dispose();
      }
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        !_taking) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 300))
          .then((_) => _ensureCamera()));
    }
  }

  Future<void> _ensureCamera() async {
    if (_initializing != null) await _initializing;
    if (!mounted || _taking || _camera?.value.isInitialized == true) return;
    final pending = _initialize();
    _initializing = pending;
    try {
      await pending;
    } finally {
      if (identical(_initializing, pending)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    CameraController? camera;
    try {
      await _disposingCamera;
      if (!mounted || generation != _generation) return;
      setState(() => _error = '');
      final cameras =
          await availableCameras().timeout(const Duration(seconds: 10));
      if (cameras.isEmpty) {
        throw StateError('На устройстве нет доступной камеры');
      }
      final back =
          cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      camera = CameraController(
          back.isEmpty ? cameras.first : back.first, ResolutionPreset.max,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await camera.initialize().timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) {
        await camera.dispose();
        return;
      }
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || generation != _generation) {
        await camera.dispose();
        return;
      }
      _camera = camera;
      await camera.startImageStream(_frame).timeout(const Duration(seconds: 8));
      if (mounted && generation == _generation) setState(() => _error = '');
    } catch (error) {
      if (camera != null) {
        if (identical(camera, _camera)) _camera = null;
        await camera.dispose();
      }
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Камера пока недоступна. Разрешите доступ к камере в настройках телефона и нажмите «Повторить». Можно также выбрать снимок из галереи.');
        final voice = VoiceScope.maybeOf(context);
        if (voice != null) {
          unawaited(voice.announce(
              'Камера недоступна. Вернитесь назад и выберите системную камеру или галерею.'));
        }
      }
    }
  }

  void _frame(CameraImage image) {
    if (!mounted ||
        _taking ||
        ModalRoute.of(context)?.isCurrent != true ||
        !(PreferencesScope.of(context).cameraGuidance ||
            PreferencesScope.of(context).autoCapture)) {
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastFrame).inMilliseconds < 750) return;
    _lastFrame = now;
    final camera = _camera;
    if (camera == null) return;
    // Capture is locked to portrait. Sensor coordinates are mapped to the same
    // portrait canvas shown by the preview; stride is honored on all devices.
    final rotation = camera.description.sensorOrientation % 360;
    final swapped = rotation == 90 || rotation == 270;
    final uprightWidth = swapped ? image.height : image.width;
    final uprightHeight = swapped ? image.width : image.height;
    const sampleWidth = 180;
    final sampleHeight =
        (sampleWidth * uprightHeight / uprightWidth).round().clamp(80, 360);
    final gray = Uint8List(sampleWidth * sampleHeight);
    final plane = image.planes.first;
    final bgra = image.format.group == ImageFormatGroup.bgra8888;
    final pixelStride = plane.bytesPerPixel ?? (bgra ? 4 : 1);
    for (var y = 0; y < sampleHeight; y++) {
      for (var x = 0; x < sampleWidth; x++) {
        final ux = (x * uprightWidth / sampleWidth).floor();
        final uy = (y * uprightHeight / sampleHeight).floor();
        final (sx, sy) = switch (rotation) {
          90 => (uy, image.height - 1 - ux),
          180 => (image.width - 1 - ux, image.height - 1 - uy),
          270 => (image.width - 1 - uy, ux),
          _ => (ux, uy),
        };
        final offset = sy * plane.bytesPerRow + sx * pixelStride;
        if (offset < 0 || offset + (bgra ? 2 : 0) >= plane.bytes.length) {
          continue;
        }
        gray[y * sampleWidth + x] = bgra
            ? ((plane.bytes[offset] +
                    plane.bytes[offset + 1] +
                    plane.bytes[offset + 2]) ~/
                3)
            : plane.bytes[offset];
      }
    }
    final result = assessTextFrame(gray, sampleWidth, sampleHeight);
    final previous = _previousGray;
    var motion = double.infinity;
    if (previous != null && previous.length == gray.length) {
      var change = 0, samples = 0;
      for (var i = 0; i < gray.length; i += 16) {
        change += (gray[i] - previous[i]).abs();
        samples++;
      }
      motion = change / samples;
    }
    _previousGray = gray;
    _positiveFrames = result.textLikely ? _positiveFrames + 1 : 0;
    _stableFrames = result.textLikely && result.edgeStrength >= 4 && motion < 7
        ? _stableFrames + 1
        : 0;
    final ready = _positiveFrames >= 3;
    if (_ready != ready || _hint != result.hint) {
      setState(() {
        _ready = ready;
        _hint = result.hint;
      });
    }
    if (ready &&
        _stableFrames >= 4 &&
        PreferencesScope.of(context).autoCapture &&
        !_autoTriggered) {
      _autoTriggered = true;
      unawaited(_capture());
      return;
    }
    final voice = VoiceScope.maybeOf(context);
    if (!ready &&
        result.backgroundConsistent &&
        result.lines == 1 &&
        result.directionHint != null &&
        now.difference(_lastFeedback).inSeconds >= 4 &&
        voice?.listening != true &&
        voice?.busy != true) {
      _lastFeedback = now;
      if (PreferencesScope.of(context).spokenHints && voice != null) {
        unawaited(voice.announce(result.directionHint!));
      }
    }
    if (ready &&
        now.difference(_lastFeedback).inSeconds >= 6 &&
        voice?.listening != true &&
        voice?.busy != true) {
      _lastFeedback = now;
      final preferences = PreferencesScope.of(context);
      if (preferences.haptics) unawaited(AppHaptics.vibrate());
      if (preferences.earcons) unawaited(AppHaptics.tone('ready'));
      if (preferences.spokenHints && voice != null) {
        unawaited(voice.announce(PreferencesScope.of(context).autoCapture
            ? 'Лист в кадре. Держите телефон неподвижно для автоматического снимка.'
            : 'Лист в кадре. Держите телефон ровно и скажите: сделай фото.'));
      }
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (_taking || camera == null || !camera.value.isInitialized) return;
    setState(() => _taking = true);
    if (PreferencesScope.of(context).haptics) {
      unawaited(AppHaptics.vibrate(kind: 'shutter'));
    }
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      final photo = await camera.takePicture();
      if (mounted) Navigator.of(context).pop(photo);
    } catch (error) {
      _autoTriggered = false;
      if (mounted && PreferencesScope.of(context).haptics) {
        unawaited(AppHaptics.vibrate(kind: 'error'));
      }
      if (mounted && PreferencesScope.of(context).earcons) {
        unawaited(AppHaptics.tone('error'));
      }
      if (mounted) setState(() => _error = userError(error));
      if (mounted && camera.value.isInitialized) {
        await camera.startImageStream(_frame);
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  Future<bool> _command(AppVoiceIntent intent) async {
    if (intent.command == AppCommand.capture) {
      await _capture();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = PreferencesScope.of(context).reduceMotion;
    return VoicePage(
        onCommand: _command,
        child: Scaffold(
          appBar: AppBar(title: const Text('Съёмка конспекта'), actions: [
            IconButton(
              tooltip: _torch ? 'Выключить фонарь' : 'Включить фонарь',
              onPressed: camera == null
                  ? null
                  : () async {
                      try {
                        await camera.setFlashMode(
                            _torch ? FlashMode.off : FlashMode.torch);
                        if (mounted) setState(() => _torch = !_torch);
                      } catch (_) {
                        if (mounted) {
                          setState(() =>
                              _error = 'На этой камере фонарь недоступен');
                        }
                      }
                    },
              icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            )
          ]),
          body: SafeArea(
              child: Column(children: [
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: LayoutBuilder(builder: (context, constraints) {
                      return GestureDetector(
                          onTap: _capture,
                          behavior: HitTestBehavior.opaque,
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: Stack(fit: StackFit.expand, children: [
                                const ColoredBox(color: Colors.black),
                                if (camera?.value.isInitialized == true)
                                  Center(
                                      child: AspectRatio(
                                          aspectRatio:
                                              1 / camera!.value.aspectRatio,
                                          child: CameraPreview(camera)))
                                else if (_error.isNotEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            unawaited(_ensureCamera()),
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text(
                                            'Повторить открытие камеры'),
                                      ),
                                    ),
                                  )
                                else
                                  const Center(
                                      child: CircularProgressIndicator()),
                                if (camera?.value.isInitialized == true)
                                  Center(
                                      child: AspectRatio(
                                          aspectRatio:
                                              1 / camera!.value.aspectRatio,
                                          child: FractionallySizedBox(
                                              widthFactor: .84,
                                              heightFactor: .76,
                                              child: AnimatedContainer(
                                                  duration: reduceMotion
                                                      ? Duration.zero
                                                      : const Duration(
                                                          milliseconds: 250),
                                                  decoration: BoxDecoration(
                                                      border: Border.all(
                                                          color: _ready
                                                              ? const Color(
                                                                  0xFF8FFFF2)
                                                              : Colors.white,
                                                          width:
                                                              _ready ? 4 : 2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              18)))))),
                                Positioned(
                                  top: 18,
                                  left: 18,
                                  right: 18,
                                  child: Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: const Color(0xDD111735),
                                        borderRadius:
                                            BorderRadius.circular(100),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              _ready
                                                  ? Icons.check_circle_rounded
                                                  : Icons
                                                      .center_focus_strong_rounded,
                                              color: _ready
                                                  ? const Color(0xFF8FFFF2)
                                                  : Colors.white,
                                              size: 18),
                                          const SizedBox(width: 7),
                                          Text(
                                              _ready
                                                  ? 'Текст в рамке'
                                                  : 'Наведите на страницу',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                  ]),
                                ),
                                Positioned(
                                  left: 18,
                                  right: 18,
                                  bottom: 18,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 11),
                                    decoration: BoxDecoration(
                                      color: const Color(0xDD111735),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                        _ready
                                            ? 'Строки найдены · держите телефон ровно'
                                            : 'Уместите текст целиком внутри светлой рамки',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ])));
                    }))),
            Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Column(children: [
                  if (_error.isNotEmpty)
                    ErrorNotice(message: _error)
                  else
                    Semantics(
                        liveRegion: true,
                        child: Text(_hint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w700))),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                          onPressed:
                              _taking || camera?.value.isInitialized != true
                                  ? null
                                  : _capture,
                          icon: const Icon(Icons.camera_alt),
                          label:
                              Text(_taking ? 'Снимаю…' : 'Фотографировать'))),
                ])),
          ])),
        ));
  }
}
