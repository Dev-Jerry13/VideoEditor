import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/crop_math.dart';
import '../models/video_project.dart';
import '../models/video_transform.dart';
import '../state/editor_state.dart';

/// Fullscreen crop editor screen for the selected video clip.
Future<void> showFullscreenCropScreen(BuildContext context) {
  final state = context.read<EditorState>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ChangeNotifierProvider<EditorState>.value(
        value: state,
        child: const _FullscreenCropScreen(),
      ),
    ),
  );
}

class _AspectPreset {
  const _AspectPreset(this.label, this.ratio);

  final String label;

  /// w/h, or null for the untouched full frame, or -1.0 for custom freeform.
  final double? ratio;
}

const _presets = <_AspectPreset>[
  _AspectPreset('Full', null),
  _AspectPreset('Custom', -1.0),
  _AspectPreset('1:1', 1),
  _AspectPreset('4:3', 4 / 3),
  _AspectPreset('16:9', 16 / 9),
  _AspectPreset('9:16', 9 / 16),
];

class _FullscreenCropScreen extends StatefulWidget {
  const _FullscreenCropScreen();

  @override
  State<_FullscreenCropScreen> createState() => _FullscreenCropScreenState();
}

class _FullscreenCropScreenState extends State<_FullscreenCropScreen> {
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
        state.updateTransformLive(id, c.transform.copyWith(crop: crop));
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

  String? _selectedPresetLabel(CropSettings crop, double sourceRatio) {
    if (crop.isIdentity) return 'Full';
    for (final preset in _presets) {
      if (preset.ratio != null && preset.ratio! > 0) {
        if (cropMatchesRatio(crop, preset.ratio, sourceRatio)) {
          return preset.label;
        }
      }
    }
    return 'Custom';
  }

  void _resizeHandle(
    CropSettings crop,
    double dx,
    double dy, {
    bool left = false,
    bool top = false,
    bool right = false,
    bool bottom = false,
    required double boxWidth,
    required double boxHeight,
  }) {
    final ndx = dx / boxWidth;
    final ndy = dy / boxHeight;

    double l = crop.left;
    double t = crop.top;
    double r = crop.right;
    double b = crop.bottom;

    if (left) l = (l + ndx).clamp(0.0, r - 0.1);
    if (top) t = (t + ndy).clamp(0.0, b - 0.1);
    if (right) r = (r + ndx).clamp(l + 0.1, 1.0);
    if (bottom) b = (b + ndy).clamp(t + 0.1, 1.0);

    _update(CropSettings(left: l, top: t, right: r, bottom: b));
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
    final activePreset = _selectedPresetLabel(crop, sourceRatio);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Crop Video'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            if (changed) _revert();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: changed && _baseline != null
                ? () {
                    context.read<EditorState>().insertUndoSnapshot(_baseline!);
                    Navigator.of(context).pop();
                  }
                : null,
            child: Text(
              'Apply',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: changed ? AppTheme.accent : Colors.white38,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _FullscreenCropBox(
                  crop: crop,
                  sourceRatio: sourceRatio,
                  controller: _clipId == state.activeClipId ? state.controller : null,
                  onPan: (dx, dy) => setState(() => _update(panCrop(crop, -dx, -dy))),
                  onResize: (dx, dy, {left = false, top = false, right = false, bottom = false, required boxWidth, required boxHeight}) =>
                      setState(() => _resizeHandle(crop, dx, dy, left: left, top: top, right: right, bottom: bottom, boxWidth: boxWidth, boxHeight: boxHeight)),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              color: Colors.black87,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Drag corners to resize · Drag center to move · ${_sizeLabel(crop)}',
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: .55)),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final preset in _presets)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(preset.label),
                              selected: activePreset == preset.label,
                              onSelected: (_) {
                                if (preset.ratio == -1.0) {
                                  setState(() {});
                                  return;
                                }
                                setState(() => _update(
                                      cropWindowForRatio(
                                        sourceRatio: sourceRatio,
                                        outputRatio: preset.ratio,
                                        anchor: crop,
                                      ),
                                    ));
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
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

class _FullscreenCropBox extends StatelessWidget {
  const _FullscreenCropBox({
    required this.crop,
    required this.sourceRatio,
    required this.onPan,
    required this.onResize,
    this.controller,
  });

  final CropSettings crop;
  final double sourceRatio;
  final void Function(double dx, double dy) onPan;
  final void Function(
    double dx,
    double dy, {
    bool left,
    bool top,
    bool right,
    bool bottom,
    required double boxWidth,
    required double boxHeight,
  }) onResize;
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final live = controller != null && controller!.value.isInitialized;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        var boxWidth = maxW;
        var boxHeight = boxWidth / sourceRatio;
        if (boxHeight > maxH) {
          boxHeight = maxH;
          boxWidth = boxHeight * sourceRatio;
        }

        return Center(
          child: GestureDetector(
            onPanUpdate: (d) => onPan(d.delta.dx / boxWidth, d.delta.dy / boxHeight),
            child: Container(
              width: boxWidth,
              height: boxHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
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
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.accent, width: 2),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(painter: _CropGridPainter()),
                          _CropHandle(
                            alignment: Alignment.topLeft,
                            onPan: (dx, dy) => onResize(dx, dy, left: true, top: true, boxWidth: boxWidth, boxHeight: boxHeight),
                          ),
                          _CropHandle(
                            alignment: Alignment.topRight,
                            onPan: (dx, dy) => onResize(dx, dy, right: true, top: true, boxWidth: boxWidth, boxHeight: boxHeight),
                          ),
                          _CropHandle(
                            alignment: Alignment.bottomLeft,
                            onPan: (dx, dy) => onResize(dx, dy, left: true, bottom: true, boxWidth: boxWidth, boxHeight: boxHeight),
                          ),
                          _CropHandle(
                            alignment: Alignment.bottomRight,
                            onPan: (dx, dy) => onResize(dx, dy, right: true, bottom: true, boxWidth: boxWidth, boxHeight: boxHeight),
                          ),
                        ],
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

  static List<(double, double, double, double)> _dimmedRegions(CropSettings c) {
    return [
      (0, 0, c.left, 1),
      (c.right, 0, 1 - c.right, 1),
      (c.left, 0, c.widthFraction, c.top),
      (c.left, c.bottom, c.widthFraction, 1 - c.bottom),
    ];
  }
}

class _CropHandle extends StatelessWidget {
  const _CropHandle({required this.alignment, required this.onPan});
  final Alignment alignment;
  final void Function(double dx, double dy) onPan;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onPan(d.delta.dx, d.delta.dy),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(blurRadius: 4, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
