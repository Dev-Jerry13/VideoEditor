import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/core/constants/app_constants.dart';
import 'package:video_editor/models/audio_track.dart';
import 'package:video_editor/models/clip_transition.dart';
import 'package:video_editor/models/text_overlay.dart';
import 'package:video_editor/models/video_adjustments.dart';
import 'package:video_editor/models/video_clip.dart';
import 'package:video_editor/models/video_filter.dart';
import 'package:video_editor/models/video_project.dart';
import 'package:video_editor/models/video_transform.dart';

VideoClip clip(
  String id,
  Duration duration, {
  Duration trimStart = Duration.zero,
  Duration? trimEnd,
}) {
  return VideoClip(
    id: id,
    sourcePath: '/source/$id.mp4',
    sourceDuration: duration,
    trimStart: trimStart,
    trimEnd: trimEnd ?? duration,
  );
}

/// A=5s, B=8s (trimmed to 8s output), C=4s → 17s without transitions.
VideoProject project({Map<String, ClipTransition> transitions = const {}}) =>
    VideoProject(
      name: 'test',
      clips: [
        clip('a', const Duration(seconds: 5)),
        clip('b', const Duration(seconds: 12),
            trimStart: const Duration(seconds: 2),
            trimEnd: const Duration(seconds: 10)),
        clip('c', const Duration(seconds: 4)),
      ],
      transitions: transitions,
    );

void main() {
  group('CropSettings', () {
    test('defaults describe the full frame', () {
      const crop = CropSettings.full;
      expect(crop.isIdentity, isTrue);
      expect(crop.widthFraction, 1);
      expect(crop.heightFraction, 1);
    });

    test('copyWith replaces only given fields and compares by value', () {
      const crop = CropSettings(left: 0.25, right: 0.75);
      final cropped = crop.copyWith(top: 0.1, bottom: 0.9);
      expect(cropped.left, 0.25);
      expect(cropped.top, 0.1);
      expect(cropped.bottom, 0.9);
      expect(cropped, const CropSettings(left: 0.25, top: 0.1, right: 0.75, bottom: 0.9));
      expect(cropped.isIdentity, isFalse);
    });
  });

  group('Rotation', () {
    test('maps to quarter turns and dimension swapping', () {
      expect(Rotation.none.quarterTurns, 0);
      expect(Rotation.clockwise90.quarterTurns, 1);
      expect(Rotation.clockwise180.quarterTurns, 2);
      expect(Rotation.clockwise270.quarterTurns, 3);
      expect(Rotation.none.swapsDimensions, isFalse);
      expect(Rotation.clockwise90.swapsDimensions, isTrue);
      expect(Rotation.clockwise180.swapsDimensions, isFalse);
      expect(Rotation.clockwise270.swapsDimensions, isTrue);
    });
  });

  group('VideoAdjustments', () {
    test('neutral default and detection', () {
      expect(VideoAdjustments.neutral.isNeutral, isTrue);
      expect(
        VideoAdjustments(brightness: -100).isNeutral,
        isFalse,
      );
    });

    test('clamp enforces ±100 range', () {
      expect(VideoAdjustments.clamp(150), 100);
      expect(VideoAdjustments.clamp(-150), -100);
      expect(VideoAdjustments.clamp(42), 42);
    });

    test('equality covers all four channels', () {
      expect(
        VideoAdjustments(brightness: 10, contrast: 20, saturation: 30, temperature: -40),
        VideoAdjustments(brightness: 10, contrast: 20, saturation: 30, temperature: -40),
      );
      expect(
        VideoAdjustments(brightness: 10),
        isNot(VideoAdjustments(brightness: 11)),
      );
    });
  });

  group('VideoFilter', () {
    test('labels cover every preset', () {
      expect(VideoFilter.values.length, 8);
      expect(VideoFilter.none.label, 'Original');
      expect(VideoFilter.highContrast.label, 'High Contrast');
    });
  });

  group('ClipTransition', () {
    test('inactive transitions never overlap', () {
      const inactive = ClipTransition(type: TransitionType.none, duration: Duration(seconds: 9));
      expect(inactive.isActive, isFalse);
      expect(
        inactive.effectiveFor(const Duration(seconds: 5), const Duration(seconds: 5)),
        Duration.zero,
      );
    });

    test('effectiveFor clamps to half the shorter neighbour', () {
      // Stored 4s, capacity min(5s, 5s) / 2 = 2.5s.
      const big = ClipTransition(type: TransitionType.fade, duration: Duration(seconds: 4));
      expect(
        big.effectiveFor(const Duration(seconds: 5), const Duration(seconds: 5)),
        const Duration(milliseconds: 2500),
      );

      // Stored 2s fits exactly into min(5s, 8s) / 2 = 2.5s.
      const fits = ClipTransition(type: TransitionType.dissolve, duration: Duration(seconds: 2));
      expect(fits.effectiveFor(const Duration(seconds: 5), const Duration(seconds: 8)),
          const Duration(seconds: 2));
    });

    test('equality and copyWith', () {
      const t = ClipTransition(type: TransitionType.slideLeft);
      expect(t.duration, AppConstants.defaultTransitionDuration);
      expect(t, const ClipTransition(type: TransitionType.slideLeft));
      expect(t.copyWith(type: TransitionType.zoom).type, TransitionType.zoom);
    });
  });

  group('timeline overlap math (no transitions)', () {
    test('matches the legacy accumulation exactly', () {
      final p = project();
      expect(p.totalDuration, const Duration(seconds: 17));
      expect(p.startOf(p.clips[0]), Duration.zero);
      expect(p.startOf(p.clips[1]), const Duration(seconds: 5));
      expect(p.startOf(p.clips[2]), const Duration(seconds: 13));
    });
  });

  group('timeline overlap math (with transitions)', () {
    test('overlap shortens total and shifts later clips forward', () {
      final p = project(transitions: {
        'a': const ClipTransition(
            type: TransitionType.fade, duration: Duration(seconds: 2)),
      });
      // 5 + 8 + 4 = 17, minus 2s overlap = 15s. C starts at 3 + 8 = 11s.
      expect(p.totalDuration, const Duration(seconds: 15));
      expect(p.startOf(p.clips[1]), const Duration(seconds: 3));
      expect(p.startOf(p.clips[2]), const Duration(seconds: 11));
    });

    test('positions inside the overlap resolve to the OUTGOING clip', () {
      final p = project(transitions: {
        'a': const ClipTransition(
            type: TransitionType.fade, duration: Duration(seconds: 2)),
      });
      // Overlap window [3s, 5s): A still owns the playhead.
      final inside = p.clipAt(const Duration(milliseconds: 3500));
      expect(inside.clip.id, 'a');
      expect(inside.localPosition, const Duration(milliseconds: 3500));

      // After A's real end the position belongs to B.
      final after = p.clipAt(const Duration(seconds: 6));
      expect(after.clip.id, 'b');
      expect(after.localPosition, const Duration(seconds: 3));
    });

    test('stored durations exceeding neighbour capacity are clamped', () {
      final p = project(transitions: {
        'a': const ClipTransition(
            type: TransitionType.fade, duration: Duration(seconds: 2)),
        // min(effB=8s, effC=4s) / 2 = 2s → requested 3s clamps to 2s.
        'b': const ClipTransition(
            type: TransitionType.dissolve, duration: Duration(seconds: 3)),
      });
      expect(p.totalDuration, const Duration(seconds: 13)); // 17 − 2 − 2
      expect(p.startOf(p.clips[2]), const Duration(seconds: 9));
      expect(p.layout.segments[1].overlapAfter, const Duration(seconds: 2));
    });

    test('transition bound to the LAST clip is inert', () {
      final p = project(transitions: {
        'c': const ClipTransition(
            type: TransitionType.fade, duration: Duration(seconds: 1)),
      });
      expect(p.totalDuration, const Duration(seconds: 17));
      expect(p.transitionAfter('c'), isNull);
      expect(p.layout.segments.last.overlapAfter, Duration.zero);
    });

    test('last segment ends exactly at totalDuration', () {
      final p = project(transitions: {
        'a': const ClipTransition(
            type: TransitionType.fade, duration: Duration(seconds: 2)),
        'b': const ClipTransition(
            type: TransitionType.dissolve, duration: Duration(seconds: 2)),
      });
      final layout = p.layout;
      expect(layout.segments.last.coveredEnd, p.totalDuration);
      expect(layout.totalOverlap, const Duration(seconds: 4));
    });

    test('layout instance is cached per immutable project', () {
      final p = project();
      expect(identical(p.layout, p.layout), isTrue);
    });
  });

  group('upsertTransition', () {
    test('stores and replaces the binding after a clip', () {
      var p = project();
      p = p.upsertTransition(
        'a',
        const ClipTransition(type: TransitionType.fade),
      );
      expect(p.transitionAfter('a')?.type, TransitionType.fade);
      // 500ms fits into min(5s, 8s) / 2 = 2.5s capacity.
      expect(p.totalDuration, const Duration(milliseconds: 16500));

      p = p.upsertTransition(
        'a',
        const ClipTransition(type: TransitionType.white, duration: Duration(seconds: 1)),
      );
      expect(p.transitionAfter('a')?.type, TransitionType.white);
      expect(p.transitionAfter('a')?.duration, const Duration(seconds: 1));
    });

    test('setting type none removes the binding entirely', () {
      final withT = project().upsertTransition(
        'a',
        const ClipTransition(type: TransitionType.fade),
      );
      final cleared = withT.upsertTransition('a', ClipTransition.none);
      expect(cleared.transitions, isEmpty);
      expect(cleared.totalDuration, const Duration(seconds: 17));

      // Clearing an absent binding is a no-op returning the SAME instance.
      final noop = project().upsertTransition('a', ClipTransition.none);
      expect(identical(noop, noop), isTrue);
    });

    test('requires an existing successor', () {
      expect(
        () => project().upsertTransition(
          'c',
          const ClipTransition(type: TransitionType.fade),
        ),
        throwsClipOperationException,
      );
      expect(
        () => project().upsertTransition(
          'missing',
          const ClipTransition(type: TransitionType.fade),
        ),
        throwsClipOperationException,
      );
    });

    test('never mutates the original project', () {
      final original = project();
      final updated = original.upsertTransition(
        'a',
        const ClipTransition(type: TransitionType.fade),
      );
      expect(original.transitions, isEmpty);
      expect(updated.transitions.length, 1);
    });
  });

  group('visual operations', () {
    test('withTransform / withFilter / withAdjustments touch only the target', () {
      final p = project()
          .withTransform('b', const VideoTransform(crop: CropSettings(left: 0.5)))
          .withFilter('b', VideoFilter.warm)
          .withAdjustments('b', const VideoAdjustments(brightness: 25));

      expect(p.clips[0].transform.isIdentity, isTrue);
      expect(p.clips[2].filter, VideoFilter.none);
      expect(p.clips[1].transform.crop.left, 0.5);
      expect(p.clips[1].filter, VideoFilter.warm);
      expect(p.clips[1].adjustments.brightness, 25);
      // Trim untouched by visual edits.
      expect(p.clips[1].trimmedDuration, const Duration(seconds: 8));
    });

    test('resetVisuals restores identity but keeps trim/speed/audio/text/transitions',
        () {
      final track = AudioTrack(
        id: 'm1',
        sourcePath: '/music.mp3',
        sourceStart: Duration.zero,
        sourceEnd: Duration(minutes: 3),
      );
      final overlay = TextOverlay(
        id: 't1',
        text: 'hello',
        startTime: Duration(seconds: 1),
        endTime: Duration(seconds: 3),
      );

      final edited = project(transitions: {
        'a': const ClipTransition(type: TransitionType.fade),
      })
          .withSpeed('b', 2)
          .withTransform('b', const VideoTransform(crop: CropSettings(right: 0.5)))
          .withFilter('b', VideoFilter.vintage)
          .withAdjustments('b', const VideoAdjustments(saturation: -50))
          .withOriginalAudioVolume(0.5)
          .upsertAudioTrack(track)
          .upsertTextOverlay(overlay);

      final reset = edited.resetVisuals('b');
      expect(reset.clips[1].transform.isIdentity, isTrue);
      expect(reset.clips[1].filter, VideoFilter.none);
      expect(reset.clips[1].adjustments.isNeutral, isTrue);
      expect(reset.clips[1].speed, 2); // preserved
      expect(reset.originalAudioVolume, 0.5); // preserved
      expect(reset.musicTrack?.id, 'm1'); // preserved
      expect(reset.textOverlays.single.text, 'hello'); // preserved
      expect(reset.transitions['a']?.type, TransitionType.fade); // preserved
    });
  });

  group('output aspect ratio', () {
    test('accepts valid ratios and rejects malformed ones', () {
      final p = project().withOutputAspectRatio('9:16');
      expect(p.outputAspectRatio, '9:16');
      expect(project().withOutputAspectRatio(null).outputAspectRatio, isNull);

      expect(() => project().withOutputAspectRatio('widescreen'),
          throwsClipOperationException);
      expect(() => project().withOutputAspectRatio('16'),
          throwsClipOperationException);
    });

    test('returns the same instance when unchanged', () {
      final p = project();
      expect(identical(p.withOutputAspectRatio(null), p), isTrue);
    });
  });

  group('structural operations interact with transitions', () {
    test('removeClip drops bindings touching the removed clip or its seam', () {
      final p = project(transitions: {
        'a': const ClipTransition(type: TransitionType.fade),
        'b': const ClipTransition(type: TransitionType.dissolve),
      }).removeClip('b');

      expect(p.clips.map((c) => c.id), ['a', 'c']);
      // 'a'→B died with B; 'b'→C died with B. Nothing dangles.
      expect(p.transitions, isEmpty);
      expect(p.totalDuration, const Duration(seconds: 9));
    });

    test('split keeps the transition with the LEFT half', () {
      final before = project(transitions: {
        'a': const ClipTransition(type: TransitionType.fade, duration: Duration(seconds: 2)),
      });
      final after = before.splitClip(
        'a',
        const Duration(seconds: 2),
        minSegment: const Duration(milliseconds: 500),
        newId: () => 'a2',
      );

      expect(after.clips.map((c) => c.id), ['a', 'a2', 'b', 'c']);
      expect(after.clips[0].trimEnd, const Duration(seconds: 2));
      expect(after.clips[1].trimStart, const Duration(seconds: 2));
      // The binding now sits on the NEW seam a|a2, whose capacity is only
      // min(2s, 3s) / 2 = 1s → the stored 2s clamps to 1s there.
      expect(after.totalDuration, const Duration(seconds: 16)); // 17 − 1
      expect(after.layout.segments.first.overlapAfter, const Duration(seconds: 1));
      // …and the binding still hangs off the LEFT piece's ORIGINAL id chain:
      // 'a' is the left half, so it owns the transition.
      expect(after.transitionAfter('a'), isNotNull);
      expect(after.transitionAfter('a2'), isNull);
    });

    test('reordered keeps the binding attached to its own clip', () {
      final moved = project(transitions: {
        'a': const ClipTransition(type: TransitionType.fade, duration: Duration(seconds: 2)),
      }).reordered(0, 3);

      // Order is now b, c, a. The transition stays bound AFTER clip 'a',
      // which is now LAST → no successor, so it is inert. Moving 'a' back
      // before another clip reactivates it.
      expect(moved.clips.map((c) => c.id), ['b', 'c', 'a']);
      expect(moved.transitions['a'], isNotNull);
      expect(moved.totalDuration, const Duration(seconds: 17)); // unchanged
      expect(moved.layout.segments.last.overlapAfter, Duration.zero);
      expect(moved.transitionAfter('a'), isNull); // inert at read time
    });

    test('appended preserves music, text, volume, aspect and transitions', () {
      final p = project(transitions: {
        'a': const ClipTransition(type: TransitionType.fade),
      })
          .withOriginalAudioVolume(0.25)
          .withOutputAspectRatio('1:1')
          .appended([clip('d', const Duration(seconds: 6))]);

      expect(p.clips.last.id, 'd');
      expect(p.originalAudioVolume, 0.25);
      expect(p.outputAspectRatio, '1:1');
      expect(p.transitions['a'], isNotNull);
      expect(p.musicTrack, isNull);
    });
  });
}

Matcher get throwsClipOperationException =>
    throwsA(isA<ClipOperationException>());
