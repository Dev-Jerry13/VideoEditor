import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/crop_math.dart';
import '../models/video_project.dart';
import '../models/video_transform.dart';
import '../state/editor_state.dart';

/// Crop bottom sheet for the SELECTED clip.
///
/// Shows the LIVE frame of the active controller with the crop window drawn
/// over it. Aspect presets solve windows against the TRUE source aspect
/// (so "16:9" yields 16:9 output on any source shape); dragging pans the
/// CONTENT with the finger. Everything applies live; Done collapses the
/// interaction into one undo entry, dismissing without Done reverts.
Future<void> showCropSheet(BuildContext context) {
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
      child: const _CropSheet(),
    ),
  );
}

class _AspectPreset {
  const _AspectPreset(this.label, this.ratio);

  final String label;

  /// w/h, or null for the untouched full frame.
  final double? ratio;
}

const _presets = <_AspectPreset>[
  _AspectPreset('Full', null),
  _AspectPreset('1:1', 1),
  _AspectPreset('4:3', 4 / 3),
  _AspectPreset('16:9', 16 / 9),
  _AspectPreset('9:16', 9 / 16),
];

class _CropSheet extends StatefulWidget {
  const _CropSheet();

  @override
  State<_CropSheet> createState() => _CropSheetState();
}

class _CropSheetState extends State<_CropSheet> {
  String? _clipId;
  CropSettings _initial = CropSettings.full;
  VideoProject? _baseline;

  @override
  void initState() {
    super.initState();
    final state = context.read<EditorState>();
    _clipId = state.selectedClip?.id;
    _initial = state.selectedClip?.transform.crop ?? CropSettings.full;
    _baseline = state.project?.copy();
  }

  CropSettings? _currentCrop(EditorState state) {
    final id = _clipId;
    if (id == null) return null;
    for (final c in state.clips) {
      if (c.id == id) return c.transform.crop;
    }
    return null;
  }

  /// DISPLAY aspect ratio (w/h) of the edited clip's frame, honoring the
  /// player's hidden rotation correction. Falls back to 16:9 only when the
  /// edited clip isn't the one on screen.
  double _sourceRatio(EditorState state) {
    final controller = state.controller;
    if (controller == null || _clipId != state.activeClipId) return 16 / 9;
    final value = controller.value;
    if (!value.isInitialized || value.aspectRatio <= 0) return 16 / 9;
    final quarter = value.rotationCorrection % 360;
    final swapped = quarter == 90 || quarter == 270;
    return swapped ? 1 / value.aspectRatio : value.aspectRatio;
  }

  void _update(CropSettings crop) {
    final state = context.read<EditorState>();
    final id = _clipId;
    if (id == null) return;
    for (final c in state.clips) {
      if (c.id == id) {
        state.updateTransformLive(
          id,
          c.transform.copyWith(crop: crop),
        );
        return;
      }
    }
  }

  void _revert() {
    final id = _clipId;
    if (id == null) return;
    final state = context.read<EditorState>();
    for (final c in state.clips) {
      if (c.id == id) {
        state.updateTransformLive(id, c.transform.copyWith(crop: _initial));
        return;
      }
    }
  }

  /// First preset whose window matches the current crop — Full is checked
  /// first so a 16:9 source showing its full frame highlights Full, not
  /// the redundant 16:9 chip.
  String? _selectedPresetLabel(CropSettings crop, double sourceRatio) {
    for (final preset in _presets) {
      if (cropMatchesRatio(crop, preset.ratio, sourceRatio)) {
        return preset.label;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final crop = _currentCrop(state);
    if (_clipId == null || crop == null) {
      Navigator.of(context).maybePop();
      return const SizedBox.shrink();
    }

    final changed = crop != _initial;
    final sourceRatio = _sourceRatio(state);

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
            Text('Crop', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Drag to move the frame · '
              '${_sizeLabel(crop)} of the original',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: .55),
              ),
            ),
            const SizedBox(height: 16),
            _CropPreviewBox(
              crop: crop,
              sourceRatio: sourceRatio,
              controller:
                  _clipId == state.activeClipId ? state.controller : null,
              onPan: (dx, dy) =>
                  setState(() => _update(panCrop(crop, -dx, -dy))),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected:
                        _selectedPresetLabel(crop, sourceRatio) ==
                            preset.label,
                    onSelected: (_) => setState(() => _update(
                          cropWindowForRatio(
                            sourceRatio: sourceRatio,
                            outputRatio: preset.ratio,
                            anchor: crop,
                          ),
                        )),
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

  static String _sizeLabel(CropSettings crop) {
    if (crop.isIdentity) return '100%';
    final pct = (crop.widthFraction * crop.heightFraction * 100).round();
    return '$pct%';
  }
}

/// LIVE frame preview with the crop window framed over it. The box is
/// contain-fitted to the true display ratio so overlay fractions map 1:1
/// onto real frame coordinates; drag gestures report normalized deltas.
class _CropPreviewBox extends StatelessWidget {
  const _CropPreviewBox({
    required this.crop,
    required this.sourceRatio,
    required this.onPan,
    this.controller,
  });

  final CropSettings crop;

  /// Display aspect ratio (w/h) of the underlying frame.
  final double sourceRatio;

  final void Function(double dx, double dy) onPan;

  /// Live controller for the edited clip, or null to fall back to a dark
  /// stand-in (e.g. editing a non-active clip).
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final live =
        controller != null && controller!.value.isInitialized;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Contain-fit the frame into the available sheet space.
        final maxW = constraints.maxWidth;
        final maxH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0;
        var boxWidth = maxW;
        var boxHeight = boxWidth / sourceRatio;
        if (boxHeight > maxH) {
          boxHeight = maxH.clamp(120.0, 340.0);
          boxWidth = boxHeight * sourceRatio;
        }

        void handle(DragUpdateDetails d) {
          onPan(d.delta.dx / boxWidth, d.delta.dy / boxHeight);
        }

        return Center(
          child: GestureDetector(
            onPanUpdate: handle,
            child: Container(
              width: boxWidth,
              height: boxHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (live)
                    AspectRatio(
                      aspectRatio: sourceRatio,
                      child: VideoPlayer(controller!),
                    )
                  else
                    const ColoredBox(color: Colors.black26),
                  for (final rect in _dimmedRegions(crop))
                    Positioned(
                      left: boxWidth * rect.$1,
                      top: boxHeight * rect.$2,
                      width: boxWidth * rect.$3,
                      height: boxHeight * rect.$4,
                      child: const ColoredBox(color: Colors.black54),
                    ),
                  Positioned(
                    left: boxWidth * crop.left,
                    top: boxHeight * crop.top,
                    width: boxWidth * crop.widthFraction,
                    height: boxHeight * crop.heightFraction,
                    child: Container(
                      foregroundDecoration: BoxDecoration(
                        border:
                            Border.all(color: AppTheme.accent, width: 2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The four strips OUTSIDE the crop window (left/right/top/bottom).
  static List<(double, double, double, double)> _dimmedRegions(
    CropSettings c,
  ) {
    return [
      (0, 0, c.left, 1), // left strip
      (c.right, 0, 1 - c.right, 1), // right strip
      (c.left, 0, c.widthFraction, c.top), // top strip
      (c.left, c.bottom, c.widthFraction, 1 - c.bottom), // bottom strip
    ];
  }
}
