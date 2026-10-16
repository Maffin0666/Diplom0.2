import 'dart:convert';

String _string(Object? value) => value is String ? value : '';
double _number(Object? value) => value is num ? value.toDouble() : 0;

class LectureChunk {
  const LectureChunk({
    required this.id,
    required this.index,
    required this.text,
    required this.spokenText,
    required this.isFormula,
    required this.startTime,
    required this.endTime,
    this.confidence = 1,
    this.bbox,
  });

  final String id;
  final int index;
  final String text;
  final String spokenText;
  final bool isFormula;
  final double startTime;
  final double endTime;
  final double confidence;

  /// Coordinates in the uploaded photograph: left, top, right, bottom.
  final List<int>? bbox;

  bool get needsReview => confidence < .55;

  factory LectureChunk.fromJson(Map<String, dynamic> json) => LectureChunk(
        id: _string(json['id']),
        index: (json['index'] as num?)?.toInt() ?? 0,
        text: _string(json['text']),
        spokenText: _string(json['spoken_text']),
        isFormula:
            json['is_formula'] == true || json['content_type'] == 'formula',
        startTime: _number(json['start_time']),
        endTime: _number(json['end_time']),
        confidence: json['confidence'] is num
            ? (json['confidence'] as num).toDouble().clamp(0, 1)
            : 1,
        bbox: switch (json['bbox']) {
          final List values
              when values.length == 4 &&
                  values.every((value) => value is num) &&
                  (values[2] as num) > (values[0] as num) &&
                  (values[3] as num) > (values[1] as num) =>
            values.map((value) => (value as num).round()).toList(),
          _ => null,
        },
      );
}

class ChunkCorrection {
  const ChunkCorrection({
    required this.id,
    required this.text,
    required this.isFormula,
    this.spokenText,
    this.remove = false,
  });

  final String id;
  final String text;
  final bool isFormula;
  final String? spokenText;
  final bool remove;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'is_formula': isFormula,
        if (spokenText != null) 'spoken_text': spokenText,
        if (remove) 'remove': true,
      };
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
        imageWidth = (json['image_width'] as num?)?.toInt(),
        imageHeight = (json['image_height'] as num?)?.toInt(),
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
  final int? imageWidth, imageHeight;
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
    this.customTitle = '',
    this.lastPositionMs = 0,
    int? bookmarkIndex,
    List<String>? bookmarkedChunkIds,
  })  : _legacyBookmarkIndex = bookmarkIndex,
        bookmarkedChunkIds = List<String>.from(bookmarkedChunkIds ?? const []);

  final String taskId;
  final String serverBase;
  final String imagePath;
  final DateTime createdAt;
  String status;
  String audioPath;
  Map<String, dynamic>? manifestJson;
  String customTitle;
  int lastPositionMs;
  final List<String> bookmarkedChunkIds;
  int? _legacyBookmarkIndex;

  /// IDs survive changed timing and deleted preceding fragments.
  List<int> get bookmarkIndexes {
    final chunks = manifest?.chunks ?? const <LectureChunk>[];
    if (bookmarkedChunkIds.isEmpty && _legacyBookmarkIndex != null) {
      final old = _legacyBookmarkIndex!;
      if (old >= 0 && old < chunks.length) {
        bookmarkedChunkIds.add(chunks[old].id);
      }
      _legacyBookmarkIndex = null;
    }
    return [
      for (var i = 0; i < chunks.length; i++)
        if (bookmarkedChunkIds.contains(chunks[i].id)) i,
    ];
  }

  int? get bookmarkIndex =>
      bookmarkIndexes.isEmpty ? null : bookmarkIndexes.first;

  set bookmarkIndex(int? index) {
    bookmarkedChunkIds.clear();
    _legacyBookmarkIndex = index;
    bookmarkIndexes; // Convert old index as soon as a manifest is available.
  }

  bool hasBookmark(int index) => bookmarkIndexes.contains(index);

  void toggleBookmark(int index) {
    final chunks = manifest?.chunks ?? const <LectureChunk>[];
    if (index < 0 || index >= chunks.length) return;
    bookmarkIndexes; // Migrate an old single bookmark before editing the set.
    final id = chunks[index].id;
    if (bookmarkedChunkIds.contains(id)) {
      bookmarkedChunkIds.remove(id);
    } else {
      bookmarkedChunkIds.add(id);
    }
  }

  void retainExistingBookmarks() {
    final ids = (manifest?.chunks ?? const <LectureChunk>[])
        .map((chunk) => chunk.id)
        .toSet();
    bookmarkedChunkIds.removeWhere((id) => !ids.contains(id));
  }

  LectureManifest? get manifest =>
      manifestJson == null ? null : LectureManifest.fromJson(manifestJson!);

  String get title {
    if (customTitle.trim().isNotEmpty) return customTitle.trim();
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
        'custom_title': customTitle,
        'last_position_ms': lastPositionMs,
        'bookmark_index': bookmarkIndex,
        'bookmark_ids': bookmarkedChunkIds,
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
        customTitle: _string(json['custom_title']),
        lastPositionMs: ((json['last_position_ms'] as num?)?.toInt() ?? 0)
            .clamp(0, 86400000),
        bookmarkIndex: (json['bookmark_index'] as num?)?.toInt(),
        bookmarkedChunkIds: (json['bookmark_ids'] as List<dynamic>?)
            ?.whereType<String>()
            .toList(),
      );
}

Map<String, dynamic> decodeObject(String body) {
  final value = jsonDecode(body);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Некорректный ответ сервера');
  }
  return value;
}
