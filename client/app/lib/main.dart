import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart' as share;

import 'api.dart';
import 'app_theme.dart';
import 'app_preferences.dart';
import 'app_haptics.dart';
import 'camera_guidance_page.dart';
import 'capture_review_page.dart';
import 'settings_page.dart';
import 'voice_navigation.dart';
export 'settings_page.dart';
import 'lektoria_sprite.dart';
import 'capture_page.dart';
import 'home_page.dart';
import 'lecture_view.dart';
import 'models.dart';
import 'storage.dart';
import 'transcript_editor.dart';
import 'voice_commands.dart';
import 'welcome_page.dart';
import 'help_page.dart';
import 'splash_page.dart';
import 'bookmarks_page.dart';
import 'user_error.dart';
import 'saved_notes_page.dart';
import 'lecture_export.dart';
import 'lecture_timeline.dart';
import 'formula_breakdown.dart';
import 'library_backup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.lecture_reader.playback',
    androidNotificationChannelName: 'Озвученные лекции',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: false,
    androidNotificationIcon: 'mipmap/ic_lektoria',
  );
  runApp(const LectureReaderApp());
}

class LectureReaderApp extends StatefulWidget {
  const LectureReaderApp({super.key});

  @override
  State<LectureReaderApp> createState() => _LectureReaderAppState();
}

class _LectureReaderAppState extends State<LectureReaderApp> {
  final _picker = ImagePicker();
  final _navigator = GlobalKey<NavigatorState>();
  final _voice = VoiceNavigation();
  final _library = ValueNotifier<bool>(false);
  final _themePreview = ValueNotifier<ThemeData?>(null);
  final Set<String> _openRoutes = {};
  bool _cameraFlowActive = false;
  AppPreferences _preferences = const AppPreferences();
  bool _preferencesLoaded = false;
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
    _voice.globalHandler = _globalCommand;
    _load();
  }

  Future<void> _load() async {
    final started = DateTime.now();
    try {
      final storage = await LectureStorage.open();
      final settings = await storage.readSettings();
      if (mounted) {
        setState(() {
          _preferences = AppPreferences.fromJson(settings);
          _preferencesLoaded = true;
        });
      }
      final records = await storage.readAll();
      final lost = await _picker.retrieveLostData();
      final recoveredPhoto = !lost.isEmpty && lost.files?.isNotEmpty == true
          ? lost.files!.first
          : null;
      final remaining = const Duration(milliseconds: 1650) -
          DateTime.now().difference(started);
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
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
            .clamp(0.8, 3.0)
            .toDouble();
        _welcomeDone = settings['welcome_done'] == true;
        _preferences = AppPreferences.fromJson(settings);
        _voice.server = _server;
        _voice.preferences = _preferences;
      });
      if (recoveredPhoto != null && _server.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(_reviewRecoveredPhoto(recoveredPhoto)));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = userError(error));
      }
    }
  }

  Future<void> _saveSettings(String server, ThemeMode theme, double scale,
      [AppPreferences? preferences]) async {
    if (server.trim().isNotEmpty) RecognitionApi.parseServerAddress(server);
    await _storage!.saveSettings({
      'server': server.trim(),
      'theme': theme.name,
      'text_scale': scale,
      'welcome_done': _welcomeDone,
      ...(preferences ?? _preferences).toJson(),
    });
    setState(() {
      _server = server.trim();
      _theme = theme;
      _textScale = scale;
      _preferences = preferences ?? _preferences;
      _voice.server = _server;
      _voice.preferences = _preferences;
    });
    if (!_preferences.showVoiceDock) unawaited(_voice.stop());
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
      while (true) {
        if (!context.mounted) return;
        final image = await _picker.pickImage(
          source: source,
          requestFullMetadata: false,
        );
        if (image == null || !context.mounted) return;
        final choice = await _reviewCapture(context, image,
            source == ImageSource.camera ? 'Переснять' : 'Выбрать другое фото');
        if (choice == null || !context.mounted) return;
        if (choice == CaptureDecision.retry) continue;
        await _saveAndOpen(context, image);
        return;
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, userError(error));
      }
    }
  }

  Future<CaptureDecision?> _reviewCapture(
          BuildContext context, XFile image, String retryLabel) =>
      Navigator.of(context).push<CaptureDecision>(MaterialPageRoute(
        settings: const RouteSettings(name: 'capture_review'),
        builder: (_) => CaptureReviewPage(photo: image, retryLabel: retryLabel),
      ));

  Future<void> _saveAndOpen(BuildContext context, XFile image) async {
    final record = await _makeRecord(_storage!, _server, image);
    _records.insert(0, record);
    await _persist();
    if (context.mounted) _open(context, record);
  }

  Future<void> _reviewRecoveredPhoto(XFile image) async {
    final context = _navigator.currentContext;
    if (context == null || !context.mounted) return;
    try {
      final choice = await _reviewCapture(context, image, 'Снять другое фото');
      if (!context.mounted) return;
      if (choice == CaptureDecision.use) {
        await _saveAndOpen(context, image);
      } else if (choice == CaptureDecision.retry) {
        _openCapture(context);
      }
    } catch (error) {
      if (context.mounted) _showMessage(context, userError(error));
    }
  }

  Future<void> _retryFailed(BuildContext context, LectureRecord old) async {
    try {
      if (!await File(old.imagePath).exists()) {
        throw const FileSystemException('Снимок больше не сохранён');
      }
      final record = await _makeRecord(
        _storage!,
        _server.isNotEmpty ? _server : old.serverBase,
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
      if (context.mounted) _showMessage(context, userError(error));
    }
  }

  void _open(BuildContext context, LectureRecord record) {
    final pages = _pagesFor(record);
    final resume = pages.where((page) => page.lastPositionMs > 0).toList();
    _pushLecture(Navigator.of(context), resume.isEmpty ? record : resume.last);
  }

  void _pushLecture(NavigatorState navigator, LectureRecord record,
      {String? initialChunkId, Duration? initialPosition,
      bool replace = false, bool autoPlay = false, bool editOnOpen = false}) {
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'lecture'),
      builder: (_) => LecturePage(
        record: record,
        initialChunkId: initialChunkId,
        initialPosition: initialPosition,
        autoPlay: autoPlay,
        editOnOpen: editOnOpen,
        storage: _storage!,
        onChanged: _persist,
        currentServer: () => _server,
        pages: () => _pagesFor(record),
        onOpenPage: (pageContext, page, start) => _pushLecture(
            Navigator.of(pageContext), page, replace: true, autoPlay: start),
        onOpenPageAtChunk: (pageContext, page, chunkId) => _pushLecture(
            Navigator.of(pageContext), page,
            replace: true, initialChunkId: chunkId),
        onOpenPageAtTime: (pageContext, page, time, start) => _pushLecture(
            Navigator.of(pageContext), page,
            replace: true, initialPosition: time, autoPlay: start),
        onEditPage: (pageContext, page) => _pushLecture(
            Navigator.of(pageContext), page,
            replace: true, editOnOpen: true),
        onAddPage: (pageContext) => _addPage(pageContext, record),
        onMovePage: (page, offset) => _movePage(page, offset),
        onRemovePage: (pageContext, page) =>
            _removePage(pageContext, page, current: record),
        onRetryFailed: (pageContext) => _retryFailed(pageContext, record),
      ),
    );
    if (replace) {
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
  }

  List<LectureRecord> _pagesFor(LectureRecord record) => _records
      .where((page) => page.lectureId == record.lectureId)
      .toList()
    ..sort((a, b) => a.pageOrder.compareTo(b.pageOrder));

  Future<void> _addPage(BuildContext context, LectureRecord parent) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Снять следующую страницу'),
            onTap: () => Navigator.pop(sheet, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Выбрать страницу из галереи'),
            onTap: () => Navigator.pop(sheet, ImageSource.gallery)),
        ])),
    );
    if (source == null || !context.mounted) return;
    try {
      final image = source == ImageSource.camera
          ? await Navigator.of(context).push<XFile>(MaterialPageRoute(
              settings: const RouteSettings(name: 'camera'),
              builder: (_) => const CameraGuidancePage()))
          : await _picker.pickImage(source: ImageSource.gallery,
              requestFullMetadata: false);
      if (image == null || !context.mounted) return;
      final decision = await _reviewCapture(context, image, 'Выбрать другое фото');
      if (decision != CaptureDecision.use || !context.mounted) return;
      final pages = _pagesFor(parent);
      final added = await _makeRecord(_storage!, _server, image);
      final priorSeriesId = parent.seriesId;
      if (parent.seriesId.isEmpty) parent.seriesId = parent.taskId;
      added.seriesId = parent.seriesId;
      added.pageOrder = pages.length;
      added.customTitle = pages.first.customTitle;
      _records.insert(0, added);
      try {
        await _persist();
      } catch (_) {
        _records.remove(added);
        parent.seriesId = priorSeriesId;
        rethrow;
      }
      if (context.mounted) {
        _pushLecture(Navigator.of(context), added, replace: true);
      }
    } catch (error) {
      if (context.mounted) _showMessage(context, userError(error));
    }
  }

  Future<void> _movePage(LectureRecord page, int offset) async {
    final pages = _pagesFor(page);
    final previous = {for (final item in pages) item: item.pageOrder};
    final previousTitles = {for (final item in pages) item: item.customTitle};
    final lectureTitle = pages.first.customTitle;
    final index = pages.indexOf(page);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= pages.length) return;
    pages.removeAt(index);
    pages.insert(target, page);
    for (var i = 0; i < pages.length; i++) {
      pages[i].pageOrder = i;
    }
    if (lectureTitle.isNotEmpty) pages.first.customTitle = lectureTitle;
    try {
      await _persist();
    } catch (_) {
      for (final item in previous.entries) {
        item.key.pageOrder = item.value;
      }
      for (final item in previousTitles.entries) {
        item.key.customTitle = item.value;
      }
      rethrow;
    }
  }

  Future<void> _removePage(BuildContext context, LectureRecord page,
      {required LectureRecord current}) async {
    final pages = _pagesFor(page);
    if (pages.length < 2) return;
    final previous = List<LectureRecord>.from(_records);
    final previousOrders = {for (final item in pages) item: item.pageOrder};
    final previousTitles = {for (final item in pages) item: item.customTitle};
    final lectureTitle = pages.first.customTitle;
    final next = pages.firstWhere((item) => item != page);
    _records.remove(page);
    pages.remove(page);
    for (var i = 0; i < pages.length; i++) {
      pages[i].pageOrder = i;
    }
    if (lectureTitle.isNotEmpty) pages.first.customTitle = lectureTitle;
    try {
      await _persist();
    } catch (_) {
      _records = previous;
      for (final item in previousOrders.entries) {
        item.key.pageOrder = item.value;
      }
      for (final item in previousTitles.entries) {
        item.key.customTitle = item.value;
      }
      rethrow;
    }
    for (final path in [page.imagePath, page.audioPath]) {
      if (path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // The page is already removed from the library; a later storage
          // cleanup may remove an orphaned file.
        }
      }
    }
    if (context.mounted && current == page) {
      _pushLecture(Navigator.of(context), next, replace: true);
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(message, style: const TextStyle(fontSize: 16)),
    ));
  }

  Future<void> _finishWelcome() async {
    await _storage!.saveSettings({
      'server': _server,
      'theme': _theme.name,
      'text_scale': _textScale,
      'welcome_done': true,
      ..._preferences.toJson(),
    });
    if (mounted) setState(() => _welcomeDone = true);
  }

  void _openSettings(BuildContext context) {
    if (!_openRoutes.add('settings')) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'settings'),
          builder: (_) => SettingsPage(
            server: _server,
            theme: _theme,
            scale: _textScale,
            onSave: _saveSettings,
            preferences: _preferences,
            themePreview: _themePreview,
            onSaveAll: (server, theme, scale, preferences) =>
                _saveSettings(server, theme, scale, preferences),
            unusedAudioBytes: () => _storage!.unusedAudioBytes(_records),
            clearUnusedAudio: () => _storage!.clearUnusedAudio(_records),
          ),
        ))
        .whenComplete(() => _openRoutes.remove('settings'));
  }

  void _openCapture(BuildContext context) {
    if (!_openRoutes.add('capture')) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'capture'),
          builder: (captureContext) => CapturePage(
            onCamera: () => _openLiveCamera(captureContext),
            onGallery: () => _pickAndOpen(captureContext, ImageSource.gallery),
            onSystemCamera: () =>
                _pickAndOpen(captureContext, ImageSource.camera),
          ),
        ))
        .whenComplete(() => _openRoutes.remove('capture'));
  }

  Future<void> _deleteRecord(LectureRecord record) async {
    final previous = List<LectureRecord>.from(_records);
    final pages = _pagesFor(record);
    _records.removeWhere((page) => page.lectureId == record.lectureId);
    try {
      await _persist();
    } catch (_) {
      _records = previous;
      rethrow;
    }
    for (final path in [for (final page in pages) ...[page.imagePath, page.audioPath]]) {
      if (path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // A failed file deletion must not restore records whose other files
        // have already been removed.
      }
    }
  }

  Future<void> _renameRecord(LectureRecord record, String title) async {
    final pages = _pagesFor(record);
    final previous = {for (final page in pages) page: page.customTitle};
    for (final page in pages) {
      page.customTitle = title.trim();
    }
    try {
      await _persist();
    } catch (_) {
      for (final item in previous.entries) {
        item.key.customTitle = item.value;
      }
      rethrow;
    }
  }

  Future<void> _backupLibrary(BuildContext context) async {
    try {
      final file = await LibraryBackup.create(_storage!, _records);
      await share.SharePlus.instance.share(share.ShareParams(
        title: 'Резервная копия библиотеки Лектории',
        files: [share.XFile(file.path, mimeType: 'application/zip')],
      ));
    } catch (error) {
      if (context.mounted) _showMessage(context, userError(error));
    }
  }

  Future<void> _restoreLibrary(BuildContext context) async {
    String? path;
    try {
      path = await const MethodChannel('lektoria/backup')
          .invokeMethod<String>('pickArchive');
      if (path == null || !context.mounted) return;
      final count = await LibraryBackup.restore(_storage!, _records, path);
      _records = await _storage!.readAll();
      if (mounted) setState(() {});
      if (context.mounted) {
        _showMessage(context, count == 0
            ? 'Все лекции из копии уже есть на телефоне'
            : 'Восстановлено лекций: $count');
      }
    } catch (error) {
      if (context.mounted) _showMessage(context, userError(error));
    } finally {
      if (path != null) {
        final temporary = File(path);
        if (await temporary.exists()) await temporary.delete();
      }
    }
  }

  void _openSavedNotes(BuildContext context) {
    if (!_openRoutes.add('saved_notes')) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'saved_notes'),
          builder: (pageContext) => SavedNotesPage(
            records: _records,
            onOpen: (record, chunkId) {
              Navigator.of(pageContext).pop();
              _pushLecture(Navigator.of(context), record,
                  initialChunkId: chunkId);
            },
            onRename: _renameRecord,
          ),
        ))
        .whenComplete(() => _openRoutes.remove('saved_notes'));
  }

  @override
  void dispose() {
    _voice.dispose();
    _library.dispose();
    _themePreview.dispose();
    super.dispose();
  }

  Future<void> _openLiveCamera(BuildContext context) async {
    if (_cameraFlowActive) return;
    if (_server.isEmpty) {
      _showMessage(context, 'Сначала укажите адрес сервера');
      return;
    }
    _cameraFlowActive = true;
    try {
      while (true) {
        if (!context.mounted) return;
        final image = await Navigator.of(context).push<XFile>(MaterialPageRoute(
            settings: const RouteSettings(name: 'camera'),
            builder: (_) => const CameraGuidancePage()));
        if (image == null || !context.mounted) return;
        final choice = await _reviewCapture(context, image, 'Переснять');
        if (choice == null || !context.mounted) return;
        if (choice == CaptureDecision.retry) continue;
        await _saveAndOpen(context, image);
        return;
      }
    } catch (error) {
      if (context.mounted) _showMessage(context, userError(error));
    } finally {
      _cameraFlowActive = false;
    }
  }

  void _showVoiceHelp() {
    final context = _navigator.currentContext;
    if (context == null || !_openRoutes.add('help')) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'help'),
          builder: (_) => const HelpPage(),
        ))
        .whenComplete(() => _openRoutes.remove('help'));
  }

  Future<bool> _globalCommand(AppVoiceIntent intent) async {
    final navigator = _navigator.currentState;
    final context = _navigator.currentContext;
    if (navigator == null || context == null || _storage == null) return false;
    switch (intent.command) {
      case AppCommand.home:
      case AppCommand.library:
        if (!_welcomeDone) await _finishWelcome();
        navigator.popUntil((route) => route.isFirst);
        _library.value = intent.command == AppCommand.library;
        return true;
      case AppCommand.settings:
        _openSettings(context);
        return true;
      case AppCommand.notes:
        _openSavedNotes(context);
        return true;
      case AppCommand.camera:
        unawaited(_openLiveCamera(context));
        return true;
      case AppCommand.gallery:
        unawaited(_pickAndOpen(context, ImageSource.gallery));
        return true;
      case AppCommand.back:
        if (navigator.canPop()) {
          navigator.pop();
          return true;
        }
        return false;
      case AppCommand.help:
        _showVoiceHelp();
        return true;
      case AppCommand.helpTopic:
        if (!_openRoutes.add('help')) return true;
        navigator
            .push(MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'help'),
              builder: (_) =>
                  HelpPage(initialTopic: HelpPage.topicFor(intent.section)),
            ))
            .whenComplete(() => _openRoutes.remove('help'));
        return true;
      case AppCommand.start:
        if (!_welcomeDone) await _finishWelcome();
        return true;
      case AppCommand.openLecture:
        final index = (intent.number ?? 1) - 1;
        final lectureIds = <String>[];
        for (final item in _records) {
          if (!lectureIds.contains(item.lectureId)) {
            lectureIds.add(item.lectureId);
          }
        }
        if (index < 0 || index >= lectureIds.length) {
          throw RangeError('Нет лекции с таким номером');
        }
        final pages = _records.where((item) => item.lectureId == lectureIds[index]).toList()
          ..sort((a, b) => a.pageOrder.compareTo(b.pageOrder));
        // Remove an existing player before opening another lecture. Otherwise
        // both routes can retain active audio after a voice command.
        navigator.popUntil((route) => route.isFirst);
        _pushLecture(navigator, pages.first);
        return true;
      case AppCommand.light:
        await _saveSettings(_server, ThemeMode.light, _textScale);
        return true;
      case AppCommand.dark:
        await _saveSettings(_server, ThemeMode.dark, _textScale);
        return true;
      case AppCommand.contrast:
        await _saveSettings(
            _server,
            _theme,
            _textScale,
            AppPreferences.fromJson(
                {..._preferences.toJson(), 'high_contrast': true}));
        return true;
      case AppCommand.larger:
        await _saveSettings(_server, _theme, (_textScale + .1).clamp(.8, 3));
        return true;
      case AppCommand.smaller:
        await _saveSettings(_server, _theme, (_textScale - .1).clamp(.8, 3));
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Лектория.Ai',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      themeMode: _theme,
      theme: AppTheme.light(
          highContrast: _preferences.highContrast,
          reduceMotion: _preferences.reduceMotion,
          boldText: _preferences.boldText,
          palette: _preferences.palette,
          fontMode: _preferences.fontMode,
          letterSpacing: _preferences.letterSpacing,
          lineHeight: _preferences.lineHeight),
      darkTheme: AppTheme.dark(
          highContrast: _preferences.highContrast,
          reduceMotion: _preferences.reduceMotion,
          boldText: _preferences.boldText,
          palette: _preferences.palette,
          fontMode: _preferences.fontMode,
          letterSpacing: _preferences.letterSpacing,
          lineHeight: _preferences.lineHeight),
      builder: (context, child) => ValueListenableBuilder<ThemeData?>(
          valueListenable: _themePreview,
          builder: (context, preview, _) {
            final effectiveTheme = preview ?? Theme.of(context);
            final light = effectiveTheme.brightness == Brightness.light;
            final landscape = MediaQuery.sizeOf(context).width >
                MediaQuery.sizeOf(context).height;
            final dock = Theme(
                data: effectiveTheme,
                child: VoiceDock(
                    voice: _voice, onHelp: _showVoiceHelp, compact: landscape));
            return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness:
                        light ? Brightness.dark : Brightness.light,
                    systemNavigationBarColor: landscape
                        ? effectiveTheme.colorScheme.surface
                        : effectiveTheme.colorScheme.surfaceContainerLow,
                    systemNavigationBarDividerColor:
                        effectiveTheme.colorScheme.outlineVariant,
                    systemNavigationBarIconBrightness:
                        light ? Brightness.dark : Brightness.light,
                    systemNavigationBarContrastEnforced: false),
                child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      viewInsets: EdgeInsets.zero,
                      boldText: _preferences.boldText ||
                          MediaQuery.of(context).boldText,
                      disableAnimations: _preferences.reduceMotion ||
                          MediaQuery.of(context).disableAnimations,
                      textScaler: TextScaler.linear(
                        (MediaQuery.textScalerOf(context).scale(1) * _textScale)
                            .clamp(0.8, 3.0),
                      ),
                    ),
                    child: Padding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.viewInsetsOf(context).bottom),
                        child: PreferencesScope(
                            preferences: _preferencesLoaded
                                ? _preferences
                                : const AppPreferences(showMascot: false),
                            child: VoiceScope(
                                controller: _voice,
                                child: landscape
                                    ? Stack(children: [
                                        Positioned.fill(child: child!),
                                        if (_preferences.showVoiceDock)
                                          Positioned(
                                              top: MediaQuery.paddingOf(context)
                                                      .top +
                                                  62,
                                              right: 12,
                                              child: dock),
                                      ])
                                    : Column(children: [
                                        Expanded(child: child!),
                                        if (_preferences.showVoiceDock) dock,
                                      ]))))));
          }),
      home: Builder(builder: (context) {
        if (_loadError.isNotEmpty) {
          return Scaffold(
              body: Center(
                  child: Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorNotice(message: _loadError),
          )));
        }
        if (_storage == null) {
          return const SplashPage();
        }
        if (!_welcomeDone) {
          return WelcomePage(
            onStart: () =>
                unawaited(_finishWelcome().catchError((Object error) {
              if (context.mounted) {
                _showMessage(context, userError(error));
              }
            })),
            onSettings: () => _openSettings(context),
          );
        }
        return HomePage(
          records: _records,
          libraryController: _library,
          serverConfigured: _server.isNotEmpty,
          onOpen: (record) => _open(context, record),
          onCapture: () => _openCapture(context),
          onSettings: () => _openSettings(context),
          onHelp: _showVoiceHelp,
          onDelete: _deleteRecord,
          onRename: _renameRecord,
          onSavedNotes: () => _openSavedNotes(context),
          onBackup: () => _backupLibrary(context),
          onRestore: () => _restoreLibrary(context),
        );
      }),
    );
  }
}

class LecturePage extends StatefulWidget {
  const LecturePage(
      {super.key,
      required this.record,
      required this.storage,
      required this.onChanged,
      required this.currentServer,
      required this.onRetryFailed,
      required this.pages,
      required this.onOpenPage,
      required this.onOpenPageAtChunk,
      required this.onOpenPageAtTime,
      required this.onEditPage,
      required this.onAddPage,
      required this.onMovePage,
      required this.onRemovePage,
      this.autoPlay = false,
      this.editOnOpen = false,
      this.initialChunkId,
      this.initialPosition});
  final LectureRecord record;
  final LectureStorage storage;
  final Future<void> Function() onChanged;
  final String Function() currentServer;
  final void Function(BuildContext) onRetryFailed;
  final String? initialChunkId;
  final Duration? initialPosition;
  final bool autoPlay;
  final bool editOnOpen;
  final List<LectureRecord> Function() pages;
  final void Function(BuildContext, LectureRecord, bool) onOpenPage;
  final void Function(BuildContext, LectureRecord, String) onOpenPageAtChunk;
  final void Function(BuildContext, LectureRecord, Duration, bool) onOpenPageAtTime;
  final void Function(BuildContext, LectureRecord) onEditPage;
  final Future<void> Function(BuildContext) onAddPage;
  final Future<void> Function(LectureRecord, int) onMovePage;
  final Future<void> Function(BuildContext, LectureRecord) onRemovePage;

  @override
  State<LecturePage> createState() => _LecturePageState();
}

class _LecturePageState extends State<LecturePage> with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  VoiceNavigation? _voiceController;
  final _scroll = ScrollController();
  RecognitionApi? _api;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  bool _audioReady = false;
  bool _uploaded = false;
  bool _closed = false;
  bool _advancingPage = false;
  bool _editShown = false;
  LectoriaPose? _actionPose;
  Timer? _actionTimer;
  Timer? _noticeTimer;
  Timer? _retryTimer;
  int _retryDelaySeconds = 10;
  double _speed = 1.0;
  String _message = '';
  String _error = '';
  int _lastPlayedChunk = -1;
  bool _hapticEnabled = true, _earconsEnabled = true;
  int _lastPositionSaved = 0;

  LectureRecord get record => widget.record;
  LectureManifest? get manifest => record.manifest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastPositionSaved = record.lastPositionMs;
    _positionSubscription = _player.positionStream.listen((position) {
      final index = manifest?.chunkAt(position) ?? -1;
      if (index != _lastPlayedChunk && index >= 0 && _playing) {
        final chunk = manifest?.chunks[index];
        if (chunk?.isFormula == true) {
          if (_hapticEnabled) {
            unawaited(AppHaptics.vibrate(kind: 'formula'));
          }
          if (_earconsEnabled) unawaited(AppHaptics.tone('formula'));
        }
      }
      _lastPlayedChunk = index;
      if (mounted) setState(() => _position = position);
      if (_playing &&
          _player.processingState != ProcessingState.completed &&
          (position.inMilliseconds - _lastPositionSaved).abs() >= 10000) {
        unawaited(_persistPosition());
      }
    });
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed && _audioReady) {
        unawaited(_persistPosition(reset: true));
        final pages = widget.pages();
        final index = pages.indexOf(record);
        if (!_advancingPage && index >= 0 && index + 1 < pages.length) {
          _advancingPage = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_closed) {
              widget.onOpenPage(context, pages[index + 1], true);
            }
          });
        }
      } else if (!state.playing && _audioReady) {
        unawaited(_persistPosition());
      }
    });
    unawaited(_resume());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = PreferencesScope.of(context);
    _hapticEnabled = preferences.haptics;
    _earconsEnabled = preferences.earcons;
    final voice = VoiceScope.maybeOf(context);
    if (!identical(voice, _voiceController)) {
      _voiceController?.removeListener(_syncVoiceVolume);
      _voiceController = voice;
      voice?.addListener(_syncVoiceVolume);
    }
  }

  void _syncVoiceVolume() {
    unawaited(_applyVoiceVolume());
  }

  Future<void> _applyVoiceVolume() async {
    try {
      await _player.setVolume(_voiceController?.listening == true ||
              _voiceController?.busy == true ||
              _voiceController?.speaking == true
          ? .22
          : 1);
    } catch (_) {
      // The page can close while the voice service is updating.
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_persistPosition());
    _voiceController?.removeListener(_syncVoiceVolume);
    _actionTimer?.cancel();
    _noticeTimer?.cancel();
    _retryTimer?.cancel();
    _api?.close();
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    unawaited(_player.dispose());
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_persistPosition());
    } else if (state == AppLifecycleState.resumed && _error.isNotEmpty) {
      unawaited(_resume());
    }
  }

  Future<void> _persistPosition({bool reset = false}) async {
    if (!_audioReady) return;
    final position =
        reset || _player.processingState == ProcessingState.completed
            ? 0
            : _position.inMilliseconds.clamp(0, 86400000);
    if (position == _lastPositionSaved) return;
    record.lastPositionMs = position;
    _lastPositionSaved = position;
    try {
      await widget.onChanged();
    } catch (_) {
      // The next playback event will retry saving this position.
      _lastPositionSaved = -1;
    }
  }

  void _notice(String value) {
    _noticeTimer?.cancel();
    if (mounted) setState(() => _message = value);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _message == value) setState(() => _message = '');
    });
  }

  void _showAction(LectoriaPose pose) {
    _actionTimer?.cancel();
    if (mounted) setState(() => _actionPose = pose);
    _actionTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _actionPose = null);
    });
  }

  Future<void> _useConfiguredServer() async {
    final address = widget.currentServer().trim();
    if (address.isEmpty) {
      throw const ApiException(
          'Укажите адрес сервера в настройках и повторите отправку снимка');
    }
    if (record.serverBase != address || _api == null) {
      _api?.close();
      _api = RecognitionApi(address);
      record.serverBase = address;
      await widget.onChanged();
    }
  }

  Future<void> _resume() async {
    if (_loading) return;
    _retryTimer?.cancel();
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
      await _useConfiguredServer();
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
            if (_earconsEnabled) unawaited(AppHaptics.tone('waiting'));
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
      _retryDelaySeconds = 10;
      _showAction(LectoriaPose.success);
      if (mounted) {
        final voice = VoiceScope.maybeOf(context);
        if (voice != null) unawaited(voice.announceAction('Лекция готова'));
      }
    } catch (error) {
      final offline = error is SocketException ||
          error is TimeoutException ||
          error is http.ClientException ||
          (error is ApiException && error.statusCode == 503);
      if (mounted) {
        setState(() => _error = offline
            ? '${userError(error)} Снимок сохранён на телефоне; попробуем снова автоматически.'
            : userError(error));
        if (offline) {
          _retryTimer = Timer(Duration(seconds: _retryDelaySeconds), () {
            if (mounted && !_closed) unawaited(_resume());
          });
          _retryDelaySeconds = (_retryDelaySeconds * 2).clamp(10, 60);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (widget.editOnOpen && _audioReady && !_editShown) {
          _editShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_openTranscriptEditor());
          });
        }
      }
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
        // Recheck the UUID: the server may have accepted the image before the
        // connection dropped. A later manual retry uses the same saved photo.
        if (attempt == 3) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
        try {
          return await _api!.status(record.taskId);
        } on ApiException catch (error) {
          if (error.statusCode != 404) rethrow;
        } on SocketException {
          // The server is still offline; continue with the saved image.
        }
      }
    }
    throw const ApiException('Отправка прервана');
  }

  Future<void> _loadAudio() async {
    await _setAudioSource(record.audioPath);
    if (!mounted) return;
    final preferences = PreferencesScope.of(context);
    _speed = preferences.playbackSpeed;
    await _player.setSpeed(_speed);
    if (widget.initialPosition != null) {
      final length = Duration(
          milliseconds: ((manifest?.totalDuration ?? 0) * 1000).round());
      final time = Duration(milliseconds:
          widget.initialPosition!.inMilliseconds.clamp(0, length.inMilliseconds));
      await _player.seek(time);
      _position = time;
    } else if (widget.initialChunkId != null) {
      final chunks = manifest?.chunks ?? const <LectureChunk>[];
      for (final chunk in chunks) {
        if (chunk.id == widget.initialChunkId) {
          final time = Duration(milliseconds: (chunk.startTime * 1000).round());
          await _player.seek(time);
          _position = time;
          break;
        }
      }
    } else if (record.lastPositionMs > 0) {
      final durationMs = ((manifest?.totalDuration ?? 0) * 1000).round();
      if (durationMs == 0 || record.lastPositionMs < durationMs - 3000) {
        final time = Duration(milliseconds: record.lastPositionMs);
        await _player.seek(time);
        _position = time;
      }
    }
    if (!widget.editOnOpen && (preferences.autoPlay || widget.autoPlay)) {
      unawaited(_startPlayback());
    }
    if (mounted) {
      setState(() {
        _audioReady = true;
        _message = 'Лекция готова';
      });
    }
  }

  Future<void> _setAudioSource(String path) async {
    await _player.setAudioSource(AudioSource.file(
      path,
      tag: MediaItem(
        id: record.taskId,
        title: record.title,
        album: 'Лектория.Ai',
        duration: Duration(
            milliseconds: ((manifest?.totalDuration ?? 0) * 1000).round()),
      ),
    ));
  }

  void _playOrPause() {
    if (!_audioReady) return;
    if (PreferencesScope.of(context).haptics) unawaited(AppHaptics.vibrate());
    _showAction(_playing ? LectoriaPose.pause : LectoriaPose.play);
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
      if (mounted) setState(() => _error = userError(error));
    }
  }

  Future<void> _seekTo(int index) async {
    final chunks = manifest?.chunks ?? [];
    if (!_audioReady) return;
    if (index < 0 || index >= chunks.length) {
      if (_hapticEnabled) unawaited(AppHaptics.vibrate(kind: 'boundary'));
      return;
    }
    final current = manifest?.chunkAt(_position) ?? -1;
    if (index != current) {
      _showAction(index > current ? LectoriaPose.next : LectoriaPose.previous);
    }
    final time =
        Duration(milliseconds: (chunks[index].startTime * 1000).round());
    try {
      await _player.seek(time);
      if (!mounted) return;
      if (PreferencesScope.of(context).haptics) {
        await AppHaptics.vibrate();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = userError(error));
      }
    }
  }

  Future<void> _seekLecture(Duration position) async {
    final target = LectureTimeline(widget.pages()).locate(position);
    if (target == null) return;
    if (target.page == record) {
      await _player.seek(target.local);
    } else if (mounted) {
      widget.onOpenPageAtTime(context, target.page, target.local, _playing);
    }
  }

  Future<void> _seekAdjacent(bool forward, {bool play = false}) async {
    final chunks = manifest?.chunks ?? const <LectureChunk>[];
    final current = manifest?.chunkAt(_position) ?? -1;
    final target = current + (forward ? 1 : -1);
    if (target >= 0 && target < chunks.length) {
      await _seekTo(target);
      if (play && !_playing) _playOrPause();
      return;
    }
    final pages = widget.pages();
    final pageIndex = pages.indexOf(record) + (forward ? 1 : -1);
    if (pageIndex < 0 || pageIndex >= pages.length) {
      if (_hapticEnabled) unawaited(AppHaptics.vibrate(kind: 'boundary'));
      if (play) {
        throw VoiceActionFeedback(
            forward ? 'Это последний фрагмент' : 'Это первый фрагмент');
      }
      return;
    }
    final next = pages[pageIndex];
    final nextChunks = next.manifest?.chunks ?? const <LectureChunk>[];
    if (nextChunks.isEmpty) {
      widget.onOpenPage(context, next, play || _playing);
    } else {
      final index = forward ? 0 : nextChunks.length - 1;
      widget.onOpenPageAtTime(context, next,
          Duration(milliseconds: (nextChunks[index].startTime * 1000).round()),
          play || _playing);
    }
  }

  Future<void> _changeSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
      if (!mounted) return;
      if (mounted) setState(() => _speed = speed);
      if (PreferencesScope.of(context).haptics) {
        await AppHaptics.vibrate();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = userError(error));
      }
    }
  }

  Future<void> _toggleBookmark(int current) async {
    if (current < 0) return;
    record.bookmarkIndexes; // Migrate a legacy single bookmark before rollback.
    final previous = List<String>.from(record.bookmarkedChunkIds);
    record.toggleBookmark(current);
    try {
      await widget.onChanged();
      if (!mounted) return;
      if (mounted) setState(() {});
      _showAction(LectoriaPose.bookmark);
      if (PreferencesScope.of(context).haptics) {
        await AppHaptics.vibrate();
      }
    } catch (error) {
      record.bookmarkedChunkIds
        ..clear()
        ..addAll(previous);
      if (mounted) {
        setState(() => _error = userError(error));
      }
    }
  }

  void _openBookmarks() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'bookmarks'),
      builder: (pageContext) => BookmarksPage(
        record: record,
        onSelect: (index) {
          Navigator.of(pageContext).pop();
          unawaited(_seekTo(index));
        },
        onRemove: _toggleBookmark,
      ),
    ));
  }

  Future<void> _openTranscriptEditor() async {
    final current = manifest;
    if (_loading || current == null || current.chunks.isEmpty) return;
    if (current.chunks.any((chunk) => chunk.id.isEmpty)) {
      setState(
          () => _error = 'В ответе сервера нет идентификаторов фрагментов. '
              'Обновите сервер и обработайте снимок повторно.');
      return;
    }
    await _player.pause();
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => TranscriptEditor(
        manifest: current,
        imagePath: record.imagePath,
        onSave: _saveCorrections,
        reviewedChunkIds: record.reviewedChunkIds,
        onConfirm: (id) async {
          if (record.reviewedChunkIds.contains(id)) return;
          record.reviewedChunkIds.add(id);
          try {
            await widget.onChanged();
          } catch (_) {
            record.reviewedChunkIds.remove(id);
            rethrow;
          }
        },
      ),
    ));
  }

  Future<void> _saveCorrections(List<ChunkCorrection> corrections) async {
    if (_loading) {
      throw const ApiException('Дождитесь завершения текущей операции');
    }
    final previousManifest = record.manifestJson;
    final previousAudioPath = record.audioPath;
    record.bookmarkIndexes;
    final previousBookmarks = List<String>.from(record.bookmarkedChunkIds);
    setState(() {
      _loading = true;
      _error = '';
      _message = 'Создаём аудио по исправленному тексту';
    });
    try {
      await _useConfiguredServer();
      final updated = await _api!.renderCorrection(record.taskId, corrections);
      final audioUrl = LectureManifest.fromJson(updated).audioUrl;
      if (audioUrl.isEmpty) {
        throw const FormatException('Сервер не вернул новую аудиозапись');
      }
      final file = widget.storage.correctedAudioFile(record.taskId, audioUrl);
      if (!await file.exists()) await _api!.downloadAudio(audioUrl, file);
      if (_closed) return;
      await _setAudioSource(file.path);
      await _player.setSpeed(_speed);
      record.manifestJson = updated;
      record.audioPath = file.path;
      record.lastPositionMs = 0;
      _lastPositionSaved = 0;
      record.retainExistingBookmarks();
      await widget.onChanged();
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _audioReady = true;
          _message = 'Исправленная лекция готова';
        });
        _showAction(LectoriaPose.success);
      }
    } catch (_) {
      record.manifestJson = previousManifest;
      record.audioPath = previousAudioPath;
      record.bookmarkedChunkIds
        ..clear()
        ..addAll(previousBookmarks);
      if (previousAudioPath.isNotEmpty &&
          await File(previousAudioPath).exists()) {
        try {
          await _setAudioSource(previousAudioPath);
          await _player.setSpeed(_speed);
        } catch (_) {
          // The original files remain available for the next page opening.
        }
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleCommand(VoiceCommand command) async {
    final current = manifest?.chunkAt(_position) ?? -1;
    switch (command) {
      case VoiceCommand.play:
        if (!_playing) _playOrPause();
        return;
      case VoiceCommand.pause:
        if (_playing) _playOrPause();
        return;
      case VoiceCommand.next:
        await _seekAdjacent(true, play: true);
        return;
      case VoiceCommand.previous:
        await _seekAdjacent(false, play: true);
        return;
      case VoiceCommand.repeatFormula:
        final index = manifest?.nearestFormulaAtOrBefore(current);
        if (index == null) {
          _notice('До этого места формул нет');
          throw const VoiceActionFeedback('До этого места формул нет');
        } else {
          await _seekTo(index);
          if (!_playing) _playOrPause();
          _showAction(LectoriaPose.repeat);
        }
        return;
      case VoiceCommand.unknown:
        _notice('Команда не распознана');
        return;
    }
  }

  Future<bool> _voiceCommand(AppVoiceIntent intent) async {
    if (intent.command == AppCommand.addPage) {
      unawaited(widget.onAddPage(context));
      return true;
    }
    if (intent.command == AppCommand.nextPage ||
        intent.command == AppCommand.previousPage) {
      final pages = widget.pages();
      final index = pages.indexOf(record);
      final target = index + (intent.command == AppCommand.nextPage ? 1 : -1);
      if (target < 0 || target >= pages.length) {
        throw VoiceActionFeedback(intent.command == AppCommand.nextPage
            ? 'Это последняя страница лекции'
            : 'Это первая страница лекции');
      }
      widget.onOpenPage(context, pages[target], false);
      return true;
    }
    if (intent.command == AppCommand.page ||
        intent.command == AppCommand.editPage) {
      final pages = widget.pages();
      final index = (intent.number ?? 0) - 1;
      if (index < 0 || index >= pages.length) {
        throw VoiceActionFeedback(
            'В этой лекции ${pages.length} страниц. Назовите номер от одного до ${pages.length}.');
      }
      final page = pages[index];
      if (intent.command == AppCommand.editPage) {
        if (_loading) {
          throw const VoiceActionFeedback(
              'Подождите завершения обработки, затем откройте редактор.');
        }
        if (page.manifest?.chunks.isNotEmpty != true) {
          throw const VoiceActionFeedback(
              'Эта страница ещё не обработана. Дождитесь расшифровки.');
        }
        if (page == record) {
          unawaited(_openTranscriptEditor());
        } else {
          widget.onEditPage(context, page);
        }
      } else if (page != record) {
        widget.onOpenPage(context, page, false);
      }
      return true;
    }
    if (!_audioReady) return false;
    final current = manifest?.chunkAt(_position) ?? -1;
    switch (intent.command) {
      case AppCommand.play:
        await _handleCommand(VoiceCommand.play);
        return true;
      case AppCommand.pause:
        await _handleCommand(VoiceCommand.pause);
        return true;
      case AppCommand.next:
        await _handleCommand(VoiceCommand.next);
        return true;
      case AppCommand.previous:
        await _handleCommand(VoiceCommand.previous);
        return true;
      case AppCommand.repeatFormula:
        await _handleCommand(VoiceCommand.repeatFormula);
        return true;
      case AppCommand.explainFormula:
        final index = manifest
            ?.nearestFormulaAtOrBefore(manifest?.chunkAt(_position) ?? -1);
        if (index == null) {
          _notice('Рядом нет формулы для разбора');
          throw const VoiceActionFeedback('Рядом нет формулы для разбора');
        } else {
          unawaited(_openFormulaBreakdown(index));
        }
        return true;
      case AppCommand.fragment:
        final index = (intent.number ?? 0) - 1;
        if (index < 0 || index >= (manifest?.chunks.length ?? 0)) {
          throw const VoiceActionFeedback('Фрагмента с таким номером нет');
        }
        await _seekTo(index);
        return true;
      case AppCommand.firstFragment:
        if (manifest?.chunks.isEmpty ?? true) return false;
        await _seekTo(0);
        return true;
      case AppCommand.lastFragment:
        if (manifest?.chunks.isEmpty ?? true) return false;
        await _seekTo(manifest!.chunks.length - 1);
        return true;
      case AppCommand.bookmark:
        if (current < 0) {
          throw const VoiceActionFeedback('В этой странице пока нет фрагментов');
        }
        await _toggleBookmark(current);
        return true;
      case AppCommand.bookmarks:
        _openBookmarks();
        return true;
      case AppCommand.exportText:
        await LectureExport.text(widget.pages());
        return true;
      case AppCommand.exportAudio:
        await LectureExport.audioWithTranscript(widget.pages());
        return true;
      case AppCommand.edit:
        if (_loading || manifest?.chunks.isNotEmpty != true) {
          throw const VoiceActionFeedback(
              'Редактор будет доступен после обработки страницы.');
        }
        unawaited(_openTranscriptEditor());
        return true;
      case AppCommand.searchLecture:
        final query = intent.value?.trim().toLowerCase().replaceAll('ё', 'е') ?? '';
        if (query.isEmpty) return true;
        LectureRecord? foundPage;
        int? foundIndex;
        for (final page in widget.pages()) {
          final chunks = page.manifest?.chunks ?? const <LectureChunk>[];
          for (var i = 0; i < chunks.length; i++) {
            if (chunks[i].text.toLowerCase().replaceAll('ё', 'е').contains(query)) {
              foundPage = page;
              foundIndex = i;
              break;
            }
          }
          if (foundPage != null) break;
        }
        if (foundPage == null || foundIndex == null) {
          _notice('В этой лекции фраза «$query» не найдена');
          throw VoiceActionFeedback('Фраза «$query» не найдена');
        }
        if (foundPage == record) {
          await _seekTo(foundIndex);
        } else {
          widget.onOpenPageAtChunk(context, foundPage,
              foundPage.manifest!.chunks[foundIndex].id);
        }
        _notice('Найден фрагмент ${foundIndex + 1}');
        return true;
      case AppCommand.faster:
        if (_speed >= 3) {
          throw const VoiceActionFeedback('Установлена максимальная скорость');
        }
        await _changeSpeed((_speed + .25).clamp(.25, 3));
        return true;
      case AppCommand.slower:
        if (_speed <= .25) {
          throw const VoiceActionFeedback('Установлена минимальная скорость');
        }
        await _changeSpeed((_speed - .25).clamp(.25, 3));
        return true;
      default:
        return false;
    }
  }

  Future<void> _export(Future<void> Function(List<LectureRecord>) action) async {
    try {
      await action(widget.pages());
    } catch (error) {
      if (mounted) setState(() => _error = userError(error));
    }
  }

  Future<void> _openFormulaBreakdown(int index) async {
    final chunks = manifest?.chunks ?? const <LectureChunk>[];
    if (index < 0 || index >= chunks.length || !chunks[index].isFormula) return;
    await _player.pause();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FormulaBreakdownPage(chunk: chunks[index]),
    ));
  }

  @override
  Widget build(BuildContext context) => VoicePage(
      scrollController: _scroll,
      onCommand: _voiceCommand,
      beforeListen: () async {
        await _player.setVolume(.22);
      },
      child: LectureView(
        scrollController: _scroll,
        record: record,
        position: _position,
        playing: _playing,
        loading: _loading,
        audioReady: _audioReady,
        uploaded: _uploaded,
        listening: VoiceScope.maybeOf(context)?.listening ?? false,
        serverVoiceFallback: VoiceScope.maybeOf(context)?.usesServer ?? false,
        message: _message,
        error: _error,
        speed: _speed,
        onPlayPause: _playOrPause,
        onSeek: (index) => unawaited(_seekTo(index)),
        onSeekTime: (time) => unawaited(_seekLecture(time)),
        onSeekAdjacent: (forward) => unawaited(_seekAdjacent(forward)),
        lecturePosition: LectureTimeline(widget.pages()).offsetOf(record) + _position,
        lectureDuration: LectureTimeline(widget.pages()).total,
        onListen: () =>
            unawaited(VoiceScope.maybeOf(context)?.toggle() ?? Future.value()),
        onServerVoice: () => unawaited(
            VoiceScope.maybeOf(context)?.toggle(forceServer: true) ??
                Future.value()),
        onVoiceHelp: () {
          final voice = VoiceScope.maybeOf(context);
          if (voice != null) {
            unawaited(voice
                .dispatch(const AppVoiceIntent(AppCommand.help))
                .then((_) {}));
          }
        },
        onRetry: () => unawaited(_resume()),
        onReprocess: () => widget.onRetryFailed(context),
        onSpeed: (speed) => unawaited(_changeSpeed(speed)),
        onBookmark: () =>
            unawaited(_toggleBookmark(manifest?.chunkAt(_position) ?? -1)),
        onOpenBookmarks: _openBookmarks,
        onEditTranscript: () => unawaited(_openTranscriptEditor()),
        onExportText: () => unawaited(_export(LectureExport.text)),
        onExportAudio: () =>
            unawaited(_export(LectureExport.audioWithTranscript)),
        onExplainFormula: (index) => unawaited(_openFormulaBreakdown(index)),
        pages: widget.pages(),
        onOpenPage: (page) => widget.onOpenPage(context, page, false),
        onEditPage: (page) {
          if (page == record) {
            unawaited(_openTranscriptEditor());
          } else {
            widget.onEditPage(context, page);
          }
        },
        onOpenPageAtChunk: (page, chunkId) =>
            widget.onOpenPageAtChunk(context, page, chunkId),
        onAddPage: () async {
          await _player.pause();
          if (context.mounted) await widget.onAddPage(context);
        },
        onMovePage: (page, offset) async {
          await widget.onMovePage(page, offset);
          if (mounted) setState(() {});
        },
        onRemovePage: (page) async {
          await widget.onRemovePage(context, page);
          if (mounted) setState(() {});
        },
        actionPose: _actionPose,
      ));
}
