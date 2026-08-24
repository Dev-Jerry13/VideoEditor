import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../models/clip_transition.dart';
import '../models/video_project.dart';
import '../state/editor_state.dart';

/// Transition bottom sheet for the seam AFTER the SELECTED clip. Type and
/// duration apply live through [EditorState.setTransitionAfterLive] so the
/// timeline length updates as you tap; Done collapses everything into one
/// undo entry, dismissing without Done reverts.
Future<void> showTransitionSheet(BuildContext context) {
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
      child: const _TransitionSheet(),
    ),
  );
}

class _TransitionSheet extends StatefulWidget {
  const _TransitionSheet();

  @override
  State<_TransitionSheet> createState() => _TransitionSheetState();
}

class _TransitionSheetState extends State<_TransitionSheet> {
  String? _clipId;
  ClipTransition _initial = ClipTransition.none;
  VideoProject? _baseline;

  @override
  void initState() {
    super.initState();
    final state = context.read<EditorState>();
    _clipId = state.selectedClip?.id;
    _initial = state.transitionAfterSelected ?? ClipTransition.none;
    _baseline = state.project?.copy();
  }

  ClipTransition _current(EditorState state) {
    final id = _clipId;
    if (id == null) return ClipTransition.none;
    return state.transitionAfter(id) ?? ClipTransition.none;
  }

  void _update(ClipTransition value) {
    final id = _clipId;
    if (id == null) return;
    context.read<EditorState>().setTransitionAfterLive(id, value);
  }

  void _revert() {
    final id = _clipId;
    if (id == null) return;
    context.read<EditorState>().setTransitionAfterLive(id, _initial);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final current = _current(state);
    if (_clipId == null || !state.hasSuccessorFor(_clipId!)) {
      Navigator.of(context).maybePop();
      return const SizedBox.shrink();
    }
    final changed = current != _initial;
    final max = state.maxTransitionAfterSelected;
    final effective = state.effectiveTransitionAfterSelected;

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
            Text('Transition',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Blends into the next clip. The overlap shortens the timeline.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: .55),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in TransitionType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: current.type == type,
                    onSelected: (_) => _update(
                      ClipTransition(type: type, duration: current.duration),
                    ),
                  ),
              ],
            ),
            if (current.isActive) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option
                        in AppConstants.transitionDurationChoices)
                      ChoiceChip(
                        label: Text(formatClock(option)),
                        selected: current.duration == option,
                        onSelected: option <= max
                            ? (_) => _update(ClipTransition(
                                  type: current.type,
                                  duration: option,
                                ))
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.merge_rounded,
                      size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Effective overlap ${formatClock(effective)}'
                      '${current.duration > max ? ' · clamped by clip length' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: .65),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
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
}
