import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/crop_math.dart';
import '../core/utils/ffmpeg_filters.dart';
import '../core/utils/time_utils.dart';
import '../models/clip_transition.dart';
import '../models/text_overlay.dart';
import '../models/video_clip.dart';
import '../models/video_transform.dart';
import '../services/timeline_service.dart' show SegmentLayout;
import '../state/editor_state.dart';

class VideoPreview extends StatelessWidget {
  const VideoPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final controller = state.controller;

    if (controller == null || !state.isVideoInitialized || !state.hasProject) {
      return const _Placeholder();
    }

    final activeClip = _clipById(state.clips, state.activeClipId);
    if (activeClip == null) return const _Placeholder();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _canvasAspectRatio(state),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Active clip + optional incoming blend during a
                      // transition window. Both run through the same
                      // crop→rotate→flip→color order the export burns.
                      ValueListenableBuilder<Duration>(
                        valueListenable: state.playbackPosition,
                        builder: (context, position, _) {
                          final blend = _blendFor(state, position);
                          final incomingId = state.incomingClipId;
                          final incomingClip =
                              incomingId == null ? null : _clipById(state.clips, incomingId);
                          final incomingController = state.incomingController;
                          final showIncoming = blend != null &&
                              incomingClip != null &&
                              incomingController != null &&
                              incomingController.value.isInitialized;

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(
                                child: _ClipVisual(
                                  clip: activeClip,
                                  controller: controller,
                                ),
                              ),
                              if (showIncoming) ...[
                                // Black/white fades dip through a solid
                                // frame (triangle opacity peaking midway).
                                if (blend.seg.transitionAfter.type ==
                                    TransitionType.black)
                                  Opacity(
                                    opacity: _backdropPhase(blend.phase),
                                    child:
                                        const ColoredBox(color: Colors.black),
                                  )
                                else if (blend.seg.transitionAfter.type ==
                                    TransitionType.white)
                                  Opacity(
                                    opacity: _backdropPhase(blend.phase),
                                    child:
                                        const ColoredBox(color: Colors.white),
                                  ),
                                IgnorePointer(
                                  child: Opacity(
                                    opacity: blend.phase,
                                    child: Center(
                                      child: _ClipVisual(
                                        clip: incomingClip,
                                        controller: incomingController,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                       // Text overlays render in CANVAS space (export draws
                       // them over the output W×H after scaling), so they sit
                       // above every clip visual but inside the canvas rect.
                       _TextOverlayLayer(state: state),
                    ],
                  ),
                ),
              ),
            ),
            _TapLayer(state: state),
            _CenterOverlay(controller: controller),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => _openFullscreen(context),
                icon: const Icon(Icons.fullscreen_rounded),
                tooltip: 'Fullscreen',
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: ValueListenableBuilder<Duration>(
                valueListenable: state.playbackPosition,
                builder: (context, position, _) => _TimePill(
                  text:
                      '${formatClock(position)} / ${formatClock(state.totalDuration)}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const _FullscreenPlayer(),
      ),
    );
  }
}

// -- Visual pipeline helpers --------------------------------------------------

VideoClip? _clipById(List<VideoClip> clips, String? id) {
  if (id == null) return null;
  for (final c in clips) {
    if (c.id == id) return c;
  }
  return null;
}

/// Canvas aspect ratio for the preview frame: the project override wins;
/// otherwise follow the visible clip's post-visual shape. (Export pins this
/// to the FIRST clip's post-visual frame — identical whenever clips share a
/// resolution or an override is set; plan §29 accepts the tiny deviation.)
double _canvasAspectRatio(EditorState state) {
  final project = state.project!;
  final override = project.outputAspectRatio;
  if (override != null) {
    final parts = override.split(':');
    if (parts.length == 2) {
      final w = int.tryParse(parts[0]);
      final h = int.tryParse(parts[1]);
      if (w != null && h != null && w > 0 && h > 0) return w / h;
    }
  }
  final controller = state.controller;
  final clip = _clipById(state.clips, state.activeClipId);
  if (controller != null &&
      clip != null &&
      controller.value.isInitialized) {
    return _visualAspectRatio(clip, _displayAspectRatio(controller));
  }
  return 16 / 9;
}

/// Aspect ratio AFTER crop and rotation (flips and color don't change it).
double _visualAspectRatio(VideoClip clip, double sourceAr) {
  final crop = clip.transform.crop;
  final preRotation = sourceAr *
      crop.widthFraction /
      math.max(1e-6, crop.heightFraction);
  return clip.transform.transform.rotation.swapsDimensions
      ? 1 / preRotation
      : preRotation;
}

/// True DISPLAY aspect ratio of the controller's frame: the player applies
/// metadata rotation internally (hidden RotatedBox), so [VideoPlayerValue]
/// aspectRatio alone is wrong for rotation-tagged files.
double _displayAspectRatio(VideoPlayerController controller) {
  final value = controller.value;
  if (!value.isInitialized || value.aspectRatio <= 0) return 16 / 9;
  final quarter = value.rotationCorrection % 360;
  final swapped = quarter == 90 || quarter == 270;
  return swapped ? 1 / value.aspectRatio : value.aspectRatio;
}

/// The transition window covering [position], if any.
({SegmentLayout seg, double phase})? _blendFor(
  EditorState state,
  Duration position,
) {
  final project = state.project;
  if (project == null) return null;
  for (final seg in project.layout.segments) {
    if (seg.overlapAfter <= Duration.zero) continue;
    if (position < seg.seam || position >= seg.coveredEnd) continue;
    final phase =
        (position - seg.seam).inMilliseconds / seg.overlapAfter.inMilliseconds;
    return (seg: seg, phase: phase.clamp(0.0, 1.0));
  }
  return null;
}

double _backdropPhase(double phase) => 1 - (2 * phase - 1).abs();

/// Contain-fits [aspectRatio] into [constraints].
Size _fitContain(double aspectRatio, BoxConstraints constraints) {
  final w = constraints.maxWidth;
  final h = constraints.maxHeight;
  if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
    return Size(w.isFinite && w > 0 ? w : 1, h.isFinite && h > 0 ? h : 1);
  }
  if (w / h > aspectRatio) return Size(h * aspectRatio, h);
  return Size(w, w / aspectRatio);
}

/// One clip's transformed texture: CROP → ROTATE → FLIP → COLOR, matching
/// `buildVideoFilterChain` exactly (plan §22 single visual authority). The
/// raw [Texture] is stretched into the oversized pre-crop box so the crop
/// window maps 1:1 onto FFmpeg's crop filter geometry.
class _ClipVisual extends StatelessWidget {
  const _ClipVisual({required this.clip, required this.controller});

  final VideoClip clip;
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final value = controller.value;
        if (!value.isInitialized) return const SizedBox.shrink();

        final crop = clip.transform.crop;
        final transform = clip.transform.transform;
        final cw = crop.widthFraction;
        final odd = transform.rotation.quarterTurns.isOdd;

        final visual = _fitContain(
          _visualAspectRatio(clip, _displayAspectRatio(controller)),
          constraints,
        );
        // Pre-rotation cropped rectangle that rotates/flips into [visual].
        final croppedW = odd ? visual.height : visual.width;
        // Full-source box PRESERVING the display AR whose crop window lands
        // exactly on [cropped]: scale k solves k·ar·cw = croppedW.
        final ar = _displayAspectRatio(controller);
        final k = croppedW / (ar * cw);
        final sourceW = ar * k;
        final sourceH = k;

        Widget content = ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: -crop.left * sourceW,
                top: -crop.top * sourceH,
                width: sourceW,
                height: sourceH,
                child: VideoPlayer(controller),
              ),
            ],
          ),
        );

        content = RotatedBox(
          quarterTurns: transform.rotation.quarterTurns,
          child: content,
        );

        if (transform.flipHorizontal || transform.flipVertical) {
          content = Transform(
            transform: Matrix4.diagonal3Values(
              transform.flipHorizontal ? -1.0 : 1.0,
              transform.flipVertical ? -1.0 : 1.0,
              1.0,
            ),
            alignment: Alignment.center,
            child: content,
          );
        }

        final matrix = FfmpegFilters.previewColorMatrix(
          clip.filter,
          clip.adjustments,
        );
        content = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: content,
        );

        return SizedBox(width: visual.width, height: visual.height, child: content);
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.videocam_off_rounded,
        size: 48,
        color: Theme.of(context)
            .colorScheme
            .onSurface
            .withValues(alpha: .25),
      ),
    );
  }
}

/// Routes taps through [EditorState] so play/pause follows the whole
/// project sequence (restart from the start after finishing, clip-boundary
/// advances), not just the current controller.
class _TapLayer extends StatelessWidget {
  const _TapLayer({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: state.togglePlayPause,
      ),
    );
  }
}

/// Renders every overlay whose window covers the playhead. The overlay
/// being edited stays visible (even outside its window) and becomes
/// draggable; drag deltas convert straight into normalized coordinates.
class _TextOverlayLayer extends StatelessWidget {
  const _TextOverlayLayer({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: state.playbackPosition,
      builder: (context, position, _) {
        final project = state.project;
        if (project == null) return const SizedBox.shrink();

        final visible = project.textOverlays
            .where((o) => position >= o.startTime && position < o.endTime)
            .toList();

        final editing = state.textEditingSession;
        final selectedId = editing ? state.selectedTextId : null;
        if (selectedId != null &&
            !visible.any((o) => o.id == selectedId)) {
          final selected = state.selectedText;
          if (selected != null) visible.add(selected);
        }
        if (visible.isEmpty) return const SizedBox.shrink();

        return Stack(
          fit: StackFit.expand,
          children: [
            for (final overlay in visible)
              if (overlay.id == selectedId)
                _DraggableOverlayLabel(
                  key: ValueKey('drag_${overlay.id}'),
                  overlay: overlay,
                  state: state,
                )
              else
                IgnorePointer(
                  child: _OverlayLabel(overlay: overlay),
                ),
          ],
        );
      },
    );
  }
}

class _DraggableOverlayLabel extends StatefulWidget {
  const _DraggableOverlayLabel({
    super.key,
    required this.overlay,
    required this.state,
  });

  final TextOverlay overlay;
  final EditorState state;

  @override
  State<_DraggableOverlayLabel> createState() =>
      _DraggableOverlayLabelState();
}

class _DraggableOverlayLabelState extends State<_DraggableOverlayLabel> {
  bool _snapshotPushed = false;

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
    final state = widget.state;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final box = _measureOverlay(overlay, width, height);
        final offset = _anchorOffset(overlay, box, width, height);

        return Positioned(
          left: offset.dx,
          top: offset.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              // One history entry per drag gesture ("Move text").
              if (!_snapshotPushed) {
                state.pushUndoSnapshot();
                _snapshotPushed = true;
              }
            },
            onPanUpdate: (details) {
              state.updateTextPosition(
                overlay.id,
                overlay.x + details.delta.dx / width,
                overlay.y + details.delta.dy / height,
              );
            },
            onPanCancel: () => _snapshotPushed = false,
            onPanEnd: (_) => _snapshotPushed = false,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.accent, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _overlayTextWidget(overlay, height),
            ),
          ),
        );
      },
    );
  }
}

/// Style matching the export drawtext parameters (size = fraction of the
/// VIDEO height, so preview and export scale identically).
TextStyle _overlayStyle(TextOverlay overlay, double videoHeight) {
  return TextStyle(
    fontSize: (overlay.fontSize * videoHeight).clamp(6.0, double.infinity),
    fontWeight: overlay.bold ? FontWeight.w700 : FontWeight.w500,
    color: Color(int.parse('FF${overlay.color.hex}', radix: 16)),
    height: 1.15,
  );
}

Size _measureOverlay(TextOverlay overlay, double maxWidth, double videoHeight) {
  final painter = TextPainter(
    text: TextSpan(
      text: overlay.text == ' ' ? ' ' : overlay.text,
      style: _overlayStyle(overlay, videoHeight),
    ),
    textAlign: overlay.alignment,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth * .92);
  final size = Size(painter.width, painter.height);
  painter.dispose();
  // Account for the background box padding when one is drawn.
  return overlay.background
      ? Size(size.width + 12, size.height + 6)
      : size;
}

/// Same anchor semantics as the export drawtext filter: left anchors the
/// box's LEFT edge at x, center its CENTER, right its RIGHT edge; y is
/// always the vertical center of the box.
Offset _anchorOffset(
  TextOverlay overlay,
  Size box,
  double width,
  double height,
) {
  var left = switch (overlay.alignment) {
    TextAlign.left => overlay.x * width,
    TextAlign.right => overlay.x * width - box.width,
    _ => overlay.x * width - box.width / 2,
  };
  var top = overlay.y * height - box.height / 2;
  left = left.clamp(2.0, math.max(2.0, width - box.width - 2.0));
  top = top.clamp(2.0, math.max(2.0, height - box.height - 2.0));
  return Offset(left, top);
}

Widget _overlayTextWidget(TextOverlay overlay, double videoHeight) {
  final content = Text(
    overlay.text == ' ' ? ' ' : overlay.text,
    textAlign: overlay.alignment,
    textDirection: TextDirection.ltr,
    style: _overlayStyle(overlay, videoHeight),
  );
  if (!overlay.background) return content;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(3),
    ),
    child: content,
  );
}

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel({required this.overlay});

  final TextOverlay overlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final box = _measureOverlay(overlay, w, h);
        final offset = _anchorOffset(overlay, box, w, h);
        return Positioned(
          left: offset.dx,
          top: offset.dy,
          child: _overlayTextWidget(overlay, h),
        );
      },
    );
  }
}

class _CenterOverlay extends StatelessWidget {
  const _CenterOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.isPlaying || value.isBuffering) return const SizedBox.shrink();
        return Center(
          child: IgnorePointer(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 44,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Reuses the shared controller; owned by [EditorState], never disposed
/// here. Watches the state so a cross-source controller switch mid-playback
/// swaps the texture instead of freezing on a stale one.
class _FullscreenPlayer extends StatefulWidget {
  const _FullscreenPlayer();

  @override
  State<_FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<_FullscreenPlayer> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: state.togglePlayPause,
        child: Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}


