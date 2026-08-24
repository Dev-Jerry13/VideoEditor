import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/video_adjustments.dart';
import '../models/video_project.dart';
import '../state/editor_state.dart';

/// Color-adjustment bottom sheet for the SELECTED clip. Four sliders in
/// USER units (−100..100) apply live; Done collapses everything into one
/// undo entry, dismissing without Done reverts.
Future<void> showAdjustmentSheet(BuildContext context) {
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
      child: const _AdjustmentSheet(),
    ),
  );
}

class _AdjustmentSheet extends StatefulWidget {
  const _AdjustmentSheet();

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  String? _clipId;
  VideoAdjustments _initial = VideoAdjustments.neutral;
  VideoProject? _baseline;

  @override
  void initState() {
    super.initState();
    final state = context.read<EditorState>();
    _clipId = state.selectedClip?.id;
    _initial = state.selectedClip?.adjustments ?? VideoAdjustments.neutral;
    _baseline = state.project?.copy();
  }

  VideoAdjustments? _current(EditorState state) {
    final id = _clipId;
    if (id == null) return null;
    for (final c in state.clips) {
      if (c.id == id) return c.adjustments;
    }
    return null;
  }

  void _update(VideoAdjustments value) {
    final state = context.read<EditorState>();
    final id = _clipId;
    if (id == null) return;
    state.updateAdjustmentsLive(id, value);
  }

  void _revert() {
    final id = _clipId;
    if (id == null) return;
    context.read<EditorState>().updateAdjustmentsLive(id, _initial);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final adjustments = _current(state);
    if (_clipId == null || adjustments == null) {
      Navigator.of(context).maybePop();
      return const SizedBox.shrink();
    }
    final changed = adjustments != _initial;

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
            Row(
              children: [
                Expanded(
                  child: Text('Adjust',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                TextButton(
                  onPressed: changed || !adjustments.isNeutral
                      ? () => _update(VideoAdjustments.neutral)
                      : null,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _SliderTile(
              icon: Icons.brightness_6_outlined,
              label: 'Brightness',
              value: adjustments.brightness,
              onChanged: (v) => _update(
                adjustments.copyWith(brightness: v),
              ),
            ),
            _SliderTile(
              icon: Icons.contrast,
              label: 'Contrast',
              value: adjustments.contrast,
              onChanged: (v) => _update(adjustments.copyWith(contrast: v)),
            ),
            _SliderTile(
              icon: Icons.palette_outlined,
              label: 'Saturation',
              value: adjustments.saturation,
              onChanged: (v) =>
                  _update(adjustments.copyWith(saturation: v)),
            ),
            _SliderTile(
              icon: Icons.thermostat_outlined,
              label: 'Warmth',
              value: adjustments.temperature,
              onChanged: (v) =>
                  _update(adjustments.copyWith(temperature: v)),
            ),
            const SizedBox(height: 10),
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

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white70),
        const SizedBox(width: 10),
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: VideoAdjustments.min,
            max: VideoAdjustments.max,
            divisions: 200,
            label: value.round().toString(),
            activeColor: AppTheme.accent,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${value.round()}',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              color: value == 0 ? Colors.white38 : AppTheme.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
