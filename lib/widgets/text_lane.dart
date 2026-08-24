import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/text_overlay.dart';
import '../state/editor_state.dart';
import 'text_overlay_editor.dart';

/// The TEXT lane under the video track. Blocks are placed on the shared
/// project timeline; tapping one selects it and opens its editor.
class TextLane extends StatelessWidget {
  const TextLane({
    super.key,
    required this.state,
    required this.width,
  });

  final EditorState state;
  final double width;

  @override
  Widget build(BuildContext context) {
    final totalMs = state.totalDuration.inMilliseconds.toDouble();
    final overlays = [...state.project?.textOverlays ?? const <TextOverlay>[]]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .04)),
      ),
      child: totalMs <= 0 || overlays.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'TEXT',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: Colors.white.withValues(alpha: .28),
                  ),
                ),
              ),
            )
          : Stack(
              clipBehavior: Clip.none,
              children: [
                for (final entry in _layoutRows(overlays))
                  Positioned(
                    left: entry.leftFraction.clamp(0.0, 1.0) * width,
                    width: (entry.widthFraction.clamp(0.0, 1.0)) * width,
                    top: entry.row == 0 ? 2 : null,
                    bottom: entry.row == 0 ? null : 2,
                    height: 12,
                    child: _TextBlock(
                      overlay: entry.overlay,
                      selected: entry.overlay.id == state.selectedTextId,
                      onTap: () => _openEditor(context, entry.overlay),
                    ),
                  ),
              ],
            ),
    );
  }

  void _openEditor(BuildContext context, TextOverlay overlay) {
    if (state.exportPhase == ExportPhase.exporting ||
        state.isLoadingProject) {
      return;
    }
    state.selectText(overlay.id);
    showTextOverlayEditor(context, overlay);
  }

  /// Greedy two-row packing so overlapping windows don't fully cover each
  /// other (plan §18 shows stacked examples).
  List<_PlacedOverlay> _layoutRows(List<TextOverlay> overlays) {
    final totalMs = state.totalDuration.inMilliseconds.toDouble();
    final rowEnds = [Duration.zero, Duration.zero];
    final placed = <_PlacedOverlay>[];

    for (final overlay in overlays) {
      var row = rowEnds.indexWhere((end) => end <= overlay.startTime);
      if (row < 0) row = 1; // third overlap shares the bottom row

      final left = overlay.startTime.inMilliseconds / totalMs;
      final widthFraction =
          overlay.duration.inMilliseconds / totalMs;
      placed.add(_PlacedOverlay(
        overlay: overlay,
        row: row,
        leftFraction: left,
        widthFraction: widthFraction,
      ));
      rowEnds[row] = overlay.endTime;
    }
    return placed;
  }
}

class _PlacedOverlay {
  const _PlacedOverlay({
    required this.overlay,
    required this.row,
    required this.leftFraction,
    required this.widthFraction,
  });

  final TextOverlay overlay;
  final int row;
  final double leftFraction;
  final double widthFraction;
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({
    required this.overlay,
    required this.selected,
    required this.onTap,
  });

  final TextOverlay overlay;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: .55)
              : AppTheme.accent.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? Colors.white : AppTheme.accent.withValues(alpha: .8),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          overlay.text == ' ' ? 'Text' : overlay.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 8.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: selected ? 1 : .85),
          ),
        ),
      ),
    );
  }
}

/// Convenience wrapper used by the editor screen so lanes share the
/// provider context without each rebuilding on every tick.
class TextLaneBuilder extends StatelessWidget {
  const TextLaneBuilder({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    return LayoutBuilder(
      builder: (context, constraints) => TextLane(
        state: state,
        width: constraints.maxWidth,
      ),
    );
  }
}
