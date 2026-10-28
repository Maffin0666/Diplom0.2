import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'user_error.dart';

import 'models.dart';
import 'photo_line_preview.dart';
import 'voice_commands.dart';
import 'voice_navigation.dart';

/// Reviews OCR by fragment so regenerated audio keeps accurate navigation.
class TranscriptEditor extends StatefulWidget {
  const TranscriptEditor({
    super.key,
    required this.manifest,
    required this.imagePath,
    required this.onSave,
    this.reviewedChunkIds = const [],
    this.onConfirm,
  });

  final LectureManifest manifest;
  final String imagePath;
  final Future<void> Function(List<ChunkCorrection>) onSave;
  final List<String> reviewedChunkIds;
  final Future<void> Function(String id)? onConfirm;

  @override
  State<TranscriptEditor> createState() => _TranscriptEditorState();
}

class _TranscriptEditorState extends State<TranscriptEditor> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _jumpController = TextEditingController();
  late final List<TextEditingController> _textControllers;
  late final List<TextEditingController> _spokenControllers;
  late final List<bool> _formulas;
  late final List<bool> _manualSpeech;
  late final List<bool> _removed;
  late final Set<String> _reviewed;
  bool _busy = false;
  bool _awaitingDictation = false;
  bool _dictatingPronunciation = false;
  String _error = '';
  int _activeIndex = 0;
  late final Future<ui.Image?> _photoFuture;
  ui.Image? _decodedPhoto;

  @override
  void initState() {
    super.initState();
    final chunks = widget.manifest.chunks;
    _reviewed = widget.reviewedChunkIds.toSet();
    _activeIndex = chunks.indexWhere(
        (chunk) => chunk.needsReview && !_reviewed.contains(chunk.id));
    if (_activeIndex < 0) _activeIndex = 0;
    _photoFuture = _loadPhoto();
    _textControllers =
        chunks.map((chunk) => TextEditingController(text: chunk.text)).toList();
    // An override must be entered deliberately; the old pronunciation may
    // describe OCR errors that the user has just corrected.
    _spokenControllers = chunks.map((_) => TextEditingController()).toList();
    _formulas = chunks.map((chunk) => chunk.isFormula).toList();
    _manualSpeech = List<bool>.filled(chunks.length, false);
    _removed = List<bool>.filled(chunks.length, false);
    for (final controller in [..._textControllers, ..._spokenControllers]) {
      controller.addListener(_refresh);
    }
  }

  Future<ui.Image?> _loadPhoto() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 2048,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        if (!mounted) {
          frame.image.dispose();
          return null;
        }
        _decodedPhoto = frame.image;
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // An old lecture may no longer have its original photo.
      return null;
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [..._textControllers, ..._spokenControllers]) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    _scroll.dispose();
    _jumpController.dispose();
    _decodedPhoto?.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final chunks = widget.manifest.chunks;
    for (var i = 0; i < chunks.length; i++) {
      if (_removed[i] ||
          _textControllers[i].text.trim() != chunks[i].text.trim() ||
          _formulas[i] != chunks[i].isFormula ||
          (_manualSpeech[i] &&
              _spokenControllers[i].text.trim() !=
                  chunks[i].spokenText.trim())) {
        return true;
      }
    }
    return false;
  }

  int get _remainingReview => widget.manifest.chunks
      .where((chunk) => chunk.needsReview && !_reviewed.contains(chunk.id))
      .length;

  void _nextUncertain() {
    final chunks = widget.manifest.chunks;
    for (var offset = 1; offset <= chunks.length; offset++) {
      final index = (_activeIndex + offset) % chunks.length;
      if (chunks[index].needsReview && !_reviewed.contains(chunks[index].id)) {
        _select(index);
        return;
      }
    }
    setState(() => _error = 'Все сомнительные фрагменты проверены');
  }

  Future<void> _confirmCurrent() async {
    final chunk = widget.manifest.chunks[_activeIndex];
    if (_busy || _reviewed.contains(chunk.id)) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.onConfirm?.call(chunk.id);
      if (!mounted) return;
      setState(() => _reviewed.add(chunk.id));
      if (_remainingReview > 0) _nextUncertain();
    } catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _submit() async {
    if (_busy || !_hasChanges) return false;
    if (_removed.every((removed) => removed)) {
      setState(() => _error = 'Оставьте хотя бы один фрагмент для озвучивания');
      return false;
    }
    for (var i = 0; i < widget.manifest.chunks.length; i++) {
      if (_removed[i]) continue;
      if (_textControllers[i].text.trim().isEmpty ||
          (_manualSpeech[i] && _spokenControllers[i].text.trim().isEmpty)) {
        _select(i);
        setState(() => _error = 'Заполните текст фрагмента ${i + 1}');
        return false;
      }
    }
    if (!_formKey.currentState!.validate()) return false;
    FocusScope.of(context).unfocus();
    final corrections = [
      for (var i = 0; i < widget.manifest.chunks.length; i++)
        ChunkCorrection(
          id: widget.manifest.chunks[i].id,
          text: _textControllers[i].text.trim(),
          isFormula: _formulas[i],
          spokenText:
              _manualSpeech[i] ? _spokenControllers[i].text.trim() : null,
          remove: _removed[i],
        ),
    ];
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.onSave(corrections);
      if (mounted) Navigator.of(context).pop();
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _error = userError(error));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(int index) {
    if (index < 0 || index >= widget.manifest.chunks.length) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _activeIndex = index;
      _awaitingDictation = false;
      _dictatingPronunciation = false;
      _error = '';
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _selectByVoice(int index) async {
    _select(index);
    if (index < 0 || index >= widget.manifest.chunks.length) return;
    final content = _textControllers[index].text.trim();
    final preview = content.length > 180
        ? '${content.substring(0, 180)}. Текст продолжается.'
        : content;
    unawaited(VoiceScope.maybeOf(context)?.announce(
          'Фрагмент ${index + 1} из ${widget.manifest.chunks.length}. $preview',
          force: true,
        ) ??
        Future<void>.value());
  }

  void _jumpToNumber() {
    final number = int.tryParse(_jumpController.text.trim());
    if (number == null ||
        number < 1 ||
        number > widget.manifest.chunks.length) {
      setState(() =>
          _error = 'Введите номер от 1 до ${widget.manifest.chunks.length}');
      return;
    }
    _select(number - 1);
    _jumpController.clear();
  }

  Future<void> _chooseFragment() async {
    final search = TextEditingController();
    try {
      final selected = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, update) {
            final query = search.text.trim().toLowerCase();
            final matches = [
              for (var i = 0; i < widget.manifest.chunks.length; i++)
                if (query.isEmpty ||
                    widget.manifest.chunks[i].text
                        .toLowerCase()
                        .contains(query) ||
                    '${i + 1}' == query)
                  i,
            ];
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
                child: SizedBox(
                  height: MediaQuery.sizeOf(sheetContext).height * .7,
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: TextField(
                        controller: search,
                        autofocus: true,
                        onChanged: (_) => update(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Найти слово или номер фрагмента',
                          prefixIcon: Icon(Icons.search_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, position) {
                          final i = matches[position];
                          final chunk = widget.manifest.chunks[i];
                          return ListTile(
                            title: Text(
                                'Фрагмент ${i + 1} · ${chunk.isFormula ? 'формула' : 'текст'}'),
                            subtitle: Text(
                              _textControllers[i].text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: chunk.needsReview
                                ? const Icon(Icons.rate_review_outlined,
                                    semanticLabel: 'Нужна проверка')
                                : null,
                            onTap: () => Navigator.of(sheetContext).pop(i),
                          );
                        },
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      );
      if (mounted && selected != null) _select(selected);
    } finally {
      search.dispose();
    }
  }

  Future<bool> _voiceCommand(AppVoiceIntent intent) async {
    if (_awaitingDictation) {
      if (intent.command == AppCommand.back) {
        setState(() {
          _awaitingDictation = false;
          _dictatingPronunciation = false;
        });
        return true;
      }
      final words = intent.utterance?.trim() ?? '';
      if (words.isEmpty) {
        setState(() {
          _awaitingDictation = false;
          _dictatingPronunciation = false;
          _error = 'Не удалось расслышать текст. Повторите фразу.';
        });
        throw const VoiceActionFeedback(
            'Не удалось расслышать текст. Повторите фразу.');
      }
      if (_dictatingPronunciation) {
        _spokenControllers[_activeIndex].text = words;
      } else {
        _textControllers[_activeIndex].text = words;
      }
      setState(() {
        _awaitingDictation = false;
        _dictatingPronunciation = false;
        _error = '';
      });
      return true;
    }
    switch (intent.command) {
      case AppCommand.save:
        if (!_hasChanges) {
          throw const VoiceActionFeedback('Сначала измените текст фрагмента.');
        }
        if (!await _submit()) {
          throw VoiceActionFeedback(_error.isEmpty
              ? 'Исправления пока не сохранены. Попробуйте ещё раз.'
              : _error);
        }
        return true;
      case AppCommand.confirmFragment:
        if (widget.manifest.chunks.isNotEmpty) await _confirmCurrent();
        return true;
      case AppCommand.nextUncertain:
        if (_remainingReview == 0) {
          throw const VoiceActionFeedback(
              'Все сомнительные фрагменты уже проверены.');
        }
        _nextUncertain();
        return true;
      case AppCommand.fragment:
        final index = (intent.number ?? 0) - 1;
        if (index < 0 || index >= widget.manifest.chunks.length) {
          throw const VoiceActionFeedback('Такого фрагмента в лекции нет');
        } else {
          await _selectByVoice(index);
        }
        return true;
      case AppCommand.firstFragment:
        await _selectByVoice(0);
        return true;
      case AppCommand.lastFragment:
        await _selectByVoice(widget.manifest.chunks.length - 1);
        return true;
      case AppCommand.next:
        if (_activeIndex < widget.manifest.chunks.length - 1) {
          await _selectByVoice(_activeIndex + 1);
        } else {
          throw const VoiceActionFeedback('Это последний фрагмент');
        }
        return true;
      case AppCommand.previous:
        if (_activeIndex > 0) {
          await _selectByVoice(_activeIndex - 1);
        } else {
          throw const VoiceActionFeedback('Это первый фрагмент');
        }
        return true;
      case AppCommand.dictate:
        if (_busy || widget.manifest.chunks.isEmpty) {
          throw const VoiceActionFeedback('Сейчас нельзя заменить этот фрагмент.');
        }
        setState(() {
          _awaitingDictation = true;
          _dictatingPronunciation = false;
          _error = '';
        });
        return true;
      case AppCommand.dictateSpeech:
        if (_busy || widget.manifest.chunks.isEmpty) {
          throw const VoiceActionFeedback(
              'Сейчас нельзя изменить произношение фрагмента.');
        }
        setState(() {
          _manualSpeech[_activeIndex] = true;
          _awaitingDictation = true;
          _dictatingPronunciation = true;
          _error = '';
        });
        return true;
      case AppCommand.markFormula:
      case AppCommand.markText:
        if (_busy || widget.manifest.chunks.isEmpty) {
          throw const VoiceActionFeedback('Сейчас нельзя изменить тип фрагмента.');
        }
        setState(() => _formulas[_activeIndex] =
            intent.command == AppCommand.markFormula);
        return true;
      case AppCommand.removeFragment:
        if (_busy || _removed.isEmpty) {
          throw const VoiceActionFeedback('Сейчас нельзя исключить фрагмент.');
        }
        setState(() => _removed[_activeIndex] = true);
        return true;
      case AppCommand.restoreFragment:
        if (_busy || _removed.isEmpty) {
          throw const VoiceActionFeedback('Сейчас нельзя вернуть фрагмент.');
        }
        setState(() => _removed[_activeIndex] = false);
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height && size.height < 500;
    final chunks = widget.manifest.chunks;
    final colors = Theme.of(context).colorScheme;
    final hasChunk = chunks.isNotEmpty;
    final i = hasChunk ? _activeIndex.clamp(0, chunks.length - 1) : 0;
    final chunk = hasChunk ? chunks[i] : null;
    final narrowNavigation = MediaQuery.sizeOf(context).width < 390 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.6;
    final jumpField = TextField(
      controller: _jumpController,
      keyboardType: TextInputType.number,
      onSubmitted: (_) => _jumpToNumber(),
      decoration: const InputDecoration(
        labelText: 'Номер фрагмента',
        border: OutlineInputBorder(),
      ),
    );
    final jumpButton = FilledButton.tonal(
      onPressed: _jumpToNumber,
      child: const Text('Перейти'),
    );
    return VoicePage(
      scrollController: _scroll,
      onCommand: _voiceCommand,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Исправить расшифровку'),
          actions: [
            if (landscape)
              IconButton(
                tooltip: 'Сохранить и озвучить',
                onPressed: _busy || !_hasChanges ? null : _submit,
                icon: const Icon(Icons.record_voice_over_rounded),
              ),
            IconButton(
              tooltip: 'Найти фрагмент',
              onPressed: hasChunk ? _chooseFragment : null,
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Исправляйте по одному фрагменту',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      const Text(
                          'После сохранения сервер создаст новую озвучку. '
                          'Для голосового перехода скажите «последний фрагмент» '
                          'или «фрагмент двадцать».'),
                      const SizedBox(height: 16),
                      if (!hasChunk)
                        const Text(
                            'В этой лекции нет фрагментов для исправления.'),
                      if (hasChunk) ...[
                        if (widget.manifest.chunks.any((c) => c.needsReview)) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text('Осталось проверить: $_remainingReview',
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.tonalIcon(
                              onPressed: _busy || _remainingReview == 0
                                  ? null
                                  : _nextUncertain,
                              icon: const Icon(Icons.rate_review_outlined),
                              label: const Text('Следующий сомнительный'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy || _reviewed.contains(chunk!.id)
                                  ? null
                                  : _confirmCurrent,
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Этот фрагмент верен'),
                            ),
                          ]),
                          const SizedBox(height: 12),
                        ],
                        Semantics(
                          liveRegion: true,
                          child: Text('Фрагмент ${i + 1} из ${chunks.length}',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          OutlinedButton(
                            onPressed: i > 0 ? () => _select(0) : null,
                            child: const Text('Первый'),
                          ),
                          OutlinedButton(
                            onPressed: i > 0 ? () => _select(i - 1) : null,
                            child: const Text('Предыдущий'),
                          ),
                          OutlinedButton(
                            onPressed: i < chunks.length - 1
                                ? () => _select(i + 1)
                                : null,
                            child: const Text('Следующий'),
                          ),
                          OutlinedButton(
                            onPressed: i < chunks.length - 1
                                ? () => _select(chunks.length - 1)
                                : null,
                            child: const Text('Последний'),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        if (narrowNavigation)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              jumpField,
                              const SizedBox(height: 8),
                              jumpButton
                            ],
                          )
                        else
                          Row(children: [
                            Expanded(child: jumpField),
                            const SizedBox(width: 8),
                            jumpButton,
                          ]),
                        TextButton.icon(
                          onPressed: _chooseFragment,
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('Найти по тексту'),
                        ),
                        if (chunk!.needsReview)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('Проверьте эту строку по фото'),
                          ),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(chunk.isFormula ? 'Формула' : 'Текст',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                ExpansionTile(
                                  key: ValueKey('photo_toggle_$i'),
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text('Сравнить со снимком'),
                                  children: [
                                    const Text(
                                        'Выделена область фрагмента на странице'),
                                    const SizedBox(height: 8),
                                    PhotoRegionOverview(
                                      imageFuture: _photoFuture,
                                      chunk: chunk,
                                      originalWidth:
                                          widget.manifest.imageWidth ?? 0,
                                      originalHeight:
                                          widget.manifest.imageHeight ?? 0,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Увеличенный участок'),
                                    const SizedBox(height: 8),
                                    PhotoLinePreview(
                                      imageFuture: _photoFuture,
                                      chunk: chunk,
                                      originalWidth:
                                          widget.manifest.imageWidth ?? 0,
                                      originalHeight:
                                          widget.manifest.imageHeight ?? 0,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_removed[i]) ...[
                                  const Text(
                                      'Этот фрагмент не войдёт в новую озвучку.'),
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                            setState(() => _removed[i] = false),
                                    icon: const Icon(Icons.undo_rounded),
                                    label: const Text('Вернуть фрагмент'),
                                  ),
                                ] else ...[
                                  TextFormField(
                                    key: ValueKey('transcript_text_$i'),
                                    controller: _textControllers[i],
                                    enabled: !_busy,
                                    minLines: 2,
                                    maxLines: 8,
                                    maxLength: 2000,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: const InputDecoration(
                                      labelText: 'Текст фрагмента',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty
                                            ? 'Введите текст фрагмента'
                                            : null,
                                  ),
                                  if (_awaitingDictation)
                                    Text(
                                      _dictatingPronunciation
                                          ? 'Снова нажмите микрофон и произнесите, как должен звучать фрагмент. Скажите «отмена» для отмены.'
                                          : 'Снова нажмите микрофон и произнесите новый текст. Скажите «отмена», чтобы не менять фрагмент.',
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            setState(() {
                                              _awaitingDictation = true;
                                              _dictatingPronunciation = false;
                                            });
                                            await VoiceScope.maybeOf(context)
                                                ?.beginDictation();
                                          },
                                    icon: const Icon(Icons.mic_rounded),
                                    label: const Text('Заменить текст голосом'),
                                  ),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Это формула'),
                                    subtitle: const Text(
                                        'Включите для озвучивания математических знаков'),
                                    value: _formulas[i],
                                    onChanged: _busy
                                        ? null
                                        : (value) => setState(
                                            () => _formulas[i] = value),
                                  ),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                        'Настроить произношение вручную'),
                                    value: _manualSpeech[i],
                                    onChanged: _busy
                                        ? null
                                        : (value) => setState(() =>
                                            _manualSpeech[i] = value ?? false),
                                  ),
                                  if (_manualSpeech[i])
                                    TextFormField(
                                      key: ValueKey('transcript_speech_$i'),
                                      controller: _spokenControllers[i],
                                      enabled: !_busy,
                                      minLines: 2,
                                      maxLines: 5,
                                      maxLength: 3000,
                                      decoration: const InputDecoration(
                                        labelText: 'Произнести как',
                                        hintText: 'Например: икс в квадрате',
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                              ? 'Введите произношение'
                                              : null,
                                    ),
                                  if (_manualSpeech[i])
                                    OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              setState(() {
                                                _awaitingDictation = true;
                                                _dictatingPronunciation = true;
                                              });
                                              await VoiceScope.maybeOf(context)
                                                  ?.beginDictation();
                                            },
                                      icon: const Icon(Icons.mic_rounded),
                                      label: const Text('Надиктовать произношение'),
                                    ),
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                            setState(() => _removed[i] = true),
                                    icon: const Icon(
                                        Icons.delete_outline_rounded),
                                    label: const Text(
                                        'Исключить ошибочный фрагмент'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_error.isNotEmpty) ErrorNotice(message: _error),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: landscape
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton.icon(
                  onPressed: _busy || !_hasChanges ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.record_voice_over_rounded),
                  label: Text(_busy
                      ? 'Создаём новую озвучку…'
                      : 'Сохранить и озвучить'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56)),
                ),
              ),
      ),
    );
  }
}
