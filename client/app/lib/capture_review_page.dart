import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_preferences.dart';
import 'text_frame_assessment.dart';
import 'voice_commands.dart';
import 'voice_navigation.dart';

enum CaptureDecision { use, retry }

/// A lightweight check of the saved photo. These are hints, not OCR or a
/// guarantee that handwriting will be readable by the server.
Future<List<String>> inspectCapture(XFile photo) async {
  final notes = <String>[];
  final size = await photo.length();
  if (size > 15 * 1024 * 1024) {
    notes.add('Файл слишком большой для сервера. Снимите страницу заново.');
    return notes;
  }
  final bytes = await photo.readAsBytes();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 320,
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return notes;
      final rgba = data.buffer.asUint8List();
      final gray = Uint8List(image.width * image.height);
      for (var i = 0; i < gray.length; i++) {
        final offset = i * 4;
        gray[i] = ((rgba[offset] * 299 +
                    rgba[offset + 1] * 587 +
                    rgba[offset + 2] * 114) /
                1000)
            .round();
      }
      final assessment = assessTextFrame(gray, image.width, image.height);
      if (assessment.meanBrightness < 65) {
        notes.add('Снимок может быть слишком тёмным. Добавьте света.');
      }
      if (!assessment.textLikely) {
        notes
            .add('Строки видны неуверенно. Проверьте, что весь текст в кадре.');
      }
      if (assessment.edgeStrength < 3) {
        notes.add('Изображение может быть размытым. Проверьте резкость букв.');
      }
      return notes;
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class CaptureReviewPage extends StatefulWidget {
  const CaptureReviewPage(
      {super.key, required this.photo, required this.retryLabel});

  final XFile photo;
  final String retryLabel;

  @override
  State<CaptureReviewPage> createState() => _CaptureReviewPageState();
}

class _CaptureReviewPageState extends State<CaptureReviewPage> {
  late final Future<List<String>> _inspection = inspectCapture(widget.photo);
  String _error = '';
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_announceInspection());
    });
  }

  Future<void> _announceInspection() async {
    if (!PreferencesScope.of(context).spokenHints) return;
    String message;
    try {
      final notes = await _inspection;
      message = notes.isEmpty
          ? 'Быстрая проверка не обнаружила явных проблем со снимком. '
              'Можно отправить его на распознавание или переснять.'
          : 'Проверьте снимок. ${notes.join(' ')} '
              'Можно переснять или отправить этот кадр.';
    } catch (_) {
      message = 'Не удалось проверить качество снимка. '
          'Можете переснять или отправить его на распознавание.';
    }
    if (mounted) await VoiceScope.maybeOf(context)?.announce(message);
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    setState(() => _confirming = true);
    try {
      if (await widget.photo.length() > 15 * 1024 * 1024) {
        if (mounted) {
          setState(() => _error =
              'Этот файл больше 15 МБ. Снимите страницу ещё раз или выберите файл поменьше.');
        }
        return;
      }
      await _inspection;
      if (mounted) Navigator.of(context).pop(CaptureDecision.use);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Не удалось открыть снимок. Снимите страницу ещё раз.');
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) => VoicePage(
        onCommand: (intent) async {
          if (intent.command == AppCommand.usePhoto) {
            await _confirm();
            return true;
          }
          if (intent.command == AppCommand.capture) {
            Navigator.of(context).pop(CaptureDecision.retry);
            return true;
          }
          return false;
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Проверить снимок')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: LayoutBuilder(builder: (context, bounds) {
                  final landscape = bounds.maxWidth > bounds.maxHeight &&
                      bounds.maxHeight < 500;
                  final confirmationActions = <Widget>[
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: FilledButton.icon(
                        onPressed: _confirming ? null : _confirm,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Использовать снимок'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(CaptureDecision.retry),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(widget.retryLabel),
                      ),
                    ),
                  ];
                  final sections = <Widget>[
                    SizedBox(
                      height: (MediaQuery.sizeOf(context).height * .48)
                          .clamp(210.0, 420.0),
                      child: InteractiveViewer(
                        minScale: .8,
                        maxScale: 5,
                        child: Center(
                          child: Image.file(
                            File(widget.photo.path),
                            fit: BoxFit.contain,
                            semanticLabel: 'Снятая страница конспекта',
                            errorBuilder: (_, __, ___) => const Text(
                              'Не удалось открыть снимок. Попробуйте ещё раз.',
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (landscape) ...[
                            ...confirmationActions,
                            const SizedBox(height: 12),
                          ],
                          Text('Виден ли весь текст?',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text(
                            'Увеличьте фото и проверьте края страницы, резкость букв и свет. '
                            'После подтверждения снимок отправится на распознавание.',
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<List<String>>(
                            future: _inspection,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return const Text(
                                    'Не удалось проверить качество снимка. Можно переснять его или отправить на распознавание.');
                              }
                              if (!snapshot.hasData) {
                                return const Text('Проверяем качество снимка…');
                              }
                              if (snapshot.data!.isEmpty) {
                                return const Text(
                                    'Проверьте снимок и подтвердите отправку.');
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final note in snapshot.data!)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text('• $note'),
                                    ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          if (_error.isNotEmpty) ...[
                            Text(_error,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                          ],
                          if (!landscape) ...confirmationActions,
                        ],
                      ),
                    ),
                  ];
                  return landscape
                      ? Row(children: [
                          Expanded(child: sections.first),
                          const VerticalDivider(width: 1),
                          Expanded(child: ListView(children: [sections.last])),
                        ])
                      : ListView(children: sections);
                }),
              ),
            ),
          ),
        ),
      );
}
