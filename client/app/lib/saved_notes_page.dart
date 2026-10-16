import 'package:flutter/material.dart';

import 'models.dart';
import 'user_error.dart';
import 'visual_system.dart';
import 'voice_commands.dart';
import 'voice_navigation.dart';

/// All saved lecture notes and their marked passages, across the library.
class SavedNotesPage extends StatefulWidget {
  const SavedNotesPage(
      {super.key,
      required this.records,
      required this.onOpen,
      required this.onRename});

  final List<LectureRecord> records;
  final void Function(LectureRecord, String?) onOpen;
  final Future<void> Function(LectureRecord, String) onRename;

  @override
  State<SavedNotesPage> createState() => _SavedNotesPageState();
}

class _SavedNotesPageState extends State<SavedNotesPage> {
  Future<void> _rename(LectureRecord record, String title) async {
    await widget.onRename(record, title);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = <(LectureRecord, int)>[
      for (final record in widget.records)
        for (final index in record.bookmarkIndexes) (record, index),
    ];
    return VoicePage(
      onCommand: (intent) async {
        if (intent.command == AppCommand.bookmark && intent.number != null) {
          final ordinal = intent.number! - 1;
          if (ordinal >= 0 && ordinal < entries.length) {
            final (record, index) = entries[ordinal];
            widget.onOpen(record, record.manifest!.chunks[index].id);
            return true;
          }
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Все заметки')),
        body: EditorialBackdrop(
            child: SafeArea(
                child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                const EditorialHeading(
                  kicker: 'ваша коллекция',
                  title: 'Заметки и закладки',
                  subtitle:
                      'Откройте лекцию или перейдите сразу к отмеченной строке.',
                ),
                const SizedBox(height: 16),
                if (widget.records.isEmpty)
                  const Card(
                      child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                        'Заметок пока нет. Добавьте первый снимок на главном экране.'),
                  )),
                for (final record in widget.records) ...[
                  Card(
                      child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: TextButton(
                            onPressed: () => widget.onOpen(record, null),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(record.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium)),
                          )),
                          IconButton(
                            tooltip: 'Переименовать лекцию',
                            onPressed: () => showRenameLectureDialog(
                                context, record, _rename),
                            icon: const Icon(
                                Icons.drive_file_rename_outline_rounded),
                          ),
                        ]),
                        if (record.bookmarkIndexes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Text('Закладок нет',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          ),
                        for (final index in record.bookmarkIndexes)
                          ListTile(
                            leading: const Icon(Icons.bookmark_rounded),
                            title: Text(record.manifest!.chunks[index].text,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('Фрагмент ${index + 1}'),
                            onTap: () => widget.onOpen(
                                record, record.manifest!.chunks[index].id),
                          ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ))),
      ),
    );
  }
}

Future<void> showRenameLectureDialog(BuildContext context, LectureRecord record,
    Future<void> Function(LectureRecord, String) onRename) async {
  final controller = TextEditingController(text: record.title);
  try {
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Название лекции'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Как назвать лекцию'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (title == null || title.isEmpty || !context.mounted) return;
    await onRename(record, title);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(userError(error), style: const TextStyle(fontSize: 16)),
      ));
    }
  } finally {
    controller.dispose();
  }
}
