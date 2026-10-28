import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_reader/lecture_export.dart';
import 'package:lecture_reader/lecture_timeline.dart';
import 'package:lecture_reader/models.dart';
import 'package:lecture_reader/mp3_joiner.dart';

LectureRecord _page(String id, int order, double duration, String text) =>
    LectureRecord(
      taskId: id,
      serverBase: '',
      imagePath: '',
      createdAt: DateTime.utc(2026, 10, 21),
      seriesId: 'lecture-1',
      pageOrder: order,
      manifestJson: {
        'status': 'completed',
        'total_duration': duration,
        'chunks': [
          {
            'id': '$id-line',
            'index': 0,
            'text': text,
            'spoken_text': text,
            'start_time': 1.0,
            'end_time': 2.0
          },
        ],
      },
    );

void main() {
  test('global timeline crosses page boundaries', () {
    final first = _page('first', 0, 10, 'Начало');
    final second = _page('second', 1, 20, 'Конец');
    final timeline = LectureTimeline([second, first]);
    expect(timeline.total, const Duration(seconds: 30));
    expect(timeline.offsetOf(second), const Duration(seconds: 10));
    expect(timeline.locate(const Duration(seconds: 15))?.page, same(second));
    expect(timeline.locate(const Duration(seconds: 15))?.local,
        const Duration(seconds: 5));
    expect(timeline.locate(const Duration(seconds: 10))?.page, same(second));
  });

  test('text and LRC include both pages in reading order', () {
    final first = _page('first', 0, 10, 'Начало');
    final second = _page('second', 1, 20, 'Конец');
    final text = fullTranscriptForExport([second, first]);
    expect(text.indexOf('Начало'), lessThan(text.indexOf('Конец')));
    final lrc = fullTimedTranscriptForExport([second, first],
        [const Duration(seconds: 10), const Duration(seconds: 20)]);
    expect(lrc, contains('[00:01.00]Начало'));
    expect(lrc, contains('[00:11.00]Конец'));
  });

  test('real TTS MP3 pages join into one decodable frame stream', () async {
    final first = File('../../static/audio/lecture_2886e5e77b.mp3');
    final second = File('../../static/audio/lecture_233887278e.mp3');
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isTrue);
    final temp = await Directory.systemTemp.createTemp('lektoria-join-');
    try {
      final output = File('${temp.path}/full.mp3');
      final lengths = await Mp3Joiner.join([first, second], output);
      expect(lengths.length, 2);
      expect(lengths.first.inSeconds, greaterThan(20));
      expect(lengths.last.inSeconds, greaterThan(10));
      expect(await output.length(), greaterThan(await first.length()));
      final header = await output.openRead(0, 4).first;
      expect(header[0], 0xff);
      try {
        final decoded = await Process.run('ffmpeg', [
          '-v', 'error', '-i', output.path, '-f', 'null',
          Platform.isWindows ? 'NUL' : '/dev/null',
        ]);
        expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
        expect((decoded.stderr as String).trim(), isEmpty);
      } on ProcessException {
        // FFmpeg is optional on CI; frame and duration checks still run.
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
