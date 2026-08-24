import '../models/clip_transition.dart';
import '../models/video_clip.dart';

/// THE authority for where clips sit on the project timeline once
/// transitions overlap their neighbours.
///
/// Every consumer — [VideoProject] math, the playhead/tick conversion,
/// trim/split/delete mapping, TEXT/AUDIO lanes, export weights and xfade
/// offsets — MUST derive positions from this layout. Nothing else is
/// allowed to accumulate clip durations on its own.
///
/// Coverage rule inside an overlap window `[startNext, outgoing.end)`:
/// both clips render simultaneously (crossfade), but POSITION LOOKUPS map
/// to the OUTGOING clip so seeking stays anchored to what was already on
/// screen.
class TimelineService {
  TimelineService._();

  static TimelineLayout resolve(
    List<VideoClip> clips,
    Map<String, ClipTransition> transitions,
  ) {
    final segments = <SegmentLayout>[];
    var cursor = Duration.zero;

    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      segments.add(SegmentLayout(
        clip: clip,
        projectStart: cursor,
        effectiveDuration: clip.effectiveDuration,
        transitionAfter: transitions[clip.id] ?? ClipTransition.none,
        nextEffective: i + 1 < clips.length
            ? clips[i + 1].effectiveDuration
            : null,
      ));
      cursor += clip.effectiveDuration - segments.last.overlapAfter;
    }

    return TimelineLayout(segments: segments, totalDuration: cursor);
  }
}

class SegmentLayout {
  SegmentLayout({
    required this.clip,
    required this.projectStart,
    required this.effectiveDuration,
    required this.transitionAfter,
    required this.nextEffective,
  });

  final VideoClip clip;
  final Duration projectStart;
  final Duration effectiveDuration;

  /// Raw transition stored after this clip (may be clamped below).
  final ClipTransition transitionAfter;

  /// Output duration of the FOLLOWING clip, or null at the sequence end —
  /// needed because the overlap is limited by BOTH neighbours.
  final Duration? nextEffective;

  late final Duration overlapAfter = nextEffective == null
      ? Duration.zero
      : transitionAfter.effectiveFor(effectiveDuration, nextEffective!);

  /// Where the NEXT clip starts (= where this clip's exclusive ownership
  /// of the playhead ends and the crossfade window begins).
  Duration get seam => projectStart + effectiveDuration - overlapAfter;

  /// Exclusive end of this clip's coverage (== next clip's start).
  Duration get coveredEnd => projectStart + effectiveDuration;
}

class TimelineLayout {
  const TimelineLayout({
    required this.segments,
    required this.totalDuration,
  });

  final List<SegmentLayout> segments;
  final Duration totalDuration;

  /// Segment covering [position]. Positions inside an overlap resolve to
  /// the OUTGOING clip; positions past the end clamp into the last one.
  int indexAt(Duration position) {
    assert(segments.isNotEmpty, 'layout requires at least one segment');
    for (var i = 0; i < segments.length; i++) {
      if (position < segments[i].coveredEnd) return i;
    }
    return segments.length - 1;
  }

  SegmentLayout segmentAt(Duration position) => segments[indexAt(position)];

  /// Project-time start of the given clip id, or null when absent.
  Duration? startOf(String clipId) {
    for (final segment in segments) {
      if (segment.clip.id == clipId) return segment.projectStart;
    }
    return null;
  }

  /// Sum of all overlaps — exported for progress-weighting and tests.
  Duration get totalOverlap => segments.fold(
        Duration.zero,
        (sum, s) => sum + s.overlapAfter,
      );
}
