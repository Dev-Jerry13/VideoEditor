import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../state/editor_state.dart';
import 'adjustment_panel.dart';
import 'crop_editor.dart';
import 'filter_selector.dart';
import 'music_editor.dart';
import 'speed_selector.dart';
import 'text_overlay_editor.dart';
import 'transform_controls.dart';
import 'transition_selector.dart';
import 'volume_editor.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final busy = state.exportPhase == ExportPhase.exporting ||
        state.isLoadingProject;
    final hasProject = state.hasProject;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              _ToolButton(
                icon: Icons.content_cut_rounded,
                label: 'Trim',
                enabled: hasProject && !busy,
                onTap: () => _showTrimDialog(context),
              ),
              // Split validity depends on the live playhead, so it listens
              // to the position notifier without rebuilding the toolbar.
              ValueListenableBuilder<Duration>(
                valueListenable: state.playbackPosition,
                builder: (context, position, _) => _ToolButton(
                  icon: Icons.call_split_rounded,
                  label: 'Split',
                  enabled:
                      hasProject && !busy && state.canSplitAt(position),
                  onTap: () {
                    context.read<EditorState>().splitAtPlayhead();
                    _surfaceActionError(context);
                  },
                ),
              ),
              _ToolButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                enabled: hasProject && !busy && state.clips.length > 1,
                onTap: () {
                  context.read<EditorState>().deleteSelectedClip();
                  _surfaceActionError(context);
                },
              ),
              _ToolButton(
                icon: Icons.add_circle_outline_rounded,
                label: 'Add',
                enabled: hasProject && !busy,
                onTap: () async {
                  await context.read<EditorState>().addVideoToTimeline();
                  if (context.mounted) _surfaceActionError(context);
                },
              ),
              _ToolButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                enabled: hasProject && !busy && state.canUndo,
                onTap: () => context.read<EditorState>().undo(),
              ),
              _ToolButton(
                icon: Icons.redo_rounded,
                label: 'Redo',
                enabled: hasProject && !busy && state.canRedo,
                onTap: () => context.read<EditorState>().redo(),
              ),
              _ToolButton(
                icon: Icons.music_note_rounded,
                label: 'Music',
                enabled: hasProject && !busy,
                onTap: () => showMusicSheet(context),
              ),
              _ToolButton(
                icon: Icons.title_rounded,
                label: 'Text',
                enabled: hasProject && !busy,
                onTap: () {
                  final overlay =
                      context.read<EditorState>().addTextOverlay();
                  if (overlay != null) showTextOverlayEditor(context, overlay);
                  _surfaceActionError(context);
                },
              ),
              _ToolButton(
                icon: Icons.speed_rounded,
                label: 'Speed',
                enabled: hasProject && !busy && state.selectedClip != null,
                onTap: () => showSpeedSheet(context),
              ),
              _ToolButton(
                icon: Icons.volume_up_rounded,
                label: 'Volume',
                enabled: hasProject && !busy,
                onTap: () => showVolumeSheet(context),
              ),
              _ToolButton(
                icon: Icons.crop_rounded,
                label: 'Crop',
                enabled: hasProject && !busy && state.selectedClip != null,
                onTap: () => showFullscreenCropScreen(context),
              ),
              _ToolButton(
                icon: Icons.rotate_right_rounded,
                label: 'Rotate',
                enabled: hasProject && !busy && state.selectedClip != null,
                onTap: () => showTransformSheet(context),
              ),
              _ToolButton(
                icon: Icons.photo_filter_rounded,
                label: 'Filter',
                enabled: hasProject && !busy && state.selectedClip != null,
                onTap: () => showFilterSheet(context),
              ),
              _ToolButton(
                icon: Icons.tune_rounded,
                label: 'Adjust',
                enabled: hasProject && !busy && state.selectedClip != null,
                onTap: () => showAdjustmentSheet(context),
              ),
              // Only meaningful when a successor exists to blend into.
              ValueListenableBuilder<Duration>(
                valueListenable: state.playbackPosition,
                builder: (context, _, _) {
                  final index = state.selectedIndex;
                  final canTransition = index >= 0 &&
                      state.project != null &&
                      index + 1 < state.project!.clips.length;
                  return _ToolButton(
                    icon: Icons.merge_rounded,
                    label: 'Transition',
                    enabled: hasProject && !busy && canTransition,
                    onTap: () => showTransitionSheet(context),
                  );
                },
              ),
            ].map(_withSpacing).toList(),
          ),
        ),
      ),
    );
  }

  void _surfaceActionError(BuildContext context) {
    final state = context.read<EditorState>();
    final error = state.actionError;
    if (error == null) return;
    state.clearActionError();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }

  Widget _withSpacing(Widget child) {
    if (child is! _ToolButton) return child;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: child,
    );
  }

  Future<void> _showTrimDialog(BuildContext context) async {
    final state = context.read<EditorState>();
    final initialStart = state.trimStart;
    final initialEnd = state.trimEnd;
    final snapshot = state.project?.copy();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _TrimDialog(initialStart: initialStart, initialEnd: initialEnd),
    );

    if (confirmed == true) {
      // Record one history entry for the whole dialog transaction.
      if (snapshot != null &&
          (state.trimStart != initialStart || state.trimEnd != initialEnd)) {
        state.insertUndoSnapshot(snapshot);
      }
    } else {
      state.resetTrimValues(start: initialStart, end: initialEnd);
    }
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: label,
      child: Opacity(
        opacity: enabled ? 1 : .38,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled
              ? (onTap ??
                    () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Coming in a later update.'),
                            duration: Duration(milliseconds: 900),
                          ),
                        ))
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .05),
                    ),
                  ),
                  child: Icon(icon, color: AppTheme.accent, size: 24),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrimDialog extends StatelessWidget {
  const _TrimDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  final Duration initialStart;
  final Duration initialEnd;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final totalMs = state.sourceDuration.inMilliseconds;

    return AlertDialog(
      title: const Text('Trim clip'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: totalMs <= 0
          ? null
          : StatefulBuilder(
              builder: (context, setState) {
                final start = state.trimStart;
                final end = state.trimEnd;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _TimeLabel(label: 'Start', value: formatClock(start)),
                        _TimeLabel(label: 'Length', value: formatClock(end - start)),
                        _TimeLabel(label: 'End', value: formatClock(end)),
                      ],
                    ),
                    RangeSlider(
                      min: 0,
                      max: totalMs.toDouble(),
                      divisions: totalMs > 100 ? totalMs ~/ 100 : 1,
                      values: RangeValues(
                        start.inMilliseconds.toDouble(),
                        end.inMilliseconds.toDouble(),
                      ),
                      onChanged: (values) {
                        state.setTrim(
                          start: Duration(milliseconds: values.start.round()),
                          end: Duration(milliseconds: values.end.round()),
                        );
                        setState(() {});
                      },
                      onChangeEnd: (_) =>
                          state.seekTo(state.selectedClipStart),
                    ),
                  ],
                );
              },
            ),
      actions: [
        TextButton(
          onPressed: () {
            state.resetTrim();
            Navigator.of(context).pop(true);
          },
          child: const Text('Reset'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: .5),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
