import 'package:flutter/painting.dart' show TextAlign;
import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/core/utils/ffmpeg_filters.dart';
import 'package:video_editor/models/clip_transition.dart';
import 'package:video_editor/models/text_overlay.dart';
import 'package:video_editor/models/video_adjustments.dart';
import 'package:video_editor/models/video_clip.dart';
import 'package:video_editor/models/video_filter.dart';
import 'package:video_editor/models/video_transform.dart';

void main() {
  group('buildAudioTempoFilter', () {
    test('passes simple in-range speeds through as one stage', () {
      expect(FfmpegFilters.buildAudioTempoFilter(1.5), 'atempo=1.5');
      expect(FfmpegFilters.buildAudioTempoFilter(0.75), 'atempo=0.75');
      expect(FfmpegFilters.buildAudioTempoFilter(2.0), 'atempo=2');
      expect(FfmpegFilters.buildAudioTempoFilter(0.5), 'atempo=0.5');
    });

    test('chains stages for speeds above 2x', () {
      expect(FfmpegFilters.buildAudioTempoFilter(4.0), 'atempo=2,atempo=2');
      expect(
        FfmpegFilters.buildAudioTempoFilter(3.0),
        'atempo=2,atempo=1.5',
      );
    });

    test('chains stages for speeds below 0.5x', () {
      expect(
        FfmpegFilters.buildAudioTempoFilter(0.25),
        'atempo=0.5,atempo=0.5',
      );
    });

    test('handles mixed extremes like 8x and 0.125x', () {
      expect(
        FfmpegFilters.buildAudioTempoFilter(8.0),
        'atempo=2,atempo=2,atempo=2',
      );
      expect(
        FfmpegFilters.buildAudioTempoFilter(0.125),
        'atempo=0.5,atempo=0.5,atempo=0.5',
      );
    });
  });

  group('escapeDrawText', () {
    test('escapes characters meaningful to the filter parser', () {
      expect(FfmpegFilters.escapeDrawText(r'a\b'), r'a\\b');
      expect(FfmpegFilters.escapeDrawText("it's"), r"it\'s");
      expect(FfmpegFilters.escapeDrawText('a:b'), r'a\:b');
      expect(FfmpegFilters.escapeDrawText('100%'), r'100\%');
    });

    test('converts newlines to the drawtext line-break sequence', () {
      expect(FfmpegFilters.escapeDrawText('a\nb'), r'a\nb');
      expect(FfmpegFilters.escapeDrawText('a\r\nb'), r'a\nb');
    });
  });

  group('escapeFilterPath', () {
    test('normalizes separators and escapes drive letters', () {
      expect(
        FfmpegFilters.escapeFilterPath(r'C:\data\clip.mp4'),
        r'C\:/data/clip.mp4',
      );
      expect(
        FfmpegFilters.escapeFilterPath('/data/clip.mp4'),
        '/data/clip.mp4',
      );
    });
  });

  group('buildDrawTextFilter', () {
    TextOverlay overlay({
      TextAlign alignment = TextAlign.center,
      bool background = true,
      double x = 0.5,
    }) {
      return TextOverlay(
        id: 't',
        text: "Hi 'there'",
        startTime: const Duration(seconds: 1),
        endTime: const Duration(seconds: 4),
        fontSize: 0.1,
        x: x,
        alignment: alignment,
        background: background,
      );
    }

    test('embeds font, size, timing and escaped text', () {
      final filter = FfmpegFilters.buildDrawTextFilter(
        overlay(),
        canvasWidth: 1920,
        canvasHeight: 1080,
        fontFilePath: '/fonts/Roboto-Regular.ttf',
      );

      expect(filter, startsWith("drawtext=fontfile='/fonts/Roboto-Regular.ttf'"));
      expect(filter, contains(r"text='Hi \'there\''"));
      expect(filter, contains('fontsize=108'));
      // Centered anchor: x = 0.5*w - tw*0.5.
      expect(filter, contains('x=0.500000*w-(tw*0.500000)'));
      expect(filter, contains('y=0.500000*h-(th*0.500000)'));
      expect(filter, contains("enable='between(1.000,4.000)'"));
      expect(filter, contains('box=1'));
    });

    test('left alignment anchors without a text-extent shift', () {
      final filter = FfmpegFilters.buildDrawTextFilter(
        overlay(alignment: TextAlign.left),
        canvasWidth: 1000,
        canvasHeight: 500,
        fontFilePath: '/f.ttf',
      );
      expect(filter, contains('x=0.500000*w'));
    });

    test('background can be disabled', () {
      final filter = FfmpegFilters.buildDrawTextFilter(
        overlay(background: false),
        canvasWidth: 1000,
        canvasHeight: 500,
        fontFilePath: '/f.ttf',
      );
      expect(filter.contains('box=1'), isFalse);
    });
  });

  group('buildVideoFilterChain (Phase 4)', () {
    VideoClip clipWith({
      CropSettings? crop,
      TransformSettings? transform,
      VideoFilter filter = VideoFilter.none,
      VideoAdjustments adjustments = VideoAdjustments.neutral,
    }) {
      return VideoClip(
        id: 'x',
        sourcePath: '/s.mp4',
        sourceDuration: const Duration(seconds: 5),
        transform: VideoTransform(
          crop: crop ?? CropSettings.full,
          transform: transform ?? TransformSettings.identity,
        ),
        filter: filter,
        adjustments: adjustments,
      );
    }

    test('returns null for a visually untouched clip', () {
      final chain = FfmpegFilters.buildVideoFilterChain(
        clipWith(),
        sourceWidth: 1920,
        sourceHeight: 1080,
      );
      expect(chain, isNull);
    });

    test('crop resolves fractions to even pixel geometry', () {
      final chain = FfmpegFilters.buildVideoFilterChain(
        clipWith(crop: const CropSettings(left: 0.25, top: 0, right: 0.75, bottom: 1)),
        sourceWidth: 1920,
        sourceHeight: 1080,
      );
      // w = 1920*0.5 = 960, x = (1920−960)*0.25/0.5 = 480.
      expect(chain, 'crop=960:1080:480:0');
    });

    test('rotation maps to transpose stages', () {
      String? chainOf(Rotation r) =>
          FfmpegFilters.buildVideoFilterChain(
            clipWith(transform: TransformSettings(rotation: r)),
            sourceWidth: 1000,
            sourceHeight: 500,
          );

      expect(chainOf(Rotation.clockwise90), 'transpose=1');
      expect(chainOf(Rotation.clockwise180), 'transpose=1,transpose=1');
      expect(chainOf(Rotation.clockwise270), 'transpose=2');
    });

    test('flips and presets append in canonical order', () {
      final chain = FfmpegFilters.buildVideoFilterChain(
        clipWith(
          transform: const TransformSettings(
            rotation: Rotation.clockwise90,
            flipHorizontal: true,
            flipVertical: true,
          ),
          filter: VideoFilter.warm,
        ),
        sourceWidth: 1000,
        sourceHeight: 500,
      );
      expect(chain, 'transpose=1,hflip,vflip,colorbalance=rs=0.15:gs=0.03:bs=-0.12');
    });

    test('adjustments map onto eq/colorbalance ranges', () {
      final chain = FfmpegFilters.buildVideoFilterChain(
        clipWith(
          adjustments: const VideoAdjustments(
            brightness: 50,
            contrast: -20,
            saturation: 40,
            temperature: 30,
          ),
        ),
        sourceWidth: 1000,
        sourceHeight: 500,
      );
      // brightness .15, contrast .9, saturation 1.4 → eq; temp +30/200=.15.
      expect(
        chain,
        'eq=brightness=0.15:contrast=0.9:saturation=1.4,colorbalance=rs=0.15:bs=-0.15',
      );
    });

    test('neutral adjustments emit nothing', () {
      final chain = FfmpegFilters.buildVideoFilterChain(
        clipWith(filter: VideoFilter.grayscale),
        sourceWidth: 1000,
        sourceHeight: 500,
      );
      expect(chain, 'hue=s=0');
    });
  });

  group('xfade / acrossfade graphs (Phase 4)', () {
    test('names map to xfade transition identifiers', () {
      expect(FfmpegFilters.xfadeName(TransitionType.fade), 'fade');
      expect(FfmpegFilters.xfadeName(TransitionType.black), 'fadeblack');
      expect(FfmpegFilters.xfadeName(TransitionType.white), 'fadewhite');
      expect(FfmpegFilters.xfadeName(TransitionType.slideLeft), 'slideleft');
      expect(FfmpegFilters.xfadeName(TransitionType.zoom), 'zoomin');
      expect(() => FfmpegFilters.xfadeName(TransitionType.none), throwsArgumentError);
    });

    test('video graph chains offsets cumulatively minus overlaps', () {
      // Segments 5s, 8s, 4s with overlaps 2s and 2s:
      // offset1 = 5−2 = 3; offset2 = 3+8−2 = 9.
      final graph = FfmpegFilters.buildXfadeVideoGraph(
        outputDurations: [
          const Duration(seconds: 5),
          const Duration(seconds: 8),
          const Duration(seconds: 4),
        ],
        types: [TransitionType.fade, TransitionType.dissolve],
        overlaps: [
          const Duration(seconds: 2),
          const Duration(seconds: 2),
        ],
        finalLabel: 'vout',
      );
      expect(
        graph,
        '[0:v][1:v]xfade=transition=fade:duration=2.000:offset=3.000[vx1];'
        '[vx1][2:v]xfade=transition=dissolve:duration=2.000:offset=9.000[vout]',
      );
    });

    test('mixed graphs interleave xfade and concat per boundary', () {
      // Boundary 0 transitions (2s overlap), boundary 1 is a hard cut.
      // offset0 = 5−2 = 3; concat join adds 4s → net total 15s.
      final graph = FfmpegFilters.buildAssemblyFilterComplex(
        outputDurations: [
          const Duration(seconds: 5),
          const Duration(seconds: 8),
          const Duration(seconds: 4),
        ],
        types: [TransitionType.fade, TransitionType.none],
        overlaps: [
          const Duration(seconds: 2),
          Duration.zero,
        ],
        videoLabel: 'vout',
        audioLabel: 'aout',
      );
      expect(
        graph,
        '[0:v][1:v]xfade=transition=fade:duration=2.000:offset=3.000[vc1];'
        '[vc1][2:v]concat=n=2:v=1:a=0[vout];'
        '[0:a][1:a]acrossfade=d=2.000[ac1];'
        '[ac1][2:a]concat=n=2:v=0:a=1[aout]',
      );
    });

    test('audio graph mirrors the same overlaps', () {
      final graph = FfmpegFilters.buildAcrossfadeAudioGraph(
        outputDurations: [
          const Duration(seconds: 5),
          const Duration(seconds: 4),
        ],
        overlaps: [const Duration(seconds: 2)],
        finalLabel: 'aout',
      );
      expect(graph, '[0:a][1:a]acrossfade=d=2.000[aout]');
    });
  });

  group('preview color matrices (Phase 4)', () {
    List<double> apply(List<double> m, double r, double g, double b) {
      double ch(int row) => (m[row * 5] * r + m[row * 5 + 1] * g +
              m[row * 5 + 2] * b + m[row * 5 + 4])
          .clamp(0.0, 1.0);
      return [ch(0), ch(1), ch(2)];
    }

    test('identity look leaves colors untouched', () {
      final m = FfmpegFilters.previewColorMatrix(
        VideoFilter.none,
        VideoAdjustments.neutral,
      );
      final out = apply(m, 0.5, 0.25, 1.0);
      expect(out[0], closeTo(0.5, 1e-9));
      expect(out[1], closeTo(0.25, 1e-9));
      expect(out[2], closeTo(1.0, 1e-9));
    });

    test('grayscale equalizes channels to luma', () {
      final m = FfmpegFilters.previewColorMatrix(
        VideoFilter.grayscale,
        VideoAdjustments.neutral,
      );
      final out = apply(m, 0.2, 0.4, 0.6);
      final luma = 0.2126 * 0.2 + 0.7152 * 0.4 + 0.0722 * 0.6;
      for (final c in out) {
        expect(c, closeTo(luma, 1e-6));
      }
    });

    test('brightness adjustment lifts all channels', () {
      final m = FfmpegFilters.previewColorMatrix(
        VideoFilter.none,
        const VideoAdjustments(brightness: 50),
      );
      final out = apply(m, 0.5, 0.5, 0.5);
      // 50/100*0.25 = +0.125.
      for (final c in out) {
        expect(c, closeTo(0.625, 1e-6));
      }
    });

    test('composition applies preset then adjustments', () {
      // Grayscale followed by brightness lift stays gray but brighter.
      final m = FfmpegFilters.previewColorMatrix(
        VideoFilter.grayscale,
        const VideoAdjustments(brightness: 20),
      );
      final out = apply(m, 0.2, 0.4, 0.6);
      final luma = 0.2126 * 0.2 + 0.7152 * 0.4 + 0.0722 * 0.6;
      for (final c in out) {
        expect(c, closeTo(luma + 0.05, 1e-6));
      }
    });
  });
}
