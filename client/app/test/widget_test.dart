import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/app_theme.dart';
import 'package:lecture_reader/main.dart';

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

    expect(find.text('Адрес сервера'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'http://192.168.1.8:8000');
    tester.testTextInput.hide();
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
