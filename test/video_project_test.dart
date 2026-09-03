import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/models/audio_track.dart';
import 'package:video_editor/models/clip_transition.dart';
import 'package:video_editor/models/text_overlay.dart';
import 'package:video_editor/models/video_clip.dart';
import 'package:video_editor/models/video_project.dart';

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

/// Project with three clips: A=5s, B=8s, C=4s → total 17s.
VideoProject project() => VideoProject(
      name: 'test',
      clips: [
        clip('a', const Duration(seconds: 5)),
        clip('b', const Duration(seconds: 12), trimStart: const Duration(seconds: 2),
            trimEnd: const Duration(seconds: 10)),
        clip('c', const Duration(seconds: 4)),
      ],
    );

const minSegment = Duration(milliseconds: 100);

void main() {
  group('totalDuration', () {
    test('sums trimmed durations', () {
      expect(project().totalDuration, const Duration(seconds: 17));
    });
  });

  group('project metadata preservation', () {
    test('renamed changes only the project name', () {
      final original = project();
      final renamed = original.renamed('Weekend edit');

      expect(renamed.name, 'Weekend edit');
      expect(renamed.clips, original.clips);
      expect(renamed.totalDuration, original.totalDuration);
    });

    test('withClips preserves project-level editing settings', () {
      final original = VideoProject(
        name: 'test',
        clips: project().clips,
        originalAudioVolume: .4,
        outputAspectRatio: '9:16',
      );
      final updated = original.withClips([original.clips.first]);

      expect(updated.clips, hasLength(1));
      expect(updated.originalAudioVolume, .4);
      expect(updated.outputAspectRatio, '9:16');
    });
  });

  group('clipAt (project position → clip + local offset)', () {
    test('resolves inside the first clip', () {
      final result = project().clipAt(const Duration(seconds: 3));
      expect(result.clip.id, 'a');
      expect(result.localPosition, const Duration(seconds: 3));
    });

    test('resolves across a boundary into the second clip', () {
      // Project time 7s = end of A (5s) + 2s into B.
      final result = project().clipAt(const Duration(seconds: 7));
      expect(result.clip.id, 'b');
      expect(result.localPosition, const Duration(seconds: 2));
    });

    test('resolves inside the last clip', () {
      final result = project().clipAt(const Duration(seconds: 15));
      expect(result.clip.id, 'c');
      expect(result.localPosition, const Duration(seconds: 2));
    });

    test('clamps positions past the end into the last clip', () {
      final result = project().clipAt(const Duration(minutes: 10));
      expect(result.clip.id, 'c');
      expect(result.localPosition, const Duration(seconds: 4));
    });
  });

  group('startOf / projectTimeOf (inverse mapping)', () {
    test('startOf returns accumulated durations of preceding clips', () {
      final p = project();
      expect(p.startOf(p.clips[0]), Duration.zero);
      expect(p.startOf(p.clips[1]), const Duration(seconds: 5));
      expect(p.startOf(p.clips[2]), const Duration(seconds: 13));
    });

    test('projectTimeOf inverts clipAt', () {
      final p = project();
      const projectPos = Duration(seconds: 9);
      final resolved = p.clipAt(projectPos);
      expect(
        p.projectTimeOf(resolved.clip, resolved.localPosition),
        projectPos,
      );
    });
  });

  group('splitClip', () {
    test('replaces one clip with two segments sharing the source range',
        () {
      var idCounter = 0;
      final p = project()
          .splitClip(
            'b',
            const Duration(seconds: 3),
            minSegment: minSegment,
            newId: () => 'split_${idCounter++}',
          )
          .clips;

      expect(p.length, 4);
      // B was trimmed [2s, 10s]; splitting at local 3s → [2s, 5s] + [5s, 10s].
      expect(p[1].trimStart, const Duration(seconds: 2));
      expect(p[1].trimEnd, const Duration(seconds: 5));
      expect(p[2].trimStart, const Duration(seconds: 5));
      expect(p[2].trimEnd, const Duration(seconds: 10));
      // Order and neighbours are preserved.
      expect(p[0].id, 'a');
      expect(p[3].id, 'c');
      // Total duration is unchanged by a split.
      expect(
        VideoProject(name: 'x', clips: p).totalDuration,
        const Duration(seconds: 17),
      );
    });

    test('rejects splits at the very start or end', () {
      final p = project();
      expect(
        () => p.splitClip('a', Duration.zero, minSegment: minSegment),
        throwsA(isA<ClipOperationException>()),
      );
      expect(
        () => p.splitClip(
            'a', const Duration(seconds: 5), minSegment: minSegment),
        throwsA(isA<ClipOperationException>()),
      );
    });

    test('enforces the minimum segment length on both sides', () {
      final p = project();
      expect(
        () => p.splitClip(
            'a', const Duration(milliseconds: 50), minSegment: minSegment),
        throwsA(isA<ClipOperationException>()),
      );
      expect(
        () => p.splitClip('a',
            const Duration(seconds: 5) - const Duration(milliseconds: 50),
            minSegment: minSegment),
        throwsA(isA<ClipOperationException>()),
      );
    });

    test('throws for unknown clips', () {
      expect(
        () =>
            project().splitClip('zzz', Duration.zero, minSegment: minSegment),
        throwsA(isA<ClipOperationException>()),
      );
    });
  });

  group('removeClip', () {
    test('removes the clip and keeps the order of the rest', () {
      final result = project().removeClip('b').clips;
      expect(result.map((c) => c.id), ['a', 'c']);
    });

    test('refuses to empty the project', () {
      final single =
          VideoProject(name: 'x', clips: [clip('only', const Duration(seconds: 1))]);
      expect(
        () => single.removeClip('only'),
        throwsA(isA<ClipOperationException>()),
      );
    });
  });

  group('reordered', () {
    test('follows remove-then-insert index semantics', () {
      final result = project().reordered(2, 0).clips;
      expect(result.map((c) => c.id), ['c', 'a', 'b']);
    });

    test('moving forward adjusts for the removed element', () {
      final result = project().reordered(0, 3).clips;
      expect(result.map((c) => c.id), ['b', 'c', 'a']);
    });

    test('no-op when target equals source', () {
      final original = project();
      expect(identical(original.reordered(1, 2), original), isTrue);
    });

    test('keeps total duration unchanged', () {
      final p = project();
      expect(p.reordered(0, 2).totalDuration, p.totalDuration);
    });
  });

  group('withTrim', () {
    test('updates only the targeted clip', () {
      final result = project().withTrim(
        'c',
        trimStart: const Duration(seconds: 1),
        trimEnd: const Duration(seconds: 3),
        minSegment: minSegment,
      );
      expect(result.clips[2].trimStart, const Duration(seconds: 1));
      expect(result.clips[2].trimEnd, const Duration(seconds: 3));
      expect(result.totalDuration, const Duration(seconds: 15));
    });

    test('rejects ranges shorter than the minimum segment', () {
      expect(
        () => project().withTrim(
              'a',
              trimStart: Duration.zero,
              trimEnd: const Duration(milliseconds: 50),
              minSegment: minSegment,
            ),
        throwsA(isA<ClipOperationException>()),
      );
    });

    test('clamps out-of-bounds values to the source duration', () {
      final result = project().withTrim(
        'a',
        trimStart: const Duration(seconds: 4),
        trimEnd: const Duration(hours: 1),
        minSegment: minSegment,
      );
      expect(result.clips[0].trimEnd, const Duration(seconds: 5));
    });
  });

  group('immutability', () {
    test('operations never mutate the original project', () {
      final original = project();
      final snapshotIds = original.clips.map((c) => c.id).toList();

      original.splitClip('b', const Duration(seconds: 4),
          minSegment: minSegment);
      original.removeClip('a');
      original.reordered(0, 2);

      expect(original.clips.map((c) => c.id), snapshotIds);
      expect(original.totalDuration, const Duration(seconds: 17));
    });
  });

  group('speed (effective durations)', () {
    VideoClip sped(String id, int seconds, double speed,
        {int trimStart = 0}) {
      return clip(id, Duration(seconds: seconds), trimStart: Duration(seconds: trimStart))
          .copyWith(speed: speed);
    }

    test('effectiveDuration divides trimmed duration by speed', () {
      expect(
        clip('a', const Duration(seconds: 10)).copyWith(speed: 2.0).effectiveDuration,
        const Duration(seconds: 5),
      );
      expect(
        clip('a', const Duration(seconds: 10)).copyWith(speed: 0.5).effectiveDuration,
        const Duration(seconds: 20),
      );
    });

    test('totalDuration uses output durations across mixed speeds', () {
      final p = VideoProject(name: 'x', clips: [
        sped('a', 5, 1.0), // 5s out
        sped('b', 8, 2.0), // 4s out
        sped('c', 4, 0.5), // 8s out
      ]);
      expect(p.totalDuration, const Duration(seconds: 17));
    });

    test('clipAt resolves across speed-adjusted boundaries in output time',
        () {
      final p = VideoProject(name: 'x', clips: [
        sped('a', 5, 1.0),
        sped('b', 8, 2.0),
        sped('c', 8, 2.0),
      ]);
      // Boundaries: a ends at 5s; b occupies [5s, 9s]; c [9s, 13s].
      final inB = p.clipAt(const Duration(seconds: 7));
      expect(inB.clip.id, 'b');
      expect(inB.localPosition, const Duration(seconds: 2)); // output time

      final inC = p.clipAt(const Duration(seconds: 10));
      expect(inC.clip.id, 'c');
      expect(inC.localPosition, const Duration(seconds: 1));
    });

    test('startOf accumulates output durations', () {
      final p = VideoProject(name: 'x', clips: [
        sped('a', 6, 2.0), // starts 0, spans 3s
        sped('b', 6, 0.5), // starts 3s, spans 12s
      ]);
      expect(p.startOf(p.clips[0]), Duration.zero);
      expect(p.startOf(p.clips[1]), const Duration(seconds: 3));
    });

    test('sourceOffsetFor maps output offsets back to source time', () {
      final p = project();
      final b = p.clips[1]; // source range [2s, 10s], speed 1
      var offset = p.sourceOffsetFor(b, const Duration(seconds: 3));
      expect(offset, const Duration(seconds: 5));

      final fast = sped('f', 8, 2.0); // source [0, 8], output span 4s
      offset = p.sourceOffsetFor(fast, const Duration(seconds: 3));
      expect(offset, const Duration(seconds: 6));

      final slow = sped('s', 8, 0.5); // output span 16s
      offset = p.sourceOffsetFor(slow, const Duration(seconds: 12));
      expect(offset, const Duration(seconds: 6));
    });

    test('sourceOffsetFor accounts for the clip\'s trim start', () {
      final p = project();
      final b = p.clips[1].copyWith(speed: 2.0); // source [2s,10s]
      // Output local 1s → source local 2s → absolute 4s.
      expect(p.sourceOffsetFor(b, const Duration(seconds: 1)),
          const Duration(seconds: 4));
    });
  });

  group('withSpeed', () {
    test('updates only the targeted clip and keeps trims intact', () {
      final result = project().withSpeed('b', 2.0);
      expect(result.clips[1].speed, 2.0);
      expect(result.clips[1].trimStart, const Duration(seconds: 2));
      expect(result.clips[1].trimEnd, const Duration(seconds: 10));
      expect(result.clips[0].speed, 1.0);
      // Output: 5 + 4 + 4 = 13s.
      expect(result.totalDuration, const Duration(seconds: 13));
    });

    test('rejects speeds outside the supported range', () {
      expect(
        () => project().withSpeed('a', 0.1),
        throwsA(isA<ClipOperationException>()),
      );
      expect(
        () => project().withSpeed('a', 5.0),
        throwsA(isA<ClipOperationException>()),
      );
    });

    test('throws for unknown clips', () {
      expect(() => project().withSpeed('zzz', 1.5),
          throwsA(isA<ClipOperationException>()));
    });

    test('split inherits the source clip\'s speed', () {
      final spedUp = project().withSpeed('b', 2.0);
      final parts =
          spedUp.splitClip('b', const Duration(seconds: 4), minSegment: minSegment).clips;
      expect(parts[1].speed, 2.0);
      expect(parts[2].speed, 2.0);
    });
  });

  group('audio tracks', () {
    AudioTrack track({double volume = 1.0, Duration start = Duration.zero}) {
      return AudioTrack(
        id: 'music',
        sourcePath: '/music/song.mp3',
        sourceStart: start,
        sourceEnd: start + const Duration(seconds: 30),
        volume: volume,
      );
    }

    test('project defaults carry no music and full original volume', () {
      final p = project();
      expect(p.audioTracks, isEmpty);
      expect(p.musicTrack, isNull);
      expect(p.originalAudioVolume, 1.0);
    });

    test('upsert inserts then replaces by id', () {
      final p = project().upsertAudioTrack(track(volume: .5));
      expect(p.musicTrack?.volume, .5);

      final replaced = p.upsertAudioTrack(track(volume: .2));
      expect(replaced.audioTracks.length, 1);
      expect(replaced.musicTrack?.volume, .2);
    });

    test('withoutAudioTrack removes the track', () {
      final p = project().upsertAudioTrack(track()).withoutAudioTrack('music');
      expect(p.audioTracks, isEmpty);
    });

    test('withOriginalAudioVolume clamps to the valid range', () {
      final loud = project().withOriginalAudioVolume(3.0);
      expect(loud.originalAudioVolume, 1.0);
      final silent = project().withOriginalAudioVolume(-2.0);
      expect(silent.originalAudioVolume, 0.0);
    });

    test('structural ops preserve audio state', () {
      final withMusic = project().upsertAudioTrack(track());
      final edited = withMusic
          .removeClip('a')
          .reordered(0, 1)
          .withTrim('b',
              trimStart: const Duration(seconds: 3),
              trimEnd: const Duration(seconds: 9),
              minSegment: minSegment);
      expect(edited.musicTrack?.id, 'music');
      expect(edited.originalAudioVolume, 1.0);
    });
  });

  group('text overlays', () {
    TextOverlay overlay(String id,
        {Duration start = Duration.zero,
        Duration end = const Duration(seconds: 3)}) {
      return TextOverlay(
        id: id,
        text: 'Hello $id',
        startTime: start,
        endTime: end,
      );
    }

    test('upsert inserts then replaces by id', () {
      final p = project().upsertTextOverlay(overlay('t1'));
      expect(p.textOverlays.length, 1);

      final edited = p.upsertTextOverlay(
        overlay('t1').copyWith(text: 'Changed'),
      );
      expect(edited.textOverlays.length, 1);
      expect(edited.textOverlays.first.text, 'Changed');
    });

    test('withoutTextOverlay removes by id', () {
      final p = project()
          .upsertTextOverlay(overlay('t1'))
          .upsertTextOverlay(overlay('t2'))
          .withoutTextOverlay('t1');
      expect(p.textOverlays.map((o) => o.id), ['t2']);
    });

    test('rejects inverted time ranges and out-of-bounds positions', () {
      expect(
        () => TextOverlay(
          id: 't',
          text: 'x',
          startTime: const Duration(seconds: 5),
          endTime: const Duration(seconds: 1),
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => overlay('t').copyWith(x: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });

    test('structural ops preserve overlays', () {
      final withText = project().upsertTextOverlay(overlay('t1'));
      final edited = withText.removeClip('c').withSpeed('a', 1.5);
      expect(edited.textOverlays.first.id, 't1');
    });
  });
}
