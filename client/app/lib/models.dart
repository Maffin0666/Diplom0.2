import 'dart:convert';

String _string(Object? value) => value is String ? value : '';
double _number(Object? value) => value is num ? value.toDouble() : 0;

class LectureChunk {
  const LectureChunk({
    required this.index,
    required this.text,
    required this.spokenText,
    required this.isFormula,
    required this.startTime,
    required this.endTime,
  });

  final int index;
  final String text;
  final String spokenText;
  final bool isFormula;
  final double startTime;
  final double endTime;

  factory LectureChunk.fromJson(Map<String, dynamic> json) => LectureChunk(
        index: (json['index'] as num?)?.toInt() ?? 0,
        text: _string(json['text']),
        spokenText: _string(json['spoken_text']),
        isFormula:
            json['is_formula'] == true || json['content_type'] == 'formula',
        startTime: _number(json['start_time']),
        endTime: _number(json['end_time']),
      );
}

class LectureManifest {
  LectureManifest.fromJson(Map<String, dynamic> json)
      : taskId = _string(json['task_id']),
        status = _string(json['status']),
        fullText = _string(json['full_text']),
        spokenText = _string(json['spoken_text']),
        audioUrl = _string(json['audio_url']),
        error = _string(json['error']),
        totalDuration = _number(json['total_duration']),
        chunks = ((json['chunks'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LectureChunk.fromJson)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));

  final String taskId;
  final String status;
  final String fullText;
  final String spokenText;
  final String audioUrl;
  final String error;
  final double totalDuration;
  final List<LectureChunk> chunks;

  /// During a pause between chunks the preceding chunk remains selected.
  int chunkAt(Duration position) {
    if (chunks.isEmpty) return -1;
    final seconds = position.inMilliseconds / 1000;
    for (var i = chunks.length - 1; i >= 0; i--) {
      if (seconds >= chunks[i].startTime) return i;
    }
    return 0;
  }

  int? nearestFormulaAtOrBefore(int index) {
    if (chunks.isEmpty) return null;
    for (var i = index.clamp(0, chunks.length - 1).toInt(); i >= 0; i--) {
      if (chunks[i].isFormula) return i;
    }
    return null;
  }
}

class LectureRecord {
  LectureRecord({
    required this.taskId,
    required this.serverBase,
    required this.imagePath,
    required this.createdAt,
    this.status = 'pending',
    this.audioPath = '',
    this.manifestJson,
    this.bookmarkIndex,
  });

  final String taskId;
  final String serverBase;
  final String imagePath;
  final DateTime createdAt;
  String status;
  String audioPath;
  Map<String, dynamic>? manifestJson;
  int? bookmarkIndex;

  LectureManifest? get manifest =>
      manifestJson == null ? null : LectureManifest.fromJson(manifestJson!);

  String get title {
    final text = manifest?.fullText.trim() ?? '';
    if (text.isEmpty) {
      return 'Конспект ${createdAt.day}.${createdAt.month}.${createdAt.year}';
    }
    final firstLine = text.split('\n').first.trim();
    return firstLine.length > 64 ? '${firstLine.substring(0, 64)}…' : firstLine;
  }

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'server_base': serverBase,
        'image_path': imagePath,
        'created_at': createdAt.toIso8601String(),
        'status': status,
        'audio_path': audioPath,
        'manifest': manifestJson,
        'bookmark_index': bookmarkIndex,
      };

  factory LectureRecord.fromJson(Map<String, dynamic> json) => LectureRecord(
        taskId: _string(json['task_id']),
        serverBase: _string(json['server_base']),
        imagePath: _string(json['image_path']),
        createdAt:
            DateTime.tryParse(_string(json['created_at'])) ?? DateTime.now(),
        status: _string(json['status']),
        audioPath: _string(json['audio_path']),
        manifestJson: json['manifest'] is Map<String, dynamic>
            ? json['manifest'] as Map<String, dynamic>
            : null,
        bookmarkIndex: (json['bookmark_index'] as num?)?.toInt(),
      );
}

Map<String, dynamic> decodeObject(String body) {
  final value = jsonDecode(body);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Некорректный ответ сервера');
  }
  return value;
}
