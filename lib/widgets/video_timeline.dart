import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../models/video_clip.dart';
import '../services/timeline_service.dart';
import '../state/editor_state.dart';
import 'audio_lane.dart';
import 'text_lane.dart';
import 'timeline_clip.dart';
import 'transition_marker.dart';
import 'transition_selector.dart';

/// Multi-clip project timeline with VIDEO / TEXT / AUDIO tracks sharing
/// one global time axis and one playhead.
///
/// The video lane layers, bottom to top:
/// 1. Clip blocks sized proportionally to their OUTPUT durations (speed
///    applied)
/// 2. Dim outside the selected clip
/// 3. Scrub layer (tap = select + seek, drag = scrub)
/// 4. Trim handles for the selected clip's range
///
/// A long-press on the video lane starts drag-reordering; blocks reflow
/// live and the final order is committed through [EditorState.reorderClips].
/// The text/audio lanes are read-only here — taps open their editors.
class VideoTimeline extends StatelessWidget {
  const VideoTimeline({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    if (!state.hasProject) {
      return SizedBox(height: height);
    }

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            const SizedBox(height: 6),
            _TimeLabels(state: state),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: _TimelineBody(state: state, width: width),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 18,
                            child: TextLane(state: state, width: width),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 26,
                            child: AudioLane(state: state, width: width),
                          ),
                        ],
                      ),
                      // One playhead sweeping all three tracks.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ValueListenableBuilder<Duration>(
                            valueListenable: state.playbackPosition,
                            builder: (context, position, _) {
                              final totalMs = state
                                  .totalDuration.inMilliseconds
                                  .toDouble();
                              final fraction = totalMs <= 0
                                  ? 0.0
                                  : position.inMilliseconds / totalMs;
                              final x =
                                  (fraction * width).clamp(0.0, width);
                              final playing = state.isPlaying;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: x,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent.withValues(alpha: playing ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: x - 1.5,
                                    top: 0,
                                    bottom: 0,
                                    width: 3,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: playing ? AppTheme.accent : Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(2),
                                        boxShadow: [
                                          BoxShadow(
                                            blurRadius: playing ? 6 : 4,
                                            color: playing ? AppTheme.accent.withValues(alpha: .7) : Colors.black54,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: x - 7,
                                    top: -4,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: playing ? AppTheme.accent : Colors.white,
                                        shape: BoxShape.circle,
                                        border: playing
                                            ? Border.all(color: Colors.white, width: 2)
                                            : null,
                                        boxShadow: playing
                                            ? [
                                                BoxShadow(
                                                  blurRadius: 4,
                                                  color: AppTheme.accent.withValues(alpha: .8),
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _TimeLabels extends StatelessWidget {
  const _TimeLabels({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      children: [
        Text('00:00', style: style),
        Expanded(
          child: ValueListenableBuilder<Duration>(
            valueListenable: state.playbackPosition,
            builder: (context, position, _) => Text(
              formatClock(position),
              textAlign: TextAlign.center,
              style: style.copyWith(
                color: AppTheme.accent,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Text(formatClock(state.totalDuration), style: style),
      ],
    );
  }
}

class _TimelineBody extends StatefulWidget {
  const _TimelineBody({required this.state, required this.width});

  final EditorState state;
  final double width;

  @override
  State<_TimelineBody> createState() => _TimelineBodyState();
}

class _TimelineBodyState extends State<_TimelineBody> {
  /// Local arrangement while a drag-reorder is in flight; committed to the
  /// editor state on drop.
  List<VideoClip>? _dragOrder;

  /// Index of the dragged clip inside [_dragOrder].
  int _dragCurrent = 0;

  /// Insertion slot the current arrangement corresponds to (pre-adjustment,
  /// matching [EditorState.reorderClips] semantics).
  int _dragSlot = 0;

  bool get _reordering => _dragOrder != null;

  /// Structural work in flight (project load or export): scrubbing and
  /// editing gestures are parked so the render pipeline and the decoders
  /// don't fight, and results stay predictable.
  bool get _busy =>
      widget.state.isLoadingProject ||
      widget.state.exportPhase == ExportPhase.exporting;

  double get _totalMs =>
      widget.state.totalDuration.inMilliseconds.toDouble();

  Duration _positionAt(double x) {
    if (widget.width <= 0 || _totalMs <= 0) return Duration.zero;
    final ratio = (x / widget.width).clamp(0.0, 1.0);
    return Duration(milliseconds: (ratio * _totalMs).round());
  }

  // -- Reorder ----------------------------------------------------------------

  void _startReorder(LongPressStartDetails details) {
    final clips = widget.state.clips;
    if (_busy || clips.length < 2 || _reordering) return;

    final x = details.localPosition.dx;
    final layout = TimelineService.resolve(clips, widget.state.project?.transitions ?? {});
    var index = clips.length - 1;
    for (var i = 0; i < layout.segments.length; i++) {
      final seg = layout.segments[i];
      final totalMs = layout.totalDuration.inMilliseconds.toDouble();
      final start = totalMs <= 0 ? 0.0 : (seg.projectStart.inMilliseconds / totalMs) * widget.width;
      final end = totalMs <= 0 ? widget.width : start + (seg.effectiveDuration.inMilliseconds / totalMs) * widget.width;
      if (x <= end) {
        index = i;
        break;
      }
    }

    HapticFeedback.mediumImpact();
    widget.state.pause();
    setState(() {
      _dragOrder = List.of(clips);
      _dragCurrent = index;
      _dragSlot = index;
    });
  }

  void _updateReorder(LongPressMoveUpdateDetails details) {
    if (!_reordering) return;
    final order = _dragOrder!;
    final layout = TimelineService.resolve(order, widget.state.project?.transitions ?? {});
    final x = (details.localPosition.dx).clamp(0.0, widget.width);

    var slot = order.length;
    final totalMs = layout.totalDuration.inMilliseconds.toDouble();
    for (var i = 0; i < layout.segments.length; i++) {
      final seg = layout.segments[i];
      final start = totalMs <= 0 ? 0.0 : (seg.projectStart.inMilliseconds / totalMs) * widget.width;
      final w = totalMs <= 0 ? widget.width : (seg.effectiveDuration.inMilliseconds / totalMs) * widget.width;
      if (x < start + w) {
        slot = x - start < w / 2 ? i : i + 1;
        break;
      }
    }

    if (slot == _dragSlot) return;
    var adjusted = slot > _dragCurrent ? slot - 1 : slot;
    if (adjusted == _dragCurrent) {
      setState(() => _dragSlot = slot);
      return;
    }
    setState(() {
      final moved = order.removeAt(_dragCurrent);
      order.insert(adjusted, moved);
      _dragCurrent = adjusted;
      _dragSlot = slot;
    });
  }

  void _endReorder() {
    if (!_reordering) return;
    final from =
        widget.state.clips.indexWhere((c) => c.id == _dragOrder![_dragCurrent].id);
    final slot = _dragSlot;
    setState(() => _dragOrder = null);
    if (from >= 0) {
      widget.state.reorderClips(from, slot);
    }
  }

  void _cancelReorder() {
    if (_reordering) setState(() => _dragOrder = null);
  }

  // -- Build --------------------------------------------------------------------

  double fractionOfSeam(TimelineLayout layout, int index) {
    final totalMs = layout.totalDuration.inMilliseconds.toDouble();
    if (totalMs <= 0 || index < 0 || index >= layout.segments.length) return 0;
    return (layout.segments[index].seam.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final order = _reordering ? _dragOrder! : state.clips;
    final layout = _reordering
        ? TimelineService.resolve(order, state.project?.transitions ?? {})
        : (state.project?.layout ?? TimelineLayout(segments: const [], totalDuration: Duration.zero));
    final selected = state.selectedClip;
    final busy = _busy;
    final totalMs = layout.totalDuration.inMilliseconds.toDouble();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Clip blocks positioned via layout (supporting transition overlaps)
        Positioned.fill(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < layout.segments.length; i++)
                () {
                  final seg = layout.segments[i];
                  final left = totalMs <= 0 ? 0.0 : (seg.projectStart.inMilliseconds / totalMs).clamp(0.0, 1.0) * widget.width;
                  final w = totalMs <= 0 ? widget.width : (seg.effectiveDuration.inMilliseconds / totalMs).clamp(0.0, 1.0) * widget.width;
                  return Positioned(
                    left: left,
                    width: w,
                    top: 0,
                    bottom: 0,
                    child: ValueListenableBuilder<Map<String, List<String>>>(
                      valueListenable: state.thumbnailStrips,
                      builder: (context, strips, _) => TimelineClipBlock(
                        key: ValueKey(seg.clip.id),
                        clip: seg.clip,
                        index: state.clips.indexOf(seg.clip),
                        selected: !_reordering && seg.clip.id == selected?.id,
                        thumbnails: strips[seg.clip.sourcePath] ?? const [],
                        dragging: _reordering && i == _dragCurrent,
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ),

        // Dim outside the selected clip's range
        if (selected != null && !_reordering) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _selectedEdgeFraction(state, isStart: true) * widget.width,
            child: _Dim(
              width: _selectedEdgeFraction(state, isStart: true) * widget.width,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width:
                (1 - _selectedEdgeFraction(state, isStart: false)) * widget.width,
            child: _Dim(
              width:
                  (1 - _selectedEdgeFraction(state, isStart: false)) * widget.width,
            ),
          ),
        ],

        // Scrub + reorder gestures (disabled while busy)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _busy
                ? null
                : (details) {
                    final position = _positionAt(details.localPosition.dx);
                    final clip = state.clipAtProjectTime(position);
                    if (clip != null) state.selectClip(clip.id);
                    state.seekTo(position);
                  },
            onHorizontalDragStart: _busy ? null : (_) {},
            onHorizontalDragUpdate:
                _busy ? null : (details) {
                  final x = (details.localPosition.dx).clamp(0.0, widget.width);
                  state.seekTo(_positionAt(x));
                },
            onLongPressStart: _busy ? null : _startReorder,
            onLongPressMoveUpdate: _updateReorder,
            onLongPressEnd: (_) => _endReorder(),
            onLongPressCancel: _cancelReorder,
          ),
        ),

        // Playhead lives on the OUTER stack so it sweeps the text and
        // audio lanes too.

        // Transition markers sit ABOVE the scrub layer so their taps open
        // the transition sheet instead of scrubbing.
        if (!busy && !_reordering && state.project != null) ...[
          for (var i = 0; i < state.project!.layout.segments.length - 1; i++)
            if ((state.transitionAfter(order[i].id)?.isActive ?? false) &&
                state.project!.layout.segments[i].overlapAfter >
                    Duration.zero)
              Positioned(
                left: (fractionOfSeam(state.project!.layout, i) * widget.width - 26)
                    .clamp(0.0, (widget.width - 52).clamp(0.0, double.infinity)),
                top: 2,
                child: TransitionMarker(
                  effective:
                      state.project!.layout.segments[i].overlapAfter,
                  onTap: () {
                    state.selectClip(order[i].id);
                    showTransitionSheet(context);
                  },
                ),
              ),
        ],

        // Trim handles for the selected clip
        if (!busy &&
            selected != null &&
            !_reordering &&
            state.selectedIndex >= 0) ...[
          _TrimHandle(
            state: state,
            width: widget.width,
            fraction: _selectedEdgeFraction(state, isStart: true),
            isStart: true,
          ),
          _TrimHandle(
            state: state,
            width: widget.width,
            fraction: _selectedEdgeFraction(state, isStart: false),
            isStart: false,
          ),
        ],
      ],
    );
  }

  double _selectedEdgeFraction(EditorState state, {required bool isStart}) {
    final selected = state.selectedClip;
    if (selected == null) return 0;
    final layout = state.project?.layout;
    if (layout == null) return 0;
    final totalMs = layout.totalDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) return 0;

    final segIndex = state.selectedIndex;
    if (segIndex < 0 || segIndex >= layout.segments.length) return 0;
    final seg = layout.segments[segIndex];

    final edge = isStart ? seg.projectStart : seg.coveredEnd;
    return (edge.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }
}

class _Dim extends StatelessWidget {
  const _Dim({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    if (width <= 0) return const SizedBox.shrink();
    return ColoredBox(color: Colors.black.withValues(alpha: .6));
  }
}

class _TrimHandle extends StatefulWidget {
  const _TrimHandle({
    required this.state,
    required this.width,
    required this.fraction,
    required this.isStart,
  });

  final EditorState state;
  final double width;
  final double fraction;
  final bool isStart;

  @override
  State<_TrimHandle> createState() => _TrimHandleState();
}

class _TrimHandleState extends State<_TrimHandle> {
  static const double hitWidth = 28;

  late EditorState state;
  late double width;
  late double fraction;
  late bool isStart;

  bool _snapshotPushed = false;

  @override
  void initState() {
    super.initState();
    _sync(widget);
  }

  @override
  void didUpdateWidget(_TrimHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(widget);
  }

  void _sync(_TrimHandle w) {
    state = w.state;
    width = w.width;
    fraction = w.fraction;
    isStart = w.isStart;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: (fraction * width - hitWidth / 2)
          .clamp(0.0, (width - hitWidth).clamp(0.0, double.infinity)),
      top: 0,
      bottom: 0,
      width: hitWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _snapshotPushed = false,
        onHorizontalDragUpdate: (details) => _drag(details.delta.dx),
        child: Center(
          child: Container(
            width: 20,
            height: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(7),
              boxShadow: const [
                BoxShadow(blurRadius: 6, color: Colors.black45),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 1.5),
                  width: 10,
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(1),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  void _drag(double dx) {
    if (!state.hasProject) return;
    // One history entry per gesture, pushed only once a real change happens.
    if (!_snapshotPushed) {
      state.pushUndoSnapshot();
      _snapshotPushed = true;
    }
    if (width <= 0) return;
    final totalMs = state.totalDuration.inMilliseconds;
    if (totalMs <= 0) return;
    final delta = Duration(
      milliseconds: (dx / width * totalMs).round(),
    );

    if (isStart) {
      final newStart = state.trimStart + delta;
      state.setTrim(start: newStart);
      // Project-time targets: the clip's OUTPUT footprint edges.
      state.seekTo(state.selectedClipStart);
    } else {
      final newEnd = state.trimEnd + delta;
      state.setTrim(end: newEnd);
      state.seekTo(
        state.selectedClipStart + state.selectedClip!.effectiveDuration,
      );
    }
  }
}
