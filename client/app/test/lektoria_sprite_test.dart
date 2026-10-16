import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/lektoria_sprite.dart';

void main() {
  testWidgets('у каждой позы есть доступный PNG и подпись для TalkBack',
      (tester) async {
    for (final pose in LectoriaPose.values) {
      for (final crop in SpriteCrop.values) {
        final path = LectoriaAssets.pose(pose, crop);
        final bytes = await rootBundle.load(path);
        expect(bytes.lengthInBytes, greaterThan(0), reason: path);
        expect(LectoriaAssets.label(pose), isNotEmpty);
      }
    }
  });

  testWidgets('смена состояния выбирает нужный спрайт', (tester) async {
    Future<void> show(LectoriaPose pose) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: AnimatedLectoriaSprite(pose: pose, size: 96),
              ),
            ),
          ),
        );

    await show(LectoriaPose.idle);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is LectoriaSprite && widget.pose == LectoriaPose.idle),
        findsOneWidget);
    await show(LectoriaPose.listening);
    await tester.pump();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is LectoriaSprite && widget.pose == LectoriaPose.listening),
        findsOneWidget);
  });
}
