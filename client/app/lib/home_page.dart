import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'models.dart';

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
    required this.serverConfigured,
    required this.onOpen,
    required this.onCapture,
    required this.onSettings,
    required this.onDelete,
  });

  final List<LectureRecord> records;
  final bool serverConfigured;
  final ValueChanged<LectureRecord> onOpen;
  final VoidCallback onCapture;
  final VoidCallback onSettings;
  final Future<void> Function(LectureRecord) onDelete;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _library = false;
  String _query = '';
  LectureKind? _filter;

  Future<void> _confirmDelete(LectureRecord record) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить лекцию?'),
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
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Не удалось удалить лекцию: $error')));
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
    return PopScope(
      canPop: !_library,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _library) setState(() => _library = false);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _library
              ? IconButton(
                  tooltip: 'Вернуться к лекциям',
                  onPressed: () => setState(() => _library = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          title: _library
              ? const Text('Библиотека')
              : const Row(children: [
                  LectoriaMascot(size: 48),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text('Мои лекции',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
          actions: [
            IconButton(
              tooltip: 'Настройки',
              onPressed: widget.onSettings,
              icon: const Icon(Icons.settings_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: _library ? const LectoriaMascot(size: 64) : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 12, 20, _library ? 100 : 24),
                children: _library
                    ? [
                        TextField(
                          onChanged: (value) => setState(() => _query = value),
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
                            style: TextStyle(color: colors.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        if (filtered.isEmpty)
                          _empty('Здесь пока нет лекций по вашему запросу'),
                        for (final record in filtered) ...[
                          LectureTile(
                              record: record,
                              onTap: () => widget.onOpen(record),
                              onMenu: () => _showActions(record)),
                          const SizedBox(height: 12),
                        ],
                      ]
                    : [
                        _hero(context),
                        const SizedBox(height: 18),
                        if (!widget.serverConfigured) ...[
                          Card(
                              child: ListTile(
                            leading: const Icon(Icons.wifi_off_rounded),
                            title: const Text('Подключите сервер'),
                            subtitle: const Text(
                                'Укажите адрес ноутбука в настройках.'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: widget.onSettings,
                          )),
                          const SizedBox(height: 18),
                        ],
                        Row(children: [
                          Expanded(
                              child: Text('Недавние лекции',
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                          TextButton(
                              onPressed: () => setState(() => _library = true),
                              child: const Text('Все')),
                        ]),
                        const SizedBox(height: 8),
                        if (widget.records.isEmpty)
                          _empty(
                              'Здесь появятся ваши лекции. Добавьте первый снимок.'),
                        for (final record in widget.records.take(4)) ...[
                          LectureTile(
                              record: record,
                              onTap: () => widget.onOpen(record),
                              onMenu: () => _showActions(record)),
                          const SizedBox(height: 12),
                        ],
                      ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(top: BorderSide(color: colors.outlineVariant))),
            child: Row(children: [
              Expanded(
                  child: _navButton(Icons.library_books_rounded, 'Библиотека',
                      _library, () => setState(() => _library = true))),
              Expanded(
                  child: Semantics(
                button: true,
                label: 'Новая лекция',
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onCapture();
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: const BoxDecoration(
                          color: Brand.gold, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Brand.indigo, size: 31),
                    ),
                    const SizedBox(height: 3),
                    Text('Новая лекция',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium),
                  ]),
                ),
              )),
              Expanded(
                  child: _navButton(Icons.settings_rounded, 'Настройки', false,
                      widget.onSettings)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _navButton(
          IconData icon, String label, bool selected, VoidCallback onTap) =>
      Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
                height: 84,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 27),
                      const SizedBox(height: 6),
                      Text(label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium),
                    ])),
          ));

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
          const LectoriaMascot(size: 90),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
        ]),
      ));

  Widget _hero(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
              colors: [Brand.indigo, Color(0xFF423374)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Конспект становится голосом',
                    style: TextStyle(
                        color: Brand.cream,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
                const SizedBox(height: 10),
                const Text('Снимите страницу и слушайте в своём темпе.',
                    style: TextStyle(color: Brand.cream, fontSize: 16)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Brand.gold,
                      foregroundColor: Brand.indigo),
                  onPressed: widget.onCapture,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Новая лекция'),
                ),
              ])),
          const SizedBox(width: 6),
          const LectoriaMascot(size: 98, mood: MascotMood.welcome),
        ]),
      );
}

class LectureTile extends StatelessWidget {
  const LectureTile(
      {super.key,
      required this.record,
      required this.onTap,
      required this.onMenu});
  final LectureRecord record;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final kind = lectureKind(record);
    final duration = record.manifest?.totalDuration ?? 0;
    final status = switch (record.status) {
      'completed' => 'Готово',
      'failed' => 'Ошибка',
      'processing' => 'Обрабатывается',
      _ => 'В очереди',
    };
    return Semantics(
      button: true,
      label:
          '${record.title}, ${_date(record.createdAt)}, $status${duration > 0 ? ', ${_duration(duration)}' : ''}',
      child: Card(
          child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onMenu,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(15)),
                child: Icon(
                    switch (kind) {
                      LectureKind.text => Icons.article_rounded,
                      LectureKind.formula => Icons.functions_rounded,
                      LectureKind.mixed => Icons.auto_stories_rounded
                    },
                    color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(record.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                        '${_date(record.createdAt)} · ${duration > 0 ? _duration(duration) : status}',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ])),
              IconButton(
                  tooltip: 'Действия с лекцией',
                  onPressed: onMenu,
                  icon: const Icon(Icons.more_vert_rounded)),
            ])),
      )),
    );
  }
}
