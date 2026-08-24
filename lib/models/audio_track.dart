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
  })  : assert(sourceEnd > sourceStart, 'track range must be positive'),
        assert(volume >= 0 && volume <= 1, 'volume must be within 0..1');

  final String id;
  final String sourcePath;

  /// Which part of the audio file is used (SOURCE time).
  final Duration sourceStart;
  final Duration sourceEnd;

  /// Where the track begins on the PROJECT timeline.
  final Duration timelineStart;

  final double volume;

  Duration get sourceDuration => sourceEnd - sourceStart;

  /// Display name derived from the file path.
  String get name =>
      sourcePath.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;

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
