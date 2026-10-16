import 'package:flutter/material.dart';
import 'app_haptics.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'lektoria_sprite.dart';
import 'models.dart';
import 'voice_navigation.dart';
import 'voice_commands.dart';
import 'app_preferences.dart';
import 'visual_system.dart';
import 'saved_notes_page.dart';
import 'user_error.dart';

enum LectureKind { text, formula, mixed }

LectureKind lectureKind(LectureRecord record) {
  final chunks = record.manifest?.chunks ?? [];
  if (chunks.isEmpty || chunks.every((chunk) => !chunk.isFormula)) {
    return LectureKind.text;
  }
  if (chunks.every((chunk) => chunk.isFormula)) return LectureKind.formula;
  return LectureKind.mixed;
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

String _duration(double seconds) {
  final minutes = (seconds / 60).floor();
  final remainder = seconds.round() % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.records,
    this.libraryController,
    required this.serverConfigured,
    required this.onOpen,
    required this.onCapture,
    required this.onSettings,
    this.onHelp,
    required this.onDelete,
    this.onRename,
    this.onSavedNotes,
  });

  final List<LectureRecord> records;
  final ValueNotifier<bool>? libraryController;
  final bool serverConfigured;
  final ValueChanged<LectureRecord> onOpen;
  final VoidCallback onCapture;
  final VoidCallback onSettings;
  final VoidCallback? onHelp;
  final Future<void> Function(LectureRecord) onDelete;
  final Future<void> Function(LectureRecord, String)? onRename;
  final VoidCallback? onSavedNotes;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _library = false;
  final _scroll = ScrollController();
  String _query = '';
  LectureKind? _filter;
  @override
  void initState() {
    super.initState();
    _library = widget.libraryController?.value ?? false;
    widget.libraryController?.addListener(_syncLibrary);
  }

  void _syncLibrary() {
    if (mounted) {
      _showLibrary(widget.libraryController?.value ?? false);
    }
  }

  void _showLibrary(bool value) {
    // The same scroll controller serves both views; keep a previous search
    // position from hiding the home hero or the library search field.
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _library = value);
  }

  @override
  void dispose() {
    widget.libraryController?.removeListener(_syncLibrary);
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _command(AppVoiceIntent intent) async {
    if (intent.command == AppCommand.library ||
        intent.command == AppCommand.home) {
      _showLibrary(intent.command == AppCommand.library);
      return true;
    }
    return false;
  }

  Future<void> _confirmDelete(LectureRecord record) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(children: [
          LectoriaSprite(pose: LectoriaPose.close, size: 48),
          SizedBox(width: 8),
          Expanded(child: Text('Удалить лекцию?')),
        ]),
        content: Text('«${record.title}» будет удалена с устройства.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (approved == true) {
      try {
        await widget.onDelete(record);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Лекция удалена')));
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(userError(error))));
        }
      }
    }
  }

  void _showActions(LectureRecord record) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                title: Text(record.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Открыть'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onOpen(record);
              },
            ),
            if (widget.onRename != null)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline_rounded),
                title: const Text('Переименовать'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showRenameLectureDialog(context, record, widget.onRename!);
                },
              ),
            if (record.manifest?.fullText.isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Скопировать распознанный текст'),
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: record.manifest!.fullText));
                  if (sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Текст скопирован')));
                  }
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Brand.coral),
              title: const Text('Удалить'),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(record);
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = widget.records.where((record) {
      final matchesKind = _filter == null || lectureKind(record) == _filter;
      final text =
          '${record.title} ${record.manifest?.fullText ?? ''}'.toLowerCase();
      return matchesKind && text.contains(_query.toLowerCase());
    }).toList();
    return VoicePage(
        scrollController: _scroll,
        onCommand: _command,
        child: PopScope(
          canPop: !_library,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _library) _showLibrary(false);
          },
          child: Scaffold(
            appBar: AppBar(
              leading: _library
                  ? IconButton(
                      tooltip: 'Вернуться к лекциям',
                      onPressed: () => _showLibrary(false),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  : null,
              title:
                  _library ? const Text('Библиотека') : const BrandWordmark(),
              actions: [
                if (widget.onSavedNotes != null)
                  IconButton(
                    tooltip: 'Все заметки и закладки',
                    onPressed: widget.onSavedNotes,
                    icon: const Icon(Icons.bookmarks_rounded),
                  ),
                if (widget.onHelp != null)
                  IconButton(
                    tooltip: 'Как пользоваться',
                    onPressed: widget.onHelp,
                    icon: const Icon(Icons.help_outline_rounded),
                  ),
                IconButton(
                  tooltip: 'Настройки',
                  onPressed: widget.onSettings,
                  icon: const Icon(Icons.settings_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: EditorialBackdrop(
                child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    controller: _scroll,
                    padding:
                        EdgeInsets.fromLTRB(20, 18, 20, _library ? 100 : 24),
                    children: _library
                        ? [
                            EditorialHeading(
                              kicker: 'архив конспектов',
                              title: 'Библиотека',
                              subtitle: widget.records.isEmpty
                                  ? 'Здесь будут снимки и озвученные лекции.'
                                  : 'Все записи под рукой. Ищите по названию или тексту.',
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search_rounded),
                                labelText: 'Поиск по лекциям',
                              ),
                            ),
                            const SizedBox(height: 14),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                _chip('Все', null),
                                _chip('Текст', LectureKind.text),
                                _chip('Формулы', LectureKind.formula),
                                _chip('Смешанные', LectureKind.mixed),
                              ]),
                            ),
                            const SizedBox(height: 20),
                            Text('Найдено: ${filtered.length}',
                                style:
                                    TextStyle(color: colors.onSurfaceVariant)),
                            const SizedBox(height: 12),
                            if (filtered.isEmpty)
                              _empty('Здесь пока нет лекций по вашему запросу'),
                            for (final record in filtered) ...[
                              LectureTile(
                                  record: record,
                                  ordinal: widget.records.indexOf(record) + 1,
                                  onTap: () => widget.onOpen(record),
                                  onMenu: () => _showActions(record)),
                              const SizedBox(height: 12),
                            ],
                          ]
                        : [
                            _hero(context),
                            const SizedBox(height: 22),
                            if (!widget.serverConfigured) ...[
                              Card(
                                  child: ListTile(
                                leading: const LectoriaSprite(
                                    pose: LectoriaPose.criticalWarning,
                                    size: 44),
                                title: const Text('Подключите сервер'),
                                subtitle: const Text(
                                    'Укажите адрес ноутбука в настройках.'),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: widget.onSettings,
                              )),
                              const SizedBox(height: 18),
                            ],
                            const SectionKicker('ваши записи'),
                            TextButton.icon(
                              onPressed: widget.onSavedNotes,
                              icon: const Icon(Icons.bookmarks_outlined),
                              label: const Text('Все заметки и закладки'),
                            ),
                            const SizedBox(height: 9),
                            Row(children: [
                              Expanded(
                                  child: Text('Недавние лекции',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge)),
                              TextButton(
                                  onPressed: () => _showLibrary(true),
                                  child: const Text('Все')),
                            ]),
                            const SizedBox(height: 8),
                            if (widget.records.isEmpty)
                              _empty(
                                  'Здесь появятся ваши лекции. Добавьте первый снимок.'),
                            for (final record in widget.records.take(4)) ...[
                              LectureTile(
                                  record: record,
                                  ordinal: widget.records.indexOf(record) + 1,
                                  onTap: () => widget.onOpen(record),
                                  onMenu: () => _showActions(record)),
                              const SizedBox(height: 12),
                            ],
                          ],
                  ),
                ),
              ),
            )),
            bottomNavigationBar: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border:
                        Border(top: BorderSide(color: colors.outlineVariant)),
                  ),
                  child: Row(children: [
                    for (final item in [
                      (false, 'Главная', Icons.home_outlined),
                    ])
                      Expanded(
                          child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Semantics(
                          selected: _library == item.$1,
                          button: true,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            decoration: BoxDecoration(
                              color: _library == item.$1
                                  ? colors.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 56),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                              ),
                              onPressed: () {
                                if (PreferencesScope.of(context).haptics) {
                                  AppHaptics.vibrate();
                                }
                                _showLibrary(item.$1);
                              },
                              icon: Icon(item.$3, size: 21),
                              label: Text(item.$2,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ),
                      )),
                    Semantics(
                      button: true,
                      label: 'Добавить лекцию',
                      child: IconButton.filled(
                        tooltip: 'Добавить лекцию',
                        onPressed: () {
                          if (PreferencesScope.of(context).haptics) {
                            AppHaptics.vibrate();
                          }
                          widget.onCapture();
                        },
                        iconSize: 30,
                        constraints:
                            const BoxConstraints(minWidth: 64, minHeight: 64),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Semantics(
                        selected: _library,
                        button: true,
                        child: AnimatedContainer(
                          duration: PreferencesScope.of(context).reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          decoration: BoxDecoration(
                            color: _library
                                ? colors.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 56),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                            ),
                            onPressed: () {
                              if (PreferencesScope.of(context).haptics) {
                                AppHaptics.vibrate();
                              }
                              _showLibrary(true);
                            },
                            icon: const Icon(Icons.library_books_outlined,
                                size: 21),
                            label: const Text('Библиотека',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                    ),
                  ]),
                )),
          ),
        ));
  }

  Widget _chip(String label, LectureKind? kind) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
            label: Text(label),
            selected: _filter == kind,
            onSelected: (_) => setState(() => _filter = kind)),
      );

  Widget _empty(String text) => Card(
          child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(children: [
          const LectoriaSprite(pose: LectoriaPose.idle, size: 90),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
        ]),
      ));

  Widget _hero(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contrast = PreferencesScope.of(context).highContrast;
    final largeType = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final light = Theme.of(context).brightness == Brightness.light;
    final ink = contrast || light ? scheme.onSurface : Colors.white;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: contrast ? scheme.surface : null,
        gradient: contrast
            ? null
            : LinearGradient(
                colors: light
                    ? const [
                        Color(0xFFE9F5F3),
                        Color(0xFFEAE8FA),
                        Color(0xFFF9EDE6)
                      ]
                    : const [
                        Color(0xFF151A3F),
                        Color(0xFF303774),
                        Color(0xFF563A88)
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: Border.all(
            color: contrast ? scheme.outline : Brand.violet,
            width: contrast ? 2 : 1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(34),
          topRight: Radius.circular(34),
          bottomRight: Radius.circular(34),
          bottomLeft: Radius.circular(8),
        ),
      ),
      child: Stack(children: [
        const Positioned(
            right: -32, top: -36, child: OrbitDecoration(size: 220)),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionKicker('ваша аудиостудия', light: !contrast && !light),
            const SizedBox(height: 16),
            if (largeType)
              const Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedLectoriaSprite(
                      pose: LectoriaPose.idle, size: 106))
            else
              Row(children: [
                Expanded(
                    child: Text('От страницы\nк голосу',
                        style: TextStyle(
                            color: ink,
                            fontSize: 29,
                            fontWeight: FontWeight.w800,
                            height: 1.08))),
                const AnimatedLectoriaSprite(
                    pose: LectoriaPose.idle, size: 114),
              ]),
            if (largeType)
              Text('От страницы к голосу',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: ink)),
            const SizedBox(height: 8),
            Text(
                'Снимите конспект. Лектория превратит его в лекцию, которую можно слушать и исправлять.',
                style: TextStyle(
                    color: contrast || light ? ink : const Color(0xFFE3E8FF),
                    fontSize: 15,
                    height: 1.42)),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: contrast || light
                    ? scheme.primary
                    : const Color(0xFFA8F5EC),
                foregroundColor: contrast || light
                    ? scheme.onPrimary
                    : const Color(0xFF102A39),
              ),
              onPressed: widget.onCapture,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Сделать снимок'),
            ),
            if (widget.records.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => widget.onOpen(widget.records.first),
                style: TextButton.styleFrom(
                    foregroundColor: ink,
                    minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: Text(
                    widget.records.first.lastPositionMs > 0
                        ? 'Продолжить с ${_duration(widget.records.first.lastPositionMs / 1000)}: ${widget.records.first.title}'
                        : 'Открыть: ${widget.records.first.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
            if (!largeType) ...[
              const SizedBox(height: 18),
              Row(children: [
                for (final step in ['01  СНИМОК', '02  ТЕКСТ', '03  ГОЛОС'])
                  Expanded(
                      child: Text(step,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: contrast || light
                                  ? ink
                                  : const Color(0xFFB9C7EC),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class LectureTile extends StatelessWidget {
  const LectureTile(
      {super.key,
      required this.record,
      required this.onTap,
      required this.onMenu,
      this.ordinal});
  final LectureRecord record;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final int? ordinal;

  @override
  Widget build(BuildContext context) {
    final kind = lectureKind(record);
    final duration = record.manifest?.totalDuration ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final kindLabel = switch (kind) {
      LectureKind.text => 'ТЕКСТ',
      LectureKind.formula => 'ФОРМУЛЫ',
      LectureKind.mixed => 'ТЕКСТ + ФОРМУЛЫ',
    };
    final status = switch (record.status) {
      'completed' => 'Готово',
      'failed' => 'Ошибка',
      'processing' => 'Обрабатывается',
      _ => 'В очереди',
    };
    final resume = record.status == 'completed' && record.lastPositionMs > 0
        ? 'Продолжить с ${_duration(record.lastPositionMs / 1000)}'
        : null;
    return Semantics(
      button: true,
      label:
          '${ordinal == null ? '' : 'Лекция $ordinal. '}${record.title}, ${_date(record.createdAt)}, $status${duration > 0 ? ', ${_duration(duration)}' : ''}${resume == null ? '' : ', $resume'}',
      child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (PreferencesScope.of(context).haptics) {
                AppHaptics.vibrate();
              }
              onTap();
            },
            onLongPress: onMenu,
            borderRadius: BorderRadius.circular(24),
            child: IntrinsicHeight(
                child: Row(children: [
              Container(
                  width: 5,
                  color: record.status == 'failed'
                      ? scheme.error
                      : scheme.secondary),
              Expanded(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 15, 6, 15),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((ordinal ?? 1).toString().padLeft(2, '0'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800)),
                      const SizedBox(width: 13),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(kindLabel,
                              style: TextStyle(
                                  color: scheme.secondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .9)),
                          const SizedBox(height: 5),
                          Text(record.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                              '${_date(record.createdAt)}  ·  ${duration > 0 ? _duration(duration) : status}',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                          if (resume != null) ...[
                            const SizedBox(height: 5),
                            Text(resume,
                                style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ],
                      )),
                    ]),
              )),
              IconButton(
                  tooltip: 'Действия с лекцией',
                  onPressed: onMenu,
                  icon: const Icon(Icons.more_vert_rounded)),
            ])),
          )),
    );
  }
}
