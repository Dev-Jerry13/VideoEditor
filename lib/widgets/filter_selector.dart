import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/ffmpeg_filters.dart';
import '../models/video_adjustments.dart';
import '../models/video_filter.dart';
import '../models/video_project.dart';
import '../state/editor_state.dart';

/// Look-preset bottom sheet for the SELECTED clip. Tapping a preset
/// applies it live through the same color matrix the preview composites,
/// so what you see is what exports (± documented approximation, plan §29).
Future<void> showFilterSheet(BuildContext context) {
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
      child: const _FilterSheet(),
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _clipId;
  VideoFilter _initial = VideoFilter.none;
  VideoProject? _baseline;

  @override
  void initState() {
    super.initState();
    final state = context.read<EditorState>();
    _clipId = state.selectedClip?.id;
    _initial = state.selectedClip?.filter ?? VideoFilter.none;
    _baseline = state.project?.copy();
  }

  VideoFilter? _currentFilter(EditorState state) {
    final id = _clipId;
    if (id == null) return null;
    for (final c in state.clips) {
      if (c.id == id) return c.filter;
    }
    return null;
  }

  void _revert() {
    final id = _clipId;
    if (id == null) return;
    context.read<EditorState>().updateFilterLive(id, _initial);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final filter = _currentFilter(state);
    if (_clipId == null || filter == null) {
      Navigator.of(context).maybePop();
      return const SizedBox.shrink();
    }
    final changed = filter != _initial;

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
            Text('Filters', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.9,
              children: [
                for (final candidate in VideoFilter.values)
                  _FilterTile(
                    filter: candidate,
                    selected: candidate == filter,
                    onTap: () => state.updateFilterLive(_clipId!, candidate),
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
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final VideoFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppTheme.accent : Colors.white24,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: ColorFiltered(
                  // The SAME matrix family the preview/export derive from.
                  colorFilter: ColorFilter.matrix(
                    FfmpegFilters.previewColorMatrix(filter, neutral),
                  ),
                  child: const _SampleImage(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filter.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: selected ? AppTheme.accent : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  static const neutral = VideoAdjustments.neutral;
}

/// A tiny synthetic scene (sunset gradient + sun + ground) so every preset
/// reads clearly without decoding any video frame.
class _SampleImage extends StatelessWidget {
  const _SampleImage();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _SamplePainter(),
      size: Size.square(64),
    );
  }
}

class _SamplePainter extends CustomPainter {
  const _SamplePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Rect.fromLTWH(0, 0, size.width, size.height * 0.7);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF2E5FA3), const Color(0xFFF2A65A)],
        ).createShader(sky),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.7, size.width, size.height * 0.3),
      Paint()..color = const Color(0xFF2E7D46),
    );
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.42),
      size.width * 0.13,
      Paint()..color = const Color(0xFFFFE082),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
