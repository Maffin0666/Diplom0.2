import 'dart:typed_data';

class TextFrameAssessment {
  const TextFrameAssessment(this.lines, this.meanBrightness,
      {this.edgeStrength = 0,
      this.directionHint,
      this.backgroundConsistent = true});
  final int lines;
  final double meanBrightness;
  final double edgeStrength;
  final String? directionHint;

  /// Large variations across the page usually mean objects or shadows rather
  /// than a single sheet. Keep manual capture available in either case.
  final bool backgroundConsistent;
  bool get textLikely => lines >= 2 && backgroundConsistent;
  String get hint => textLikely
      ? edgeStrength < 4
          ? 'Лист в кадре. Дождитесь фокусировки'
          : 'Лист в кадре. Держите телефон неподвижно'
      : meanBrightness < 45
          ? 'Добавьте света'
          : 'Наведите рамку на текст';
}

/// Geometry guidance, not OCR. Operates on a small upright grayscale sample.
/// Multiple short dark runs identify ink rows; solid borders/grid lines do not.
TextFrameAssessment assessTextFrame(Uint8List gray, int width, int height) {
  if (width < 20 || height < 20 || gray.length < width * height) {
    return const TextFrameAssessment(0, 0);
  }
  final left = (width * .08).round(), right = (width * .92).round();
  final top = (height * .12).round(), bottom = (height * .88).round();
  final rows = <int>[];
  final masks = <List<bool>>[];
  final columnInk = List<int>.filled(right - left, 0);
  final columnBrightness = List<double>.filled(right - left, 0);
  double total = 0;
  double rowSquares = 0;
  double edges = 0;
  var edgeSamples = 0;
  for (var y = top; y < bottom; y++) {
    double sum = 0;
    for (var x = left; x < right; x++) {
      final value = gray[y * width + x];
      sum += value;
      columnBrightness[x - left] += value;
      if (x > left && y > top) {
        final p = gray[y * width + x];
        edges += (p - gray[y * width + x - 1]).abs() +
            (p - gray[(y - 1) * width + x]).abs();
        edgeSamples += 2;
      }
    }
    final mean = sum / (right - left);
    total += mean;
    rowSquares += mean * mean;
    final lightInk = mean < 90;
    final threshold =
        lightInk ? (mean + 45).clamp(80, 230) : (mean - 35).clamp(25, 175);
    final mask = <bool>[];
    for (var x = left; x < right; x++) {
      final ink = lightInk
          ? gray[y * width + x] > threshold
          : gray[y * width + x] < threshold;
      mask.add(ink);
      if (ink) columnInk[x - left]++;
    }
    masks.add(mask);
  }
  for (var y = 0; y < masks.length; y++) {
    var dark = 0, runs = 0;
    bool inInk = false;
    for (var x = 0; x < right - left; x++) {
      // Long vertical strokes belong to ruled paper or page borders.
      final ink = masks[y][x] && columnInk[x] < masks.length * .6;
      if (ink) dark++;
      if (ink && !inInk) runs++;
      inInk = ink;
    }
    final fraction = dark / (right - left);
    if (runs >= 4 && fraction >= .035 && fraction <= .55) rows.add(y + top);
  }
  var lines = 0;
  if (rows.isNotEmpty) {
    var start = rows.first, end = start;
    for (final y in rows.skip(1)) {
      if (y - end > 1) {
        if (end - start < height * .16) lines++;
        start = y;
      }
      end = y;
    }
    if (end - start < height * .16) lines++;
  }
  // Compare sparse dark pixels near the vertical borders. This is guidance,
  // not proof that the entire physical page is visible.
  var topInk = 0, bottomInk = 0;
  final band = (height * .13).round();
  for (var y = 0; y < band; y++) {
    for (var x = left; x < right; x += 3) {
      if (gray[y * width + x] < 110) topInk++;
      if (gray[(height - 1 - y) * width + x] < 110) bottomInk++;
    }
  }
  final direction = topInk > bottomInk * 2 && topInk > 20
      ? 'Поднимите телефон выше'
      : bottomInk > topInk * 2 && bottomInk > 20
          ? 'Опустите телефон ниже'
          : null;
  final rowCount = bottom - top;
  final meanBrightness = total / rowCount;
  final rowVariance = rowSquares / rowCount - meanBrightness * meanBrightness;
  var columnSquares = 0.0;
  for (final sum in columnBrightness) {
    final mean = sum / rowCount;
    columnSquares += mean * mean;
  }
  final columnVariance =
      columnSquares / columnBrightness.length - meanBrightness * meanBrightness;
  // These deliberately conservative limits prevent automatic shots of
  // strongly textured objects. A real page can still be photographed by hand.
  final consistent = rowVariance < 38 * 38 && columnVariance < 24 * 24;
  return TextFrameAssessment(lines, meanBrightness,
      edgeStrength: edgeSamples == 0 ? 0 : edges / edgeSamples,
      directionHint: consistent && lines == 1 ? direction : null,
      backgroundConsistent: consistent);
}
