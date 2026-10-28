import 'package:flutter/material.dart';

import 'models.dart';
import 'visual_system.dart';
import 'voice_commands.dart';
import 'voice_navigation.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage(
      {super.key,
      required this.record,
      required this.onSelect,
      required this.onRemove});

  final LectureRecord record;
  final ValueChanged<int> onSelect;
  final Future<void> Function(int) onRemove;

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chunks = widget.record.manifest?.chunks ?? const <LectureChunk>[];
    final indexes = widget.record.bookmarkIndexes;
    return VoicePage(
        scrollController: _scroll,
        onCommand: (intent) async {
          if (intent.command == AppCommand.fragment && intent.number != null) {
            final index = intent.number! - 1;
            if (indexes.contains(index)) {
              widget.onSelect(index);
              return true;
            }
          }
          if (intent.command == AppCommand.bookmark && intent.number != null) {
            final ordinal = intent.number! - 1;
            if (ordinal >= 0 && ordinal < indexes.length) {
              widget.onSelect(indexes[ordinal]);
              return true;
            }
          }
          return false;
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Закладки')),
          body: EditorialBackdrop(
            child: SafeArea(
                child: Center(
                    child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  const EditorialHeading(
                    kicker: 'быстрые переходы',
                    title: 'Избранные места',
                    subtitle: 'Нажмите строку или скажите «закладка два», '
                        'чтобы перейти к ней в записи.',
                  ),
                  const SizedBox(height: 22),
                  if (indexes.isEmpty)
                    const Card(
                        child: Padding(
                      padding: EdgeInsets.all(22),
                      child: Text(
                          'Закладок пока нет. Во время прослушивания нажмите значок закладки у нужного фрагмента.'),
                    )),
                  for (final index in indexes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                          child: Row(children: [
                        Expanded(
                            child: InkWell(
                          onTap: () => widget.onSelect(index),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'ФРАГМЕНТ ${index + 1}  ·  ${_time(chunks[index].startTime)}',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 7),
                                  Text(chunks[index].text,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge),
                                ]),
                          ),
                        )),
                        IconButton(
                          tooltip: 'Убрать закладку у фрагмента ${index + 1}',
                          constraints: const BoxConstraints(
                              minWidth: 64, minHeight: 64),
                          onPressed: () async {
                            await widget.onRemove(index);
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.bookmark_remove_outlined),
                        ),
                      ])),
                    ),
                ],
              ),
            ))),
          ),
        ));
  }
}

String _time(double seconds) {
  final duration = Duration(milliseconds: (seconds * 1000).round());
  return '${duration.inMinutes.toString().padLeft(2, '0')}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
