import 'models.dart';

/// Coordinates page-local timestamps on one lecture timeline.
class LectureTimeline {
  LectureTimeline(Iterable<LectureRecord> records)
      : pages = List<LectureRecord>.of(records)
          ..sort((a, b) => a.pageOrder.compareTo(b.pageOrder));

  final List<LectureRecord> pages;

  Duration get total => Duration(
      milliseconds: pages.fold<int>(0, (sum, page) => sum + _durationMs(page)));

  Duration offsetOf(LectureRecord page) {
    var offset = 0;
    for (final item in pages) {
      if (identical(item, page)) break;
      offset += _durationMs(item);
    }
    return Duration(milliseconds: offset);
  }

  ({LectureRecord page, Duration local})? locate(Duration position) {
    if (pages.isEmpty) return null;
    final bounded = position.inMilliseconds.clamp(0, total.inMilliseconds);
    var elapsed = 0;
    for (var i = 0; i < pages.length; i++) {
      final length = _durationMs(pages[i]);
      if (bounded < elapsed + length || i == pages.length - 1) {
        return (
          page: pages[i],
          local: Duration(milliseconds: (bounded - elapsed).clamp(0, length)),
        );
      }
      elapsed += length;
    }
    return null;
  }

  static int _durationMs(LectureRecord page) =>
      ((page.manifest?.totalDuration ?? 0).clamp(0, 86400) * 1000).round();
}
