import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../models/video_clip.dart';

/// One clip's block on the multi-clip timeline: a filmstrip sliced to the
/// clip's trim range, plus selection visuals, index badge and duration.
///
/// Purely presentational — all gestures live in the parent timeline so
/// scrubbing, trimming and drag-reorder share one coherent gesture setup.
class TimelineClipBlock extends StatelessWidget {
  const TimelineClipBlock({
    super.key,
    required this.clip,
    required this.index,
    required this.selected,
    required this.thumbnails,
    required this.dragging,
  });

  final VideoClip clip;

  /// Zero-based position within the project; shown as "1", "2", …
  final int index;

  final bool selected;

  /// Filmstrip paths covering the clip's WHOLE source video evenly.
  final List<String> thumbnails;

  /// Whether this block is being drag-reordered right now.
  final bool dragging;

  static const double _badgeHeight = 18;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dragging ? .35 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.accent : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppTheme.surfaceRaised,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Column(
              children: [
                Expanded(child: _FilmstripSlice(clip: clip, paths: thumbnails)),
                _Badge(index: index, duration: clip.trimmedDuration),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.index, required this.duration});

  final int index;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: TimelineClipBlock._badgeHeight,
      width: double.infinity,
      color: Colors.black.withValues(alpha: .55),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: .85),
            ),
          ),
          const Spacer(),
          Text(
            formatClock(duration),
            style: TextStyle(
              fontSize: 9,
              color: Colors.white.withValues(alpha: .85),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders only the frames whose source-time coverage intersects the clip's
/// `[trimStart, trimEnd)` window, sizing each tile proportionally to its
/// overlap so trims visibly slide the filmstrip.
class _FilmstripSlice extends StatelessWidget {
  const _FilmstripSlice({required this.clip, required this.paths});

  final VideoClip clip;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return const ColoredBox(color: AppTheme.surfaceRaised);
    }

    final count = paths.length;
    final interval =
        clip.sourceDuration.inMilliseconds.toDouble() / count;
    if (interval <= 0) {
      return const ColoredBox(color: AppTheme.surfaceRaised);
    }

    final windowMs = clip.trimmedDuration.inMilliseconds.toDouble();
    final firstIndex = (clip.trimStart.inMilliseconds / interval).floor();
    final lastIndex = (clip.trimEnd.inMilliseconds / interval).ceil();

    final tiles = <Widget>[];
    for (var i = firstIndex; i < lastIndex; i++) {
      final frameStart = i * interval;
      final frameEnd = frameStart + interval;

      final overlapStart = frameStart > clip.trimStart.inMilliseconds
          ? frameStart
          : clip.trimStart.inMilliseconds.toDouble();
      final overlapEnd = frameEnd < clip.trimEnd.inMilliseconds
          ? frameEnd
          : clip.trimEnd.inMilliseconds.toDouble();
      var fraction = (overlapEnd - overlapStart) / windowMs;
      if (fraction <= 0) continue;
      if (fraction > 1) fraction = 1;

      tiles.add(
        Expanded(
          flex: (fraction * 1000).round().clamp(1, 1000),
          child: Image.file(
            File(paths[i.clamp(0, count - 1)]),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }

    if (tiles.isEmpty) {
      // Degenerate windows still deserve a frame rather than a void.
      final nearest = ((clip.trimStart.inMilliseconds / interval).floor())
          .clamp(0, count - 1);
      return Image.file(
        File(paths[nearest]),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: tiles,
    );
  }
}
