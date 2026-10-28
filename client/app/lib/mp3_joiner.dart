import 'dart:io';
import 'dart:typed_data';

/// Raw MPEG Layer III frame concatenation. All TTS pages use the same encoder.
/// Strip per-file ID3/Xing metadata: otherwise players read the duration of
/// only the first page. No transcoding, network request or large audio buffer.
class Mp3Joiner {
  const Mp3Joiner._();

  static Future<List<Duration>> join(
      List<File> sources, File destination) async {
    if (sources.isEmpty) {
      throw const FormatException('Нет аудио для объединения');
    }
    final segments = <_Mp3Segment>[];
    for (final file in sources) {
      if (!await file.exists()) {
        throw const FileSystemException('Не найдена аудиозапись страницы');
      }
      segments.add(_Mp3Segment.parse(await file.readAsBytes()));
    }
    final format = segments.first;
    if (segments.any((part) =>
        part.version != format.version ||
        part.sampleRate != format.sampleRate ||
        part.channels != format.channels)) {
      throw const FormatException(
          'Страницы имеют разные аудиоформаты. Для объединения озвучьте их одной настройкой сервера.');
    }
    final partial = File('${destination.path}.partial');
    final output = partial.openWrite();
    try {
      for (var i = 0; i < sources.length; i++) {
        await output.addStream(
            sources[i].openRead(segments[i].audioStart, segments[i].audioEnd));
      }
      await output.flush();
      await output.close();
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
      return [for (final part in segments) part.duration];
    } catch (_) {
      await output.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }
}

class _Mp3Segment {
  const _Mp3Segment(this.audioStart, this.audioEnd, this.version,
      this.sampleRate, this.channels, this.samples);

  final int audioStart, audioEnd, version, sampleRate, channels, samples;
  Duration get duration =>
      Duration(microseconds: (samples * 1000000 / sampleRate).round());

  static _Mp3Segment parse(Uint8List bytes) {
    if (bytes.length < 64) {
      throw const FormatException('Повреждена аудиозапись страницы');
    }
    var offset = 0;
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      for (var i = 6; i < 10; i++) {
        if (bytes[i] > 0x7f) {
          throw const FormatException('Повреждены метаданные MP3');
        }
      }
      final tagSize =
          (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
      offset = 10 + tagSize + ((bytes[5] & 0x10) != 0 ? 10 : 0);
    }
    _Frame? first;
    final searchLimit = (offset + 8192).clamp(0, bytes.length - 4);
    while (offset <= searchLimit) {
      first = _Frame.at(bytes, offset);
      if (first != null && _Frame.at(bytes, offset + first.length) != null) {
        break;
      }
      offset++;
    }
    if (first == null || offset > searchLimit) {
      throw const FormatException('Не найдены звуковые кадры MP3');
    }
    final version = first.version;
    final sampleRate = first.sampleRate;
    final channels = first.channels;
    final firstAudio =
        _hasXing(bytes, offset, first) ? offset + first.length : offset;
    var samples = 0;
    var end = offset;
    while (end + 4 <= bytes.length) {
      final frame = _Frame.at(bytes, end);
      if (frame == null || end + frame.length > bytes.length) break;
      if (frame.version != version ||
          frame.sampleRate != sampleRate ||
          frame.channels != channels) {
        throw const FormatException('Аудиозапись содержит несовместимые кадры');
      }
      if (end >= firstAudio) samples += frame.samples;
      end += frame.length;
    }
    if (samples == 0 || end <= firstAudio) {
      throw const FormatException('Аудиозапись страницы пуста');
    }
    final tail = bytes.length - end;
    if (tail > 0 &&
        !(tail == 128 &&
            bytes[end] == 0x54 &&
            bytes[end + 1] == 0x41 &&
            bytes[end + 2] == 0x47) &&
        !(tail <= 4096 && bytes.skip(end).every((byte) => byte == 0))) {
      throw const FormatException('Повреждён конец аудиозаписи страницы');
    }
    return _Mp3Segment(firstAudio, end, version, sampleRate, channels, samples);
  }

  static bool _hasXing(Uint8List bytes, int offset, _Frame frame) {
    final sideInfo = frame.version == 3
        ? (frame.channels == 1 ? 17 : 32)
        : (frame.channels == 1 ? 9 : 17);
    final marker = offset + 4 + (frame.hasCrc ? 2 : 0) + sideInfo;
    if (marker + 4 > offset + frame.length) return false;
    final label = String.fromCharCodes(bytes.sublist(marker, marker + 4));
    return label == 'Xing' || label == 'Info';
  }
}

class _Frame {
  const _Frame(this.length, this.version, this.sampleRate, this.channels,
      this.samples, this.hasCrc);
  final int length, version, sampleRate, channels, samples;
  final bool hasCrc;

  static _Frame? at(Uint8List bytes, int offset) {
    if (offset < 0 ||
        offset + 4 > bytes.length ||
        bytes[offset] != 0xff ||
        (bytes[offset + 1] & 0xe0) != 0xe0) {
      return null;
    }
    final version = (bytes[offset + 1] >> 3) & 3;
    final layer = (bytes[offset + 1] >> 1) & 3;
    final bitrateIndex = (bytes[offset + 2] >> 4) & 15;
    final rateIndex = (bytes[offset + 2] >> 2) & 3;
    if (version == 1 ||
        layer != 1 ||
        bitrateIndex == 0 ||
        bitrateIndex == 15 ||
        rateIndex == 3) {
      return null;
    }
    const mpeg1Bitrates = [
      0,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320
    ];
    const mpeg2Bitrates = [
      0,
      8,
      16,
      24,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160
    ];
    const baseRates = [44100, 48000, 32000];
    final sampleRate = baseRates[rateIndex] ~/
        (version == 3
            ? 1
            : version == 2
                ? 2
                : 4);
    final bitrate = (version == 3
        ? mpeg1Bitrates[bitrateIndex]
        : mpeg2Bitrates[bitrateIndex]);
    final padding = (bytes[offset + 2] >> 1) & 1;
    final length =
        (version == 3 ? 144000 : 72000) * bitrate ~/ sampleRate + padding;
    if (length < 24) return null;
    return _Frame(
        length,
        version,
        sampleRate,
        (bytes[offset + 3] & 0xc0) == 0xc0 ? 1 : 2,
        version == 3 ? 1152 : 576,
        (bytes[offset + 1] & 1) == 0);
  }
}
