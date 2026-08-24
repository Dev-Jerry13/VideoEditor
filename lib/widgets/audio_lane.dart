import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../state/editor_state.dart';
import 'music_editor.dart';

/// The AUDIO lane under the video and text tracks. Shows the music block
/// spanning its timeline window, or an empty hint when no track is set.
/// Tapping anywhere opens the music sheet.
class AudioLane extends StatelessWidget {
  const AudioLane({
    super.key,
    required this.state,
    required this.width,
  });

  final EditorState state;
  final double width;

  bool get _busy =>
      state.isLoadingProject || state.exportPhase == ExportPhase.exporting;

  @override
  Widget build(BuildContext context) {
    final totalMs = state.totalDuration.inMilliseconds.toDouble();
    final track = state.project?.musicTrack;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : () => showMusicSheet(context),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceRaised.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .04)),
        ),
        padding: const EdgeInsets.all(2),
        child: track == null || totalMs <= 0
            ? Row(
                children: [
                  const SizedBox(width: 8),
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: .35),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'AUDIO · tap to add music',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      color: Colors.white.withValues(alpha: .32),
                    ),
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final available = state.totalDuration - track.timelineStart;
                  final windowDuration =
                      track.sourceDuration > available && !available.isNegative
                          ? available
                          : track.sourceDuration;
                  final leftFraction =
                      (track.timelineStart.inMilliseconds / totalMs)
                          .clamp(0.0, 1.0);
                  final widthFraction =
                      (windowDuration.inMilliseconds / totalMs)
                          .clamp(0.02, 1.0);

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: leftFraction * constraints.maxWidth,
                        width: widthFraction * constraints.maxWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: .28),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.accent.withValues(alpha: .8),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.music_note_rounded,
                                  size: 11, color: Colors.white),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${track.name} · '
                                  '${(track.volume * 100).round()}%',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    height: 1,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Colors.white.withValues(alpha: .9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
