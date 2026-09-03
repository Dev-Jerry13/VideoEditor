import 'video_adjustments.dart';
import 'video_filter.dart';
import 'video_transform.dart';

class VideoClip {
  VideoClip({
    required this.id,
    required this.sourcePath,
    required this.sourceDuration,
    this.trimStart = Duration.zero,
    Duration? trimEnd,
    this.speed = 1.0,
    this.transform = VideoTransform.identity,
    this.filter = VideoFilter.none,
    this.adjustments = VideoAdjustments.neutral,
  }) : trimEnd = trimEnd ?? sourceDuration {
    assert(trimStart >= Duration.zero, 'trimStart must be non-negative');
    assert(this.trimEnd <= sourceDuration, 'trimEnd cannot exceed source');
    assert(trimStart < this.trimEnd, 'trim range must have positive length');
    assert(speed > 0, 'speed must be positive');
  }

  /// Stable identity used for selection, timeline keys and undo snapshots.
  final String id;

  final String sourcePath;
  final Duration sourceDuration;
  final Duration trimStart;
  final Duration trimEnd;

  /// Playback rate applied to this clip's trimmed range. The trim values
  /// stay in SOURCE time; only the timeline footprint shrinks/grows.
  final double speed;

  /// Visual look of this clip (crop/rotate/flip + color). Applied in the
  /// Flutter preview immediately and burned in by FFmpeg at export.
  final VideoTransform transform;
  final VideoFilter filter;
  final VideoAdjustments adjustments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourcePath': sourcePath,
    'sourceDurationMs': sourceDuration.inMilliseconds,
    'trimStartMs': trimStart.inMilliseconds,
    'trimEndMs': trimEnd.inMilliseconds,
    'speed': speed,
    'transform': transform.toJson(),
    'filter': filter.code,
    'adjustments': adjustments.toJson(),
  };

  static VideoClip fromJson(Map<String, dynamic> json) {
    final sourceDuration = Duration(
      milliseconds: json['sourceDurationMs'] as int? ?? 1,
    );
    return VideoClip(
      id: json['id'] as String? ?? '',
      sourcePath: json['sourcePath'] as String? ?? '',
      sourceDuration: sourceDuration,
      trimStart: Duration(milliseconds: json['trimStartMs'] as int? ?? 0),
      trimEnd: Duration(milliseconds: json['trimEndMs'] as int? ?? 1),
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      transform: VideoTransform.fromJson(
        (json['transform'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      filter: VideoFilter.fromCode(json['filter'] as String?),
      adjustments: VideoAdjustments.fromJson(
        (json['adjustments'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  /// Position of the clip within the project timeline is derived from its
  /// index in [VideoProject.clips]; it is intentionally not stored here.
  Duration get trimmedDuration => trimEnd - trimStart;

  /// Length of this clip on the PROJECT timeline once [speed] is applied:
  /// `sourceDuration / speed`.
  Duration get effectiveDuration {
    if (speed == 1.0) return trimmedDuration;
    return Duration(
      milliseconds: (trimmedDuration.inMilliseconds / speed).round(),
    );
  }

  /// Whether [position] (SOURCE time) lies inside the trim range.
  bool containsPosition(Duration position) =>
      position >= trimStart && position <= trimEnd;

  VideoClip copyWith({
    String? id,
    String? sourcePath,
    Duration? sourceDuration,
    Duration? trimStart,
    Duration? trimEnd,
    double? speed,
    VideoTransform? transform,
    VideoFilter? filter,
    VideoAdjustments? adjustments,
  }) {
    return VideoClip(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      speed: speed ?? this.speed,
      transform: transform ?? this.transform,
      filter: filter ?? this.filter,
      adjustments: adjustments ?? this.adjustments,
    );
  }
}
