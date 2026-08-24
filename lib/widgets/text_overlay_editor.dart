import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../models/text_overlay.dart';
import '../models/video_project.dart';
import '../state/editor_state.dart';

/// Full-screen-ish editor for one text overlay. Every control mutates the
/// overlay LIVE (visible on the preview immediately, including dragging on
/// the video); Apply collapses the session into a single undo entry and
/// dismissing without Apply reverts to the state at open time.
Future<void> showTextOverlayEditor(
  BuildContext context,
  TextOverlay overlay,
) {
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
      child: _TextOverlayEditor(overlayId: overlay.id),
    ),
  );
}

class _TextOverlayEditor extends StatefulWidget {
  const _TextOverlayEditor({required this.overlayId});

  final String overlayId;

  @override
  State<_TextOverlayEditor> createState() => _TextOverlayEditorState();
}

class _TextOverlayEditorState extends State<_TextOverlayEditor> {
  late TextEditingController _textController;
  VideoProject? _baseline;
  TextOverlay? _initial;

  @override
  void initState() {
    super.initState();
    final state = context.read<EditorState>();
    _initial = _find(state);
    _baseline = state.project?.copy();
    state.setTextEditingSession(true);
    state.selectText(widget.overlayId);
    _textController = TextEditingController(text: _initial?.text ?? '');
  }

  @override
  void dispose() {
    // Session flag must clear even when the sheet is dismissed by drag.
    final state = context.read<EditorState>();
    if (state.textEditingSession) {
      state.setTextEditingSession(false);
    }
    _textController.dispose();
    super.dispose();
  }

  TextOverlay? _find(EditorState state) {
    for (final o in state.project?.textOverlays ?? const <TextOverlay>[]) {
      if (o.id == widget.overlayId) return o;
    }
    return null;
  }

  void _update(TextOverlay current, TextOverlay Function(TextOverlay) edit) {
    context.read<EditorState>().updateTextOverlayLive(edit(current));
  }

  bool _changed(TextOverlay? now) {
    final initial = _initial;
    if (now == null || initial == null) return false;
    return now.text != initial.text ||
        now.fontSize != initial.fontSize ||
        now.alignment != initial.alignment ||
        now.bold != initial.bold ||
        now.color != initial.color ||
        now.background != initial.background ||
        now.x != initial.x ||
        now.y != initial.y ||
        now.startTime != initial.startTime ||
        now.endTime != initial.endTime;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final overlay = _find(state);

    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    final total = state.totalDuration;
    final stepMs = 500;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _revertAndClose(context, overlay);
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
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
                TextField(
                  controller: _textController,
                  maxLines: 2,
                  autofocus: overlay.text == 'Text',
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Enter your text…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => _update(
                    overlay,
                    (o) => o.copyWith(text: value.trim().isEmpty ? ' ' : value),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tip: drag the text on the video preview to move it.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: .45),
                  ),
                ),
                const SizedBox(height: 14),

                _SectionLabel('Font size'),
                Row(
                  children: [
                    Slider(
                      value: overlay.fontSize
                          .clamp(AppConstants.minTextFontSize,
                              AppConstants.maxTextFontSize),
                      min: AppConstants.minTextFontSize,
                      max: AppConstants.maxTextFontSize,
                      onChanged: (value) =>
                          _update(overlay, (o) => o.copyWith(fontSize: value)),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(overlay.fontSize * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),

                _SectionLabel('Style'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final align in const [
                      TextAlign.left,
                      TextAlign.center,
                      TextAlign.right,
                    ])
                      ChoiceChip(
                        label: Icon(_alignIcon(align), size: 18),
                        selected: overlay.alignment == align,
                        onSelected: (_) => _update(
                          overlay,
                          (o) => o.copyWith(alignment: align),
                        ),
                      ),
                    FilterChip(
                      label: const Icon(Icons.format_bold_rounded, size: 18),
                      selected: overlay.bold,
                      onSelected: (value) =>
                          _update(overlay, (o) => o.copyWith(bold: value)),
                    ),
                    FilterChip(
                      label: const Icon(Icons.shield_rounded, size: 18),
                      tooltip: 'Background box',
                      selected: overlay.background,
                      onSelected: (value) =>
                          _update(overlay, (o) => o.copyWith(background: value)),
                    ),
                  ],
                ),

                _SectionLabel('Color'),
                Row(
                  children: [
                    for (final color in OverlayTextColor.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _ColorSwatch(
                          hex: color.hex,
                          selected: overlay.color == color,
                          onTap: () => _update(
                            overlay,
                            (o) => o.copyWith(color: color),
                          ),
                        ),
                      ),
                  ],
                ),

                _SectionLabel('Timing'),
                Row(
                  children: [
                    Expanded(
                      child: _TimeStepper(
                        label: 'Start',
                        value: formatClock(overlay.startTime),
                        canDecrease: overlay.startTime >=
                            Duration(milliseconds: stepMs),
                        canIncrease:
                            overlay.endTime - overlay.startTime >
                                Duration(milliseconds: stepMs + 200),
                        onDecrease: () => _shiftStart(overlay, -stepMs, total),
                        onIncrease: () => _shiftStart(overlay, stepMs, total),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeStepper(
                        label: 'End',
                        value: formatClock(overlay.endTime),
                        canDecrease: overlay.endTime - overlay.startTime >
                            Duration(milliseconds: stepMs + 200),
                        canIncrease: overlay.endTime <= total,
                        onDecrease: () => _shiftEnd(overlay, -stepMs, total),
                        onIncrease: () => _shiftEnd(overlay, stepMs, total),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF87171),
                      ),
                      onPressed: () {
                        // deleteSelectedText records its own undo entry.
                        context.read<EditorState>().deleteSelectedText();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final snapshot = _baseline;
                          if (_changed(overlay) && snapshot != null) {
                            context
                                .read<EditorState>()
                                .insertUndoSnapshot(snapshot);
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
        ),
      ),
    );
  }

  void _revertAndClose(BuildContext context, TextOverlay current) {
    final state = context.read<EditorState>();
    final initial = _initial;
    if (initial != null && _changed(current)) {
      state.updateTextOverlayLive(initial);
    }
    Navigator.of(context).pop();
  }

  void _shiftStart(TextOverlay overlay, int deltaMs, Duration total) {
    final delta = Duration(milliseconds: deltaMs);
    var start = overlay.startTime + delta;
    if (start.isNegative) start = Duration.zero;
    if (start > total) start = total;
    if (overlay.endTime - start < const Duration(milliseconds: 300)) return;
    _update(overlay, (o) => o.copyWith(startTime: start));
  }

  void _shiftEnd(TextOverlay overlay, int deltaMs, Duration total) {
    final delta = Duration(milliseconds: deltaMs);
    var end = overlay.endTime + delta;
    if (end.isNegative) end = Duration.zero;
    if (end > total) end = total;
    if (end - overlay.startTime < const Duration(milliseconds: 300)) return;
    _update(overlay, (o) => o.copyWith(endTime: end));
  }
}

IconData _alignIcon(TextAlign align) => switch (align) {
      TextAlign.left => Icons.format_align_left_rounded,
      TextAlign.right => Icons.format_align_right_rounded,
      _ => Icons.format_align_center_rounded,
    };

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: .4,
          color: Colors.white.withValues(alpha: .5),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse('FF$hex', radix: 16));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppTheme.accent : Colors.white24,
            width: selected ? 3 : 1.5,
          ),
        ),
      ),
    );
  }
}

class _TimeStepper extends StatelessWidget {
  const _TimeStepper({
    required this.label,
    required this.value,
    required this.canIncrease,
    required this.canDecrease,
    required this.onIncrease,
    required this.onDecrease,
  });

  final String label;
  final String value;
  final bool canIncrease;
  final bool canDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: .45),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: canDecrease ? onDecrease : null,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: canIncrease ? onIncrease : null,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
