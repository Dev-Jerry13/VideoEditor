import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../models/video_clip.dart';
import '../models/video_project.dart';
import '../state/editor_state.dart';

/// Playback-speed bottom sheet for the SELECTED clip. Chips apply live so
/// the timeline and preview react instantly; Done collapses the whole
/// interaction into one undo entry, dismissing without Done reverts.
Future<void> showSpeedSheet(BuildContext context) {
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
      child: const _SpeedSheet(),
    ),
  );
}

class _SpeedSheet extends StatefulWidget {
  const _SpeedSheet();

  @override
  State<_SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<_SpeedSheet> {
  String? _clipId;
  double _initialSpeed = 1.0;
  VideoProject? _baseline;

  @override
  void initState() {
    super.initState();
    final state = context.read<EditorState>();
    _clipId = state.selectedClip?.id;
    _initialSpeed = state.selectedClip?.speed ?? 1.0;
    _baseline = state.project?.copy();
  }

  void _revert() {
    if (_clipId == null) return;
    context.read<EditorState>().applyClipSpeedLive(_clipId!, _initialSpeed);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final clipId = _clipId;
    VideoClip? clip;
    if (clipId != null) {
      for (final c in state.clips) {
        if (c.id == clipId) {
          clip = c;
          break;
        }
      }
    }

    if (clip == null) {
      // Selected clip vanished (undo while open, etc.).
      Navigator.of(context).maybePop();
      return const SizedBox.shrink();
    }

    final busy =
        state.isLoadingProject || state.exportPhase == ExportPhase.exporting;
    final changed = clip.speed != _initialSpeed;
    final newTotal = _totalWithSpeed(state.project, clipId!, clip.speed);

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
            Text('Playback Speed',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Clip ${state.selectedIndex + 1} · '
              '${formatClock(clip.trimmedDuration)} → '
              '${formatClock(clip.effectiveDuration)}'
              '${newTotal != null ? ' · Total ${formatClock(newTotal)}' : ''}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: .55),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in AppConstants.speedPresets)
                  ChoiceChip(
                    label: Text('${_label(preset)}x'),
                    selected: (clip.speed - preset).abs() < 0.001,
                    onSelected: busy
                        ? null
                        : (_) =>
                            state.applyClipSpeedLive(clipId, preset),
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
                    onPressed: () {
                      if (changed && _baseline != null) {
                        state.insertUndoSnapshot(_baseline!);
                      }
                      Navigator.of(context).pop();
                    },
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
}

String _label(double speed) => speed % 1 == 0
    ? speed.toStringAsFixed(speed < 10 ? 1 : 0).replaceAll('.0', '')
    : speed.toString();

/// Project total if [clipId] ran at [speed] — for the preview line.
Duration? _totalWithSpeed(
  VideoProject? project,
  String clipId,
  double speed,
) {
  if (project == null) return null;
  var total = Duration.zero;
  for (final c in project.clips) {
    final effective = c.id == clipId
        ? Duration(
            milliseconds:
                (c.trimmedDuration.inMilliseconds / speed).round(),
          )
        : c.effectiveDuration;
    total += effective;
  }
  return total;
}
