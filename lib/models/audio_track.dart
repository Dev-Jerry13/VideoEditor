/// A background-music track laid on the project timeline.
///
/// Phase 3 exposes a single music track through the UI, but the project
/// stores a list so multiple tracks can be introduced later without
/// rewriting the model.
class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.sourcePath,
    required this.sourceStart,
    required this.sourceEnd,
    this.timelineStart = Duration.zero,
    this.volume = 1.0,
  }) : assert(sourceEnd > sourceStart, 'track range must be positive'),
       assert(volume >= 0 && volume <= 1, 'volume must be within 0..1');

  final String id;
  final String sourcePath;

  /// Which part of the audio file is used (SOURCE time).
  final Duration sourceStart;
  final Duration sourceEnd;

  /// Where the track begins on the PROJECT timeline.
  final Duration timelineStart;

  final double volume;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourcePath': sourcePath,
    'sourceStartMs': sourceStart.inMilliseconds,
    'sourceEndMs': sourceEnd.inMilliseconds,
    'timelineStartMs': timelineStart.inMilliseconds,
    'volume': volume,
  };

  static AudioTrack fromJson(Map<String, dynamic> json) => AudioTrack(
    id: json['id'] as String? ?? '',
    sourcePath: json['sourcePath'] as String? ?? '',
    sourceStart: Duration(milliseconds: json['sourceStartMs'] as int? ?? 0),
    sourceEnd: Duration(milliseconds: json['sourceEndMs'] as int? ?? 1),
    timelineStart: Duration(milliseconds: json['timelineStartMs'] as int? ?? 0),
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
  );

  Duration get sourceDuration => sourceEnd - sourceStart;

  /// Display name derived from the file path.
  String get name => sourcePath
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .last;

  AudioTrack copyWith({
    String? id,
    String? sourcePath,
    Duration? sourceStart,
    Duration? sourceEnd,
    Duration? timelineStart,
    double? volume,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceEnd: sourceEnd ?? this.sourceEnd,
      timelineStart: timelineStart ?? this.timelineStart,
      volume: volume ?? this.volume,
    );
  }
}
