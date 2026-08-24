import 'dart:typed_data';

import 'package:flutter/painting.dart' show TextAlign;

import '../../models/clip_transition.dart' show TransitionType;
import '../../models/text_overlay.dart';
import '../../models/video_adjustments.dart';
import '../../models/video_clip.dart';
import '../../models/video_filter.dart';
import '../../models/video_transform.dart';
import 'time_utils.dart';

/// Pure FFmpeg filter-string builders shared by preview-independent logic.
///
/// Keeping these free of plugin imports lets them be unit-tested directly
/// and reused wherever a filter graph fragment is needed.
abstract final class FfmpegFilters {
  /// Builds an `atempo` filter chain for [speed].
  ///
  /// A single `atempo` instance only accepts 0.5–2.0, so values outside
  /// that range are decomposed into chained stages, e.g. 4.0 becomes
  /// `atempo=2.0,atempo=2.0` and 0.25 becomes `atempo=0.5,atempo=0.5`.
  static String buildAudioTempoFilter(double speed) {
    var remaining = speed;
    final stages = <double>[];
    while (remaining > 2.0 + 1e-9) {
      stages.add(2.0);
      remaining /= 2.0;
    }
    while (remaining < 0.5 - 1e-9) {
      stages.add(0.5);
      remaining *= 2.0;
    }
    stages.add(remaining);

    // Trim trailing zeros: 2.0 → "2", 1.25 → "1.25".
    String fmt(double v) {
      var s = v.toStringAsFixed(6);
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
      return s;
    }

    return stages.map((s) => 'atempo=${fmt(s)}').join(',');
  }

  /// Escapes [text] for safe embedding inside a single-quoted `drawtext`
  /// text parameter. Order matters: backslashes first, then quotes, then
  /// characters meaningful to the filter parser (`:` `%`), then newlines
  /// become drawtext's escaped `\n` sequence.
  static String escapeDrawText(String text) {
    return text
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(':', r'\:')
        .replaceAll('%', r'\%')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\n');
  }

  /// Normalizes a filesystem path for use inside a filter argument:
  /// forward slashes only (accepted on every platform) and colons escaped
  /// so Windows drive letters survive filter parsing.
  static String escapeFilterPath(String path) =>
      path.replaceAll('\\', '/').replaceAll(':', r'\:');

  /// Builds one `drawtext=…` filter for [overlay] against a canvas of
  /// [canvasWidth]×[canvasHeight]. The result contains single-quoted
  /// sections and must not be wrapped in further quotes per-argument;
  /// callers join multiple overlays with commas.
  static String buildDrawTextFilter(
    TextOverlay overlay, {
    required int canvasWidth,
    required int canvasHeight,
    required String fontFilePath,
  }) {
    final fontsize = (canvasHeight * overlay.fontSize).round().clamp(8, 10000);
    final text = escapeDrawText(overlay.text);

    // Alignment shifts the anchor so x/y describes the block's visual
    // position, not its left/top corner.
    final ax = switch (overlay.alignment) {
      TextAlign.left => 0.0,
      TextAlign.right => 1.0,
      _ => 0.5,
    };
    final ay = 0.5; // vertical centering relative to the anchor

    final xExpr = _anchorExpr('w', 'tw', overlay.x, ax);
    final yExpr = _anchorExpr('h', 'th', overlay.y, ay);

    final buffer = StringBuffer('drawtext=')
      ..write("fontfile='${escapeFilterPath(fontFilePath)}'")
      ..write(":text='$text'")
      ..write(':fontcolor=0x${overlay.color.hex}')
      ..write(':fontsize=$fontsize')
      ..write(':x=$xExpr')
      ..write(':y=$yExpr')
      // Visibility window in output seconds — the concatenated export runs
      // on the project timeline, so overlay times apply directly.
      ..write(
        ":enable='between(${formatSeconds(overlay.startTime)},"
        "${formatSeconds(overlay.endTime)})'",
      );

    if (overlay.background) {
      final border = (canvasHeight * 0.012).round().clamp(4, 64);
      buffer.write(":box=1:boxcolor=0x000000@0.45:boxborderw=$border");
    }

    return buffer.toString();
  }

  /// `normalized * dimension - textDimension * anchor`, letting FFmpeg
  /// resolve the text extents at draw time.
  static String _anchorExpr(
    String dim,
    String textDim,
    double normalized,
    double anchor,
  ) {
    final n = normalized.toStringAsFixed(6);
    if (anchor.abs() < 1e-9) {
      return '$n*$dim';
    }
    final a = anchor.toStringAsFixed(6);
    return '$n*$dim-($textDim*$a)';
  }

  // ---------------------------------------------------------------------------
  // Phase 4: per-clip visual chains
  //
  // Canonical order shared with the Flutter preview (plan §29 parity):
  //   CROP → ROTATE → FLIP → COLOR(preset → adjustments)
  // The preview must apply the same sequence or the two will diverge.
  // ---------------------------------------------------------------------------

  /// Builds the `vf` fragment for one clip, or null when the clip is
  /// visually untouched (no filter argument needed).
  ///
  /// [sourceWidth]/[sourceHeight] are the PROBED dimensions of the source
  /// video; crop fractions resolve to even pixel sizes against them.
  static String? buildVideoFilterChain(
    VideoClip clip, {
    required int sourceWidth,
    required int sourceHeight,
  }) {
    final parts = <String>[];

    final crop = clip.transform.crop;
    if (!crop.isIdentity) {
      parts.add(_cropPart(crop, sourceWidth, sourceHeight));
    }

    final rotation = clip.transform.transform.rotation;
    if (rotation.quarterTurns != 0) {
      parts.addAll(_transposeParts(rotation));
    }

    if (clip.transform.transform.flipHorizontal) {
      parts.add('hflip');
    }
    if (clip.transform.transform.flipVertical) {
      parts.add('vflip');
    }

    final preset = _presetColorParts(clip.filter);
    if (preset != null) {
      parts.add(preset);
    }

    final adjust = _adjustmentParts(clip.adjustments);
    if (adjust != null) {
      parts.add(adjust);
    }

    return parts.isEmpty ? null : parts.join(',');
  }

  /// `crop=w:h:x:y` with even output size and clamped offsets.
  static String _cropPart(
    CropSettings crop,
    int sourceWidth,
    int sourceHeight,
  ) {
    final w = _even(sourceWidth * crop.widthFraction);
    final h = _even(sourceHeight * crop.heightFraction);
    // When an axis keeps its full size there is no room to pan — offset 0
    // (the general formula would divide by zero).
    final x = crop.widthFraction < 1 - 1e-9
        ? _even((sourceWidth - w) * crop.left / (1 - crop.widthFraction))
        : 0;
    final y = crop.heightFraction < 1 - 1e-9
        ? _even((sourceHeight - h) * crop.top / (1 - crop.heightFraction))
        : 0;
    return 'crop=$w:$h:$x:$y';
  }

  /// Rotation as `transpose` stages. transpose=1 is 90° CW; 180° uses a
  /// double application; 270° uses the CCW variant.
  static List<String> _transposeParts(Rotation rotation) => switch (
        rotation.quarterTurns % 4
      ) {
        1 => const ['transpose=1'],
        2 => const ['transpose=1', 'transpose=1'],
        3 => const ['transpose=2'],
        _ => const [],
      };

  /// FFmpeg fragment for a look preset, or null for [VideoFilter.none].
  static String? _presetColorParts(VideoFilter filter) => switch (filter) {
        VideoFilter.none => null,
        VideoFilter.grayscale => 'hue=s=0',
        VideoFilter.warm => 'colorbalance=rs=0.15:gs=0.03:bs=-0.12',
        VideoFilter.cool => 'colorbalance=rs=-0.10:bs=0.18',
        VideoFilter.vintage => 'curves=preset=vintage',
        VideoFilter.highContrast => 'eq=contrast=1.35:saturation=1.05',
        VideoFilter.bright => 'eq=brightness=0.18:saturation=1.08',
        VideoFilter.fade => 'eq=saturation=0.60:contrast=0.85:brightness=0.06',
      };

  /// User-range adjustments (−100..100) mapped onto FFmpeg's scales:
  /// brightness ±0.30, contrast 0.5..1.5, saturation 0..2, temperature via
  /// opposing red/blue shifts in colorbalance.
  static String? _adjustmentParts(VideoAdjustments adj) {
    if (adj.isNeutral) return null;

    final eqTerms = <String>[];
    if (adj.brightness != 0) {
      eqTerms.add('brightness=${_num(adj.brightness / 100 * 0.30)}');
    }
    if (adj.contrast != 0) {
      eqTerms.add('contrast=${_num(1 + adj.contrast / 100 * 0.5)}');
    }
    if (adj.saturation != 0) {
      eqTerms.add('saturation=${_num(1 + adj.saturation / 100)}');
    }

    final parts = <String>[];
    if (eqTerms.isNotEmpty) {
      parts.add('eq=${eqTerms.join(':')}');
    }
    if (adj.temperature != 0) {
      final t = adj.temperature / 200;
      parts.add(
        'colorbalance=rs=${_num(t)}:bs=${_num(-t)}',
      );
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  static int _even(double pixels) {
    final v = pixels.round().clamp(2, 1 << 20);
    return v.isEven ? v : v - 1;
  }

  /// Trims trailing zeros: "0.300000" → "0.3", "1.000000" → "1".
  static String _num(double v) {
    var s = v.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  // ---------------------------------------------------------------------------
  // Phase 4: transition assembly graphs
  // ---------------------------------------------------------------------------

  /// Maps [TransitionType] values onto xfade's transition names.
  static String xfadeName(TransitionType type) => switch (type) {
        TransitionType.fade => 'fade',
        TransitionType.dissolve => 'dissolve',
        TransitionType.black => 'fadeblack',
        TransitionType.white => 'fadewhite',
        TransitionType.slideLeft => 'slideleft',
        TransitionType.slideRight => 'slideright',
        TransitionType.zoom => 'zoomin',
        TransitionType.none => throw ArgumentError(
            'none transitions must be joined by concat instead'),
      };

  /// Builds the video side of an overlap assembly: chained `xfade` filters.
  ///
  /// [types] and [overlaps] describe the boundaries BETWEEN consecutive
  /// segments (length n−1); every entry must be active — hard-cut
  /// boundaries are handled by the concat fallback in the export service.
  /// Returns the chain ending in label [finalLabel]; input labels follow
  /// FFmpeg's `[i:v]` convention.
  static String buildXfadeVideoGraph({
    required List<Duration> outputDurations,
    required List<TransitionType> types,
    required List<Duration> overlaps,
    required String finalLabel,
  }) {
    assert(outputDurations.length == types.length + 1);
    assert(overlaps.length == types.length);

    final buffer = StringBuffer();
    final offsets = _chainOffsets(outputDurations, overlaps);
    var acc = '0:v';

    for (var i = 0; i < types.length; i++) {
      final out = i + 1 < types.length ? 'vx${i + 1}' : finalLabel;
      buffer.write(
        '[$acc][${i + 1}:v]'
        'xfade=transition=${xfadeName(types[i])}'
        ':duration=${formatSeconds(overlaps[i])}'
        ':offset=${formatSeconds(offsets[i])}'
        '[$out]',
      );
      if (i + 1 < types.length) buffer.write(';');
      acc = out;
    }
    return buffer.toString();
  }

  /// Audio mirror of [buildXfadeVideoGraph]: chained `acrossfade` filters
  /// using the SAME overlaps so sound and picture crossfade in lockstep.
  static String buildAcrossfadeAudioGraph({
    required List<Duration> outputDurations,
    required List<Duration> overlaps,
    required String finalLabel,
  }) {
    assert(outputDurations.length == overlaps.length + 1);

    final buffer = StringBuffer();
    var acc = '0:a';

    for (var i = 0; i < overlaps.length; i++) {
      final out = i + 1 < overlaps.length ? 'ax${i + 1}' : finalLabel;
      buffer.write(
        '[$acc][${i + 1}:a]'
        'acrossfade=d=${formatSeconds(overlaps[i])}'
        '[$out]',
      );
      if (i + 1 < overlaps.length) buffer.write(';');
      acc = out;
    }
    return buffer.toString();
  }

  /// Cumulative xfades offsets for a PURE transition chain: the position
  /// inside the accumulated stream where the next segment must begin.
  /// Shared by the simple and generalized graph builders so both agree.
  static List<Duration> _chainOffsets(
    List<Duration> outputDurations,
    List<Duration> overlaps,
  ) {
    final offsets = <Duration>[];
    var accDur = outputDurations.first;
    for (var i = 0; i < overlaps.length; i++) {
      offsets.add(accDur - overlaps[i]);
      accDur += outputDurations[i + 1] - overlaps[i];
    }
    return offsets;
  }

  /// Builds ONE `filter_complex` joining every pair of adjacent segments
  /// with the right primitive: an `xfade`+`acrossfade` pair where an active
  /// transition sits, a `concat` pair where the seam is a hard cut.
  ///
  /// Mixed graphs (some seams transitioning, some cutting) are the common
  /// case, so this — not the pure helpers above — drives exports.
  ///
  /// Offsets always refer to the ACCUMULATED stream's own timeline, tracked
  /// through concat joins too (concat emits sequential timestamps).
  static String buildAssemblyFilterComplex({
    required List<Duration> outputDurations,
    required List<TransitionType> types,
    required List<Duration> overlaps,
    required String videoLabel,
    required String audioLabel,
  }) {
    assert(outputDurations.length == types.length + 1);
    assert(overlaps.length == types.length);

    final video = StringBuffer();
    final audio = StringBuffer();
    var vAcc = '0:v';
    var aAcc = '0:a';
    var accDur = outputDurations.first;

    for (var i = 0; i < types.length; i++) {
      final last = i == types.length - 1;
      final vOut = last ? videoLabel : 'vc${i + 1}';
      final aOut = last ? audioLabel : 'ac${i + 1}';
      final active =
          types[i] != TransitionType.none && overlaps[i] > Duration.zero;

      if (active) {
        final offset = accDur - overlaps[i];
        video.write(
          '[$vAcc][${i + 1}:v]'
          'xfade=transition=${xfadeName(types[i])}'
          ':duration=${formatSeconds(overlaps[i])}'
          ':offset=${formatSeconds(offset)}'
          '[$vOut]',
        );
        audio.write(
          '[$aAcc][${i + 1}:a]'
          'acrossfade=d=${formatSeconds(overlaps[i])}'
          '[$aOut]',
        );
        accDur += outputDurations[i + 1] - overlaps[i];
      } else {
        video.write(
          '[$vAcc][${i + 1}:v]concat=n=2:v=1:a=0[$vOut]',
        );
        audio.write(
          '[$aAcc][${i + 1}:a]concat=n=2:v=0:a=1[$aOut]',
        );
        accDur += outputDurations[i + 1];
      }

      vAcc = vOut;
      aAcc = aOut;
      if (!last) video.write(';');
      if (!last) audio.write(';');
    }

    return '$video;$audio';
  }

  // ---------------------------------------------------------------------------
  // Phase 4: preview color matrices
  //
  // Single authority for visual LOOK: export translates presets/adjustments
  // into FFmpeg filters above, while the Flutter preview composes these
  // ColorFilter matrices from the same inputs. Tiny deviations are accepted
  // (plan §29) but both sides derive from this one mapping.
  // ---------------------------------------------------------------------------

  /// Composed 4×5 matrix (20 entries) for the given clip look, ready for
  /// `ColorFilter.matrix`.
  static Float64List previewColorMatrix(
    VideoFilter filter,
    VideoAdjustments adjustments,
  ) {
    var m = _identityMatrix();
    m = _multiplyMatrices(m, _presetMatrix(filter));
    m = _multiplyMatrices(m, _adjustmentMatrix(adjustments));
    return Float64List.fromList(m);
  }

  static List<double> _identityMatrix() => <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _presetMatrix(VideoFilter filter) => switch (filter) {
        VideoFilter.none => _identityMatrix(),
        VideoFilter.grayscale => <double>[
          .2126, .7152, .0722, 0, 0, //
          .2126, .7152, .0722, 0, 0, //
          .2126, .7152, .0722, 0, 0, //
          0, 0, 0, 1, 0, //
        ],
        VideoFilter.warm => <double>[
          1.08, 0, 0, 0, 0.02, //
          0, 1.00, 0, 0, 0.01, //
          0, 0, 0.90, 0, 0, //
          0, 0, 0, 1, 0, //
        ],
        VideoFilter.cool => <double>[
          0.92, 0, 0, 0, 0, //
          0, 0.98, 0, 0, 0.01, //
          0, 0, 1.10, 0, 0.03, //
          0, 0, 0, 1, 0, //
        ],
        VideoFilter.vintage => <double>[
          .68, .28, .04, 0, 0.04, //
          .24, .64, .12, 0, 0.02, //
          .14, .32, .50, 0, 0.04, //
          0, 0, 0, 1, 0, //
        ],
        VideoFilter.highContrast => _scaleAroundMidpoint(1.3),
        VideoFilter.bright => _offsetAll(0.10),
        VideoFilter.fade => _fadeMatrix(),
      };

  static List<double> _scaleAroundMidpoint(double factor) => <double>[
        factor, 0, 0, 0, 0.5 * (1 - factor), //
        0, factor, 0, 0, 0.5 * (1 - factor), //
        0, 0, factor, 0, 0.5 * (1 - factor), //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _offsetAll(double offset) => <double>[
        1, 0, 0, 0, offset, //
        0, 1, 0, 0, offset, //
        0, 0, 1, 0, offset, //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _fadeMatrix() {
    // Lift blacks and desaturate ~35% toward luma.
    const luma = [.2126, .7152, .0722];
    const sat = 0.65;
    const lift = 0.09;
    return <double>[
      for (final row in [0, 1, 2]) ...[
        luma[row] * (1 - sat) + (row == 0 ? sat : 0),
        luma[row] * (1 - sat) + (row == 1 ? sat : 0),
        luma[row] * (1 - sat) + (row == 2 ? sat : 0),
        0,
        lift,
      ],
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _adjustmentMatrix(VideoAdjustments adj) {
    if (adj.isNeutral) return _identityMatrix();

    var m = _identityMatrix();

    if (adj.brightness != 0) {
      m = _multiplyMatrices(m, _offsetAll(adj.brightness / 100 * 0.25));
    }

    if (adj.contrast != 0) {
      final f = 1 + adj.contrast / 150;
      m = _multiplyMatrices(m, _scaleAroundMidpoint(f));
    }

    if (adj.saturation != 0) {
      final s = 1 + adj.saturation / 100;
      const luma = [.2126, .7152, .0722];
      // out = luma*(1−s) + channel*s:
      m = _multiplyMatrices(
        m,
        <double>[
          for (final row in [0, 1, 2]) ...[
            luma[0] * (1 - s) + (row == 0 ? s : 0),
            luma[1] * (1 - s) + (row == 1 ? s : 0),
            luma[2] * (1 - s) + (row == 2 ? s : 0),
            0,
            0,
          ],
          0, 0, 0, 1, 0,
        ],
      );
    }

    if (adj.temperature != 0) {
      final t = adj.temperature / 100;
      m = _multiplyMatrices(
        m,
        <double>[
          1 + t * 0.08, 0, 0, 0, t * 0.02, //
          0, 1, 0, 0, 0, //
          0, 0, 1 - t * 0.08, 0, -t * 0.02, //
          0, 0, 0, 1, 0, //
        ],
      );
    }

    return m;
  }

  /// Multiplies two 4×5 color matrices (the standard ColorFilter layout:
  /// 5 columns, last row unused beyond alpha passthrough).
  static List<double> _multiplyMatrices(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[r * 5 + k] * b[k * 5 + c];
        }
        if (c == 4) sum += a[r * 5 + 4];
        out[r * 5 + c] = sum;
      }
    }
    return out;
  }
}
