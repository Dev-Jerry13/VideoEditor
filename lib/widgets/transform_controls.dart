import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/video_project.dart';
import '../models/video_transform.dart';
import '../state/editor_state.dart';

/// Rotate/flip bottom sheet for the SELECTED clip. Every button applies
/// live so the preview reacts instantly; Done collapses the whole
/// interaction into one undo entry, dismissing without Done reverts.
Future<void> showTransformSheet(BuildContext context) {
  final state = context.read<EditorState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => ChangeNotifierProvider<EditorState>.value(
      value: state,
      child: const _TransformSheet(),
    ),
  );
}

class _TransformSheet extends StatefulWidget {
  const _TransformSheet();

  @override
  State<_TransformSheet> createState() => _TransformSheetState();
}

class _TransformSheetState extends State<_TransformSheet> {
  String? _clipId;
  TransformSettings _initial = TransformSettings.identity;
  VideoProject? _baseline;

  @override
  void initState() {
    super.initState();
    final state = context.read<EditorState>();
    _clipId = state.selectedClip?.id;
    _initial = state.selectedClip?.transform.transform ??
        TransformSettings.identity;
    _baseline = state.project?.copy();
  }

  void _apply(TransformSettings value) {
    final state = context.read<EditorState>();
    final id = _clipId;
    if (id == null) return;
    for (final c in state.clips) {
      if (c.id == id) {
        state.updateTransformLive(id, c.transform.copyWith(transform: value));
        return;
      }
    }
  }

  TransformSettings _current(EditorState state) {
    final id = _clipId;
    if (id == null) return TransformSettings.identity;
    for (final c in state.clips) {
      if (c.id == id) return c.transform.transform;
    }
    return TransformSettings.identity;
  }

  void _revert() {
    final id = _clipId;
    if (id == null) return;
    final state = context.read<EditorState>();
    final clip = state.clips.where((c) => c.id == id).firstOrNull;
    if (clip == null) return;
    state.updateTransformLive(id, clip.transform.copyWith(transform: _initial));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    if (_clipId == null ||
        !state.clips.any((c) => c.id == _clipId)) {
      Navigator.of(context).maybePop();
      return const SizedBox.shrink();
    }

    final current = _current(state);
    final changed = current != _initial;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Rotate & Flip',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Rotation ${_rotationLabel(current.rotation)}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: .55),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _apply(_rotated(current, -1)),
                    icon: const Icon(Icons.rotate_left),
                    label: const Text('90° CCW'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _apply(_rotated(current, 1)),
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('90° CW'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilterChip(
                    selected: current.flipHorizontal,
                    onSelected: (_) =>
                        _apply(current.copyWith(flipHorizontal: !current.flipHorizontal)),
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flip, size: 18),
                        SizedBox(width: 6),
                        Text('Flip H'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilterChip(
                    selected: current.flipVertical,
                    onSelected: (_) =>
                        _apply(current.copyWith(flipVertical: !current.flipVertical)),
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flip_camera_android, size: 18),
                        SizedBox(width: 6),
                        Text('Flip V'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (changed) _revert();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: changed && _baseline != null
                        ? () {
                            context
                                .read<EditorState>()
                                .insertUndoSnapshot(_baseline!);
                            Navigator.of(context).pop();
                          }
                        : null,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static TransformSettings _rotated(TransformSettings current, int dir) {
    final turns =
        (current.rotation.quarterTurns + dir + 4) % 4;
    return current.copyWith(rotation: Rotation.values[turns]);
  }

  static String _rotationLabel(Rotation rotation) => switch (rotation) {
        Rotation.none => 'None',
        Rotation.clockwise90 => '90° CW',
        Rotation.clockwise180 => '180°',
        Rotation.clockwise270 => '270° CW',
      };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final item in this) {
      return item;
    }
    return null;
  }
}
