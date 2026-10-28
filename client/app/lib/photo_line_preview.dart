import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'models.dart';

/// Exact server box on the decoded photo. The crop below adds padding, while
/// the overview deliberately shows the reported bounds without expanding them.
Rect? photoRegionRect(
    LectureChunk chunk, int originalWidth, int originalHeight, ui.Image image) {
  final box = chunk.bbox;
  if (box == null || originalWidth <= 0 || originalHeight <= 0) return null;
  final left = box[0].clamp(0, originalWidth).toDouble();
  final top = box[1].clamp(0, originalHeight).toDouble();
  final right = box[2].clamp(0, originalWidth).toDouble();
  final bottom = box[3].clamp(0, originalHeight).toDouble();
  if (right <= left || bottom <= top) return null;
  return Rect.fromLTRB(
    left * image.width / originalWidth,
    top * image.height / originalHeight,
    right * image.width / originalWidth,
    bottom * image.height / originalHeight,
  );
}

/// Map a tap on a fitted page to the smallest OCR region under the finger.
/// A small tolerance makes thin handwritten lines easier to select.
int? photoChunkAt(Offset point, Size size, Size imageSize,
    List<LectureChunk> chunks, int originalWidth, int originalHeight) {
  if (size.isEmpty || imageSize.isEmpty || originalWidth <= 0 || originalHeight <= 0) {
    return null;
  }
  final scale = math.min(size.width / imageSize.width, size.height / imageSize.height);
  final left = (size.width - imageSize.width * scale) / 2;
  final top = (size.height - imageSize.height * scale) / 2;
  final x = (point.dx - left) / (imageSize.width * scale) * originalWidth;
  final y = (point.dy - top) / (imageSize.height * scale) * originalHeight;
  if (x < 0 || x > originalWidth || y < 0 || y > originalHeight) return null;
  int? selected;
  double? smallestArea;
  for (var i = 0; i < chunks.length; i++) {
    final box = chunks[i].bbox;
    if (box == null) continue;
    final tolerance = 12 / scale * originalWidth / imageSize.width;
    if (x < box[0] - tolerance || x > box[2] + tolerance ||
        y < box[1] - tolerance || y > box[3] + tolerance) {
      continue;
    }
    final area = (box[2] - box[0]) * (box[3] - box[1]).toDouble();
    if (smallestArea == null || area < smallestArea) {
      smallestArea = area;
      selected = i;
    }
  }
  return selected;
}

/// A page overview makes a cropped OCR line understandable in its context.
class PhotoRegionOverview extends StatelessWidget {
  const PhotoRegionOverview({
    super.key,
    required this.imageFuture,
    required this.chunk,
    required this.originalWidth,
    required this.originalHeight,
    this.maxHeight = 320,
    this.chunks = const [],
    this.onSelect,
  });

  final Future<ui.Image?> imageFuture;
  final LectureChunk chunk;
  final int originalWidth, originalHeight;
  final double maxHeight;
  final List<LectureChunk> chunks;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image?>(
        future: imageFuture,
        builder: (context, snapshot) {
          final image = snapshot.data;
          if (image == null) {
            return Text(snapshot.connectionState == ConnectionState.done
                ? 'Исходный снимок недоступен.'
                : 'Открываем снимок…');
          }
          final region =
              photoRegionRect(chunk, originalWidth, originalHeight, image);
          if (region == null) {
            return const Text('Для этого фрагмента нет координат на снимке.');
          }
          return LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height =
                math.min(maxHeight, width * image.height / image.width);
            return Semantics(
              image: true,
              label:
                  'Исходный снимок. Выделена область фрагмента ${chunk.index + 1}.',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: onSelect == null ? null : (details) {
                    final index = photoChunkAt(
                      details.localPosition, Size(width, height),
                      Size(image.width.toDouble(), image.height.toDouble()),
                      chunks, originalWidth, originalHeight);
                    if (index != null) onSelect!(index);
                  },
                  child: CustomPaint(
                    key: ValueKey('photo_region_${chunk.id}'),
                    size: Size(width, height),
                    painter: _RegionPainter(
                        image, region, Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
            );
          });
        },
      );
}

class _RegionPainter extends CustomPainter {
  const _RegionPainter(this.image, this.region, this.accent);
  final ui.Image image;
  final Rect region;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final scale =
        math.min(size.width / image.width, size.height / image.height);
    final page = Rect.fromLTWH(
        (size.width - image.width * scale) / 2,
        (size.height - image.height * scale) / 2,
        image.width * scale,
        image.height * scale);
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        page,
        Paint());
    final box = Rect.fromLTRB(
      page.left + region.left * scale,
      page.top + region.top * scale,
      page.left + region.right * scale,
      page.top + region.bottom * scale,
    );
    canvas.drawRect(box, Paint()..color = accent.withValues(alpha: .22));
    canvas.drawRect(
        box,
        Paint()
          ..color = accent
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_RegionPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.region != region ||
      oldDelegate.accent != accent;
}

/// The server reports boxes in the original uploaded image. The editor uses a
/// smaller decoded image; convert the coordinates before drawing the crop.
Rect? lineSourceRect(
    LectureChunk chunk, int originalWidth, int originalHeight, ui.Image image) {
  final box = chunk.bbox;
  if (box == null || originalWidth <= 0 || originalHeight <= 0) return null;
  final left = box[0].clamp(0, originalWidth).toDouble();
  final top = box[1].clamp(0, originalHeight).toDouble();
  final right = box[2].clamp(0, originalWidth).toDouble();
  final bottom = box[3].clamp(0, originalHeight).toDouble();
  if (right <= left || bottom <= top) return null;
  final padX = math.max(8.0, (right - left) * .035);
  final padY = math.max(8.0, (bottom - top) * .28);
  final sx = image.width / originalWidth;
  final sy = image.height / originalHeight;
  return Rect.fromLTRB(
    math.max(0, left - padX) * sx,
    math.max(0, top - padY) * sy,
    math.min(originalWidth.toDouble(), right + padX) * sx,
    math.min(originalHeight.toDouble(), bottom + padY) * sy,
  );
}

class PhotoLinePreview extends StatelessWidget {
  const PhotoLinePreview({
    super.key,
    required this.imageFuture,
    required this.chunk,
    required this.originalWidth,
    required this.originalHeight,
  });

  final Future<ui.Image?> imageFuture;
  final LectureChunk chunk;
  final int originalWidth, originalHeight;

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image?>(
        future: imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Открываем участок снимка…'),
            );
          }
          final image = snapshot.data;
          if (image == null) {
            return const Text('Снимок недоступен. Проверьте текст вручную.');
          }
          final source =
              lineSourceRect(chunk, originalWidth, originalHeight, image);
          if (source == null) {
            return const Text(
                'Для этой строки нет области снимка. Откройте фото целиком выше.');
          }
          const cropHeight = 148.0;
          return LayoutBuilder(builder: (context, bounds) {
            final naturalWidth = cropHeight * source.width / source.height;
            final contentWidth = math.max(bounds.maxWidth, naturalWidth);
            return Semantics(
              image: true,
              label: 'Увеличенный участок снимка для этого фрагмента. '
                  'Проведите в сторону, чтобы просмотреть всю строку.',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: CustomPaint(
                      key: ValueKey('photo_line_${chunk.id}'),
                      size: Size(contentWidth, cropHeight),
                      painter: _LinePainter(image, source),
                    ),
                  ),
                ),
              ),
            );
          });
        },
      );
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.image, this.source);
  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.height * source.width / source.height;
    final left = (size.width - width) / 2;
    canvas.drawImageRect(
        image, source, Rect.fromLTWH(left, 0, width, size.height), Paint());
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.source != source;
}
