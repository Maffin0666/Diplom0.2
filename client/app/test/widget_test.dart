import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/app_theme.dart';
import 'package:lecture_reader/app_preferences.dart';
import 'package:lecture_reader/main.dart';
import 'package:lecture_reader/voice_commands.dart';
import 'package:lecture_reader/voice_navigation.dart';

void main() {
  testWidgets('настройки сохраняют адрес сервера и тему', (tester) async {
    String? savedServer;
    ThemeMode? savedTheme;
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        server: 'http://192.168.1.5:8000',
        theme: ThemeMode.system,
        scale: 1,
        onSave: (server, theme, scale) async {
          savedServer = server;
          savedTheme = theme;
        },
      ),
    ));

    await tester.scrollUntilVisible(find.text('Подключение'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Подключение'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подключение'));
    await tester.pumpAndSettle();
    expect(find.text('Адрес сервера'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '192.168.1.8');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Оформление'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Тёмная'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Тёмная'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Сохранить настройки'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Сохранить настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить настройки'));
    await tester.pump();

    expect(savedServer, 'http://192.168.1.8:8000');
    expect(savedTheme, ThemeMode.dark);
  });

  test('светлая и тёмная темы имеют соответствующую яркость', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });

  testWidgets('расширенный адрес сохраняет нестандартный порт', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        server: 'https://lecture.example:9443',
        theme: ThemeMode.system,
        scale: 1,
        onSave: (server, _, __) async => saved = server,
      ),
    ));
    await tester.scrollUntilVisible(find.text('Подключение'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Подключение'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подключение'));
    await tester.pumpAndSettle();
    expect(find.text('Полный адрес сервера'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'https://lecture.example:9443');
    await tester.tap(find.text('Сохранить настройки'));
    await tester.pump();
    expect(saved, 'https://lecture.example:9443');
  });

  testWidgets('голос меняет параметры настроек до сохранения', (tester) async {
    final voice = VoiceNavigation();
    addTearDown(voice.dispose);
    AppPreferences? saved;
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => VoiceScope(controller: voice, child: child!),
      home: SettingsPage(
        server: '',
        theme: ThemeMode.system,
        scale: 1,
        onSave: (_, __, ___) async {},
        onSaveAll: (_, __, ___, preferences) async => saved = preferences,
      ),
    ));
    expect(await voice.dispatch(parseAppVoiceCommand('выключи панель голоса')),
        isTrue);
    expect(
        await voice.dispatch(parseAppVoiceCommand('распознавай на ноутбуке')),
        isTrue);
    expect(await voice.dispatch(parseAppVoiceCommand('сохранить')), isTrue);
    await tester.pump();
    expect(saved?.showVoiceDock, isFalse);
    expect(saved?.voiceMode, 'server');
  });

  testWidgets('масштаб текста можно уменьшить ниже 100%', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SettingsPage(
      server: 'http://192.168.1.5:8000',
      theme: ThemeMode.system,
      scale: 1,
      onSave: (_, __, ___) async {},
    )));
    await tester.tap(find.text('Оформление'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Уменьшить текст'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byTooltip('Уменьшить текст'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Уменьшить текст'));
    await tester.pump();
    expect(find.text('Размер текста: 90%'), findsOneWidget);
    await tester.tap(find.byTooltip('Уменьшить текст'));
    await tester.pump();
    expect(find.text('Размер текста: 80%'), findsOneWidget);
  });

  testWidgets('настройки доступны при крупном тексте на узком экране',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.2)),
        child: SettingsPage(
          server: 'http://192.168.1.5:8000',
          theme: ThemeMode.dark,
          scale: 1.6,
          onSave: (server, theme, scale) async {},
        ),
      ),
    ));
    await tester.scrollUntilVisible(find.text('Сохранить настройки'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Сохранить настройки'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
