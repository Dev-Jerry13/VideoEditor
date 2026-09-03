import '../core/constants/app_constants.dart';
import '../core/utils/time_utils.dart';
import '../services/timeline_service.dart';
import 'audio_track.dart';
import 'clip_transition.dart';
import 'text_overlay.dart';
import 'video_adjustments.dart';
import 'video_filter.dart';
import 'video_clip.dart';
import 'video_transform.dart';

/// Generates unique clip ids.
class ClipId {
  ClipId._();

  static int _counter = 0;

  static String next() {
    _counter += 1;
    return 'clip_${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }
}

/// Generates unique ids for audio tracks and text overlays.
class OverlayId {
  OverlayId._();

  static int _counter = 0;

  static String next(String prefix) {
    _counter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }
}

/// Where a project-timeline position lands inside the clip sequence.
///
/// [localPosition] is expressed in OUTPUT time (after speed), matching the
/// project-timeline domain. Positions inside a TRANSITION OVERLAP resolve
/// to the OUTGOING clip (see [TimelineService]).
class ClipAtPosition {
  const ClipAtPosition({required this.clip, required this.localPosition});

  /// Clip that covers [position] (or the last one when past the end).
  final VideoClip clip;

  /// Offset of [position] inside [clip]'s trimmed range, in OUTPUT time.
  final Duration localPosition;
}

/// Thrown when an edit operation would produce an invalid timeline.
class ClipOperationException implements Exception {
  const ClipOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VideoProject {
  VideoProject({
    required this.name,
    required List<VideoClip> clips,
    List<AudioTrack> audioTracks = const [],
    List<TextOverlay> textOverlays = const [],
    Map<String, ClipTransition> transitions = const {},
    this.originalAudioVolume = 1.0,
    this.outputAspectRatio,
  }) : clips = List.of(clips),
       audioTracks = List.of(audioTracks),
       textOverlays = List.of(textOverlays),
       transitions = Map.of(transitions);

  VideoProject._(
    this.name,
    this.clips,
    this.audioTracks,
    this.textOverlays,
    this.transitions,
    this.originalAudioVolume,
    this.outputAspectRatio,
  );

  final String name;

  /// Ordered clip sequence; index in this list is the clip's order.
  ///
  /// Treat as immutable: every operation returns a new [VideoProject] so
  /// undo snapshots never alias live state.
  final List<VideoClip> clips;

  /// Background music tracks. Phase 3 UI exposes at most one, but the
  /// list-based model keeps the door open for more.
  final List<AudioTrack> audioTracks;

  /// Text overlays positioned on the shared project timeline.
  final List<TextOverlay> textOverlays;

  /// Transitions keyed by the LEFT clip's id ("transition after clip X").
  /// Bindings follow their left clip through reorders; lookups validate
  /// lazily that a successor still exists.
  final Map<String, ClipTransition> transitions;

  /// Volume of the source videos' own audio (0..1).
  final double originalAudioVolume;

  /// Output aspect override ('16:9', '9:16', '1:1', …). Null derives the
  /// canvas from the first clip (Phase 2/3 behaviour).
  final String? outputAspectRatio;

  /// Immutable instance → layout computed exactly once, then shared by
  /// all the hot paths (ticks, seeks, timeline painting).
  late final TimelineLayout _layout = TimelineService.resolve(
    clips,
    transitions,
  );

  TimelineLayout get layout => _layout;

  Map<String, dynamic> toJson() => {
    'name': name,
    'clips': clips.map((c) => c.toJson()).toList(),
    'audioTracks': audioTracks.map((a) => a.toJson()).toList(),
    'textOverlays': textOverlays.map((o) => o.toJson()).toList(),
    'transitions': transitions.map((k, v) => MapEntry(k, v.toJson())),
    'originalAudioVolume': originalAudioVolume,
    'outputAspectRatio': outputAspectRatio,
  };

  static VideoProject fromJson(Map<String, dynamic> json) => VideoProject(
    name: json['name'] as String? ?? 'Project',
    clips: (json['clips'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => VideoClip.fromJson(m.cast<String, dynamic>()))
        .toList(),
    audioTracks: (json['audioTracks'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => AudioTrack.fromJson(m.cast<String, dynamic>()))
        .toList(),
    textOverlays: (json['textOverlays'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => TextOverlay.fromJson(m.cast<String, dynamic>()))
        .toList(),
    transitions: (json['transitions'] as Map? ?? const {}).map(
      (k, v) => MapEntry(
        k.toString(),
        ClipTransition.fromJson((v as Map).cast<String, dynamic>()),
      ),
    ),
    originalAudioVolume:
        (json['originalAudioVolume'] as num?)?.toDouble() ?? 1.0,
    outputAspectRatio: json['outputAspectRatio'] as String?,
  );

  /// Sum of OUTPUT durations MINUS transition overlaps — the number every
  /// lane, the playhead and the export agree on.
  Duration get totalDuration => _layout.totalDuration;

  bool get isEmpty => clips.isEmpty;

  bool get isNotEmpty => clips.isNotEmpty;

  AudioTrack? get musicTrack => audioTracks.isEmpty ? null : audioTracks.first;

  /// Resolves a position on the combined project timeline to the covering
  /// clip plus the offset within that clip. Positions past the end clamp
  /// into the last clip. The offset is OUTPUT time.
  ClipAtPosition clipAt(Duration position) {
    assert(clips.isNotEmpty, 'clipAt requires a non-empty project');
    final segment = _layout.segmentAt(position);
    return ClipAtPosition(
      clip: segment.clip,
      localPosition: clampDuration(
        position - segment.projectStart,
        Duration.zero,
        segment.effectiveDuration,
      ),
    );
  }

  /// Project-time position where the given clip starts.
  Duration startOf(VideoClip clip) =>
      _layout.startOf(clip.id) ?? _layout.totalDuration;

  /// Inverse of [clipAt]: converts an OUTPUT-local offset into project time.
  Duration projectTimeOf(VideoClip clip, Duration localOutput) =>
      startOf(clip) +
      clampDuration(localOutput, Duration.zero, clip.effectiveDuration);

  /// Converts an OUTPUT-local offset into SOURCE time (the trim window of
  /// [clip]) — used to translate playhead positions into seek targets and
  /// split points. Independent of the layout: pure per-clip conversion.
  Duration sourceOffsetFor(VideoClip clip, Duration localOutput) {
    final ratio = clip.effectiveDuration.inMilliseconds <= 0 ? 0.0 : clip.speed;
    final sourceLocal = localOutput * ratio;
    return clampDuration(
      clip.trimStart + sourceLocal,
      clip.trimStart,
      clip.trimEnd,
    );
  }

  /// Raw transition stored after [clipId], only when a successor exists.
  ClipTransition? transitionAfter(String clipId) {
    final index = indexOf(clipId);
    if (index < 0 || index + 1 >= clips.length) return null;
    return transitions[clipId];
  }

  int indexOf(String clipId) => clips.indexWhere((c) => c.id == clipId);

  // -- Immutable edit operations ---------------------------------------------

  /// Splits the clip at [clipId] into two clips at [sourceOffset], measured
  /// from the SOURCE trim start. Both resulting segments must be at least
  /// [minSegment] long; the split inherits the clip's visuals and keeps any
  /// transition bound to the LEFT half.
  VideoProject splitClip(
    String clipId,
    Duration sourceOffset, {
    required Duration minSegment,
    String Function() newId = ClipId.next,
  }) {
    final index = indexOf(clipId);
    if (index < 0) {
      throw ClipOperationException('Clip not found.');
    }
    final clip = clips[index];
    final duration = clip.trimmedDuration;

    if (sourceOffset <= Duration.zero || sourceOffset >= duration) {
      throw const ClipOperationException(
        'Move the playhead inside the clip to split it.',
      );
    }
    if (sourceOffset < minSegment || duration - sourceOffset < minSegment) {
      throw const ClipOperationException(
        'Not enough room to split — both parts must stay above the minimum '
        'clip length.',
      );
    }

    final splitPoint = clip.trimStart + sourceOffset;
    final left = clip.copyWith(trimEnd: splitPoint);
    final right = clip.copyWith(
      id: newId(),
      trimStart: splitPoint,
      trimEnd: clip.trimEnd,
    );

    return _replaceRange(index, index + 1, [left, right]);
  }

  /// Removes the clip at [clipId] along with any transition bound to it or
  /// pointing at it. Refuses when it is the only clip.
  VideoProject removeClip(String clipId) {
    if (clips.length <= 1) {
      throw const ClipOperationException('Cannot delete the only clip.');
    }
    final index = indexOf(clipId);
    if (index < 0) {
      throw ClipOperationException('Clip not found.');
    }
    final next = _copyWithoutTransitionsAround(index);
    return next._replaceRange(index, index + 1, const []);
  }

  /// Drops bindings that reference the clip at [index] as left side or its
  /// successor slot (the right side of the seam before it).
  VideoProject _copyWithoutTransitionsAround(int index) {
    final id = clips[index].id;
    final previousId = index > 0 ? clips[index - 1].id : null;
    final stale = <String>{id};
    if (previousId != null) {
      stale.add(previousId);
    }
    if (!transitions.keys.any(stale.contains)) return this;
    return VideoProject._(
      name,
      clips,
      audioTracks,
      textOverlays,
      Map.of(transitions)..removeWhere((k, _) => stale.contains(k)),
      originalAudioVolume,
      outputAspectRatio,
    );
  }

  /// Moves the clip at [oldIndex] to [newIndex] (same semantics as
  /// [dart:core.List.remove] + insert, matching ReorderableListView).
  ///
  /// Transitions follow their LEFT clip; bindings whose seam partners
  /// changed simply apply to whatever now follows — undo restores the
  /// exact original arrangement either way.
  VideoProject reordered(int oldIndex, int newIndex) {
    assert(oldIndex >= 0 && oldIndex < clips.length, 'oldIndex out of range');
    assert(newIndex >= 0 && newIndex <= clips.length, 'newIndex out of range');
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target == oldIndex) return this;

    final order = List.of(clips);
    final moved = order.removeAt(oldIndex);
    order.insert(target, moved);
    return VideoProject._(
      name,
      order,
      audioTracks,
      textOverlays,
      transitions,
      originalAudioVolume,
      outputAspectRatio,
    );
  }

  /// Returns a copy with the clip's trim range replaced. Enforces source
  /// bounds and a minimum length of [minSegment].
  VideoProject withTrim(
    String clipId, {
    required Duration trimStart,
    required Duration trimEnd,
    required Duration minSegment,
  }) {
    final index = indexOf(clipId);
    if (index < 0) {
      throw ClipOperationException('Clip not found.');
    }
    final clip = clips[index];
    final newStart = clampDuration(
      trimStart,
      Duration.zero,
      clip.sourceDuration,
    );
    final newEnd = clampDuration(trimEnd, Duration.zero, clip.sourceDuration);
    if (newEnd - newStart < minSegment) {
      throw const ClipOperationException('Trim range is too short.');
    }
    return _withClip(
      index,
      clip.copyWith(trimStart: newStart, trimEnd: newEnd),
    );
  }

  /// Returns a copy with the clip's playback speed replaced. Speeds outside
  /// [AppConstants.minPlaybackSpeed]..[AppConstants.maxPlaybackSpeed] are
  /// rejected. Transition overlaps shrink/grow automatically because the
  /// resolver clamps against the neighbours' NEW effective durations.
  VideoProject withSpeed(String clipId, double speed) {
    if (speed < AppConstants.minPlaybackSpeed ||
        speed > AppConstants.maxPlaybackSpeed) {
      throw ClipOperationException(
        'Speed must be between ${AppConstants.minPlaybackSpeed}x '
        'and ${AppConstants.maxPlaybackSpeed}x.',
      );
    }
    final index = indexOf(clipId);
    if (index < 0) {
      throw ClipOperationException('Clip not found.');
    }
    return _withClip(index, clips[index].copyWith(speed: speed));
  }

  // -- Phase 4: visual operations ---------------------------------------------

  VideoProject withTransform(String clipId, VideoTransform value) =>
      _mapClip(clipId, (c) => c.copyWith(transform: value));

  VideoProject withFilter(String clipId, VideoFilter value) =>
      _mapClip(clipId, (c) => c.copyWith(filter: value));

  VideoProject withAdjustments(String clipId, VideoAdjustments value) =>
      _mapClip(clipId, (c) => c.copyWith(adjustments: value));

  /// Restores crop/rotate/flip/filter/adjustments to defaults WITHOUT
  /// touching trim/speed/audio/text (plan §15).
  VideoProject resetVisuals(String clipId) => _mapClip(
    clipId,
    (c) => c.copyWith(
      transform: VideoTransform.identity,
      filter: VideoFilter.none,
      adjustments: VideoAdjustments.neutral,
    ),
  );

  /// Sets or clears the transition after [leftClipId]. Requires an existing
  /// successor. Stored raw — [TimelineService] clamps on read so trimming a
  /// neighbour later can never produce an impossible timeline.
  VideoProject upsertTransition(String leftClipId, ClipTransition transition) {
    final index = indexOf(leftClipId);
    if (index < 0 || index + 1 >= clips.length) {
      throw const ClipOperationException(
        'Transitions need two adjacent clips.',
      );
    }
    if (!transition.isActive && !transitions.containsKey(leftClipId)) {
      return this;
    }
    final next = Map.of(transitions);
    if (!transition.isActive) {
      next.remove(leftClipId);
    } else {
      next[leftClipId] = transition;
    }
    return VideoProject._(
      name,
      clips,
      audioTracks,
      textOverlays,
      next,
      originalAudioVolume,
      outputAspectRatio,
    );
  }

  /// Validates and stores the project-wide output aspect override.
  VideoProject withOutputAspectRatio(String? ratio) {
    if (ratio == outputAspectRatio) return this;
    if (ratio != null && !_aspectPattern.hasMatch(ratio)) {
      throw ClipOperationException('Unsupported aspect ratio.');
    }
    return VideoProject._(
      name,
      clips,
      audioTracks,
      textOverlays,
      transitions,
      originalAudioVolume,
      ratio,
    );
  }

  static final RegExp _aspectPattern = RegExp(r'^\d{1,3}:\d{1,3}$');

  /// Inserts or replaces [track] (matched by id). Phase 3 keeps a single
  /// track: callers typically replace the whole list instead.
  VideoProject upsertAudioTrack(AudioTrack track) {
    final index = audioTracks.indexWhere((t) => t.id == track.id);
    final next = List.of(audioTracks);
    if (index >= 0) {
      next[index] = track;
    } else {
      next.add(track);
    }
    return _copyWithAudio(next);
  }

  VideoProject withoutAudioTrack(String trackId) =>
      _copyWithAudio(List.of(audioTracks)..removeWhere((t) => t.id == trackId));

  VideoProject withOriginalAudioVolume(double volume) {
    final clamped = volume.clamp(0.0, AppConstants.maxAudioVolume);
    return VideoProject._(
      name,
      clips,
      audioTracks,
      textOverlays,
      transitions,
      clamped,
      outputAspectRatio,
    );
  }

  /// Inserts or replaces [overlay] (matched by id).
  VideoProject upsertTextOverlay(TextOverlay overlay) {
    final index = textOverlays.indexWhere((o) => o.id == overlay.id);
    final next = List.of(textOverlays);
    if (index >= 0) {
      next[index] = overlay;
    } else {
      next.add(overlay);
    }
    return _copyWithText(next);
  }

  VideoProject withoutTextOverlay(String overlayId) => _copyWithText(
    List.of(textOverlays)..removeWhere((o) => o.id == overlayId),
  );

  /// Appends [clips] to the end of the sequence, preserving every other
  /// project property.
  VideoProject appended(List<VideoClip> newClips) => VideoProject._(
    name,
    [...clips, ...newClips],
    audioTracks,
    textOverlays,
    transitions,
    originalAudioVolume,
    outputAspectRatio,
  );

  /// Shallow copy sharing clip instances (they are immutable); every list
  /// is freshly allocated so snapshots compare by identity.
  VideoProject copy() => VideoProject(
    name: name,
    clips: clips,
    audioTracks: audioTracks,
    textOverlays: textOverlays,
    transitions: transitions,
    originalAudioVolume: originalAudioVolume,
    outputAspectRatio: outputAspectRatio,
  );

  // -- Internal constructors ---------------------------------------------------

  VideoProject _mapClip(String clipId, VideoClip Function(VideoClip) edit) {
    final index = indexOf(clipId);
    if (index < 0) {
      throw ClipOperationException('Clip not found.');
    }
    return _withClip(index, edit(clips[index]));
  }

  VideoProject _withClip(int index, VideoClip updated) => VideoProject._(
    name,
    List.of(clips)..[index] = updated,
    audioTracks,
    textOverlays,
    transitions,
    originalAudioVolume,
    outputAspectRatio,
  );

  VideoProject _replaceRange(int start, int end, List<VideoClip> replacement) {
    final order = List.of(clips)..replaceRange(start, end, replacement);
    return VideoProject._(
      name,
      order,
      audioTracks,
      textOverlays,
      transitions,
      originalAudioVolume,
      outputAspectRatio,
    );
  }

  VideoProject _copyWithAudio(List<AudioTrack> tracks) => VideoProject._(
    name,
    clips,
    tracks,
    textOverlays,
    transitions,
    originalAudioVolume,
    outputAspectRatio,
  );

  VideoProject _copyWithText(List<TextOverlay> overlays) => VideoProject._(
    name,
    clips,
    audioTracks,
    overlays,
    transitions,
    originalAudioVolume,
    outputAspectRatio,
  );
}
