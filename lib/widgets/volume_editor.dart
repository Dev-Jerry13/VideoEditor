import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/video_project.dart';
import '../state/editor_state.dart';

/// Volume bottom sheet: original video audio (with mute) and background
/// music side by side. Both sliders mutate live; Done collapses the whole
/// session into a single undo entry.
Future<void> showVolumeSheet(BuildContext context) {
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
      child: const _VolumeSheet(),
    ),
  );
}

class _VolumeSheet extends StatefulWidget {
  const _VolumeSheet();

  @override
  State<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<_VolumeSheet> {
  VideoProject? _baseline;
  double _initialOriginal = 1.0;
  double _initialMusic = 1.0;

  @override
  void initState() {
    super.initState();
    final project = context.read<EditorState>().project;
    _baseline = project?.copy();
    _initialOriginal = project?.originalAudioVolume ?? 1.0;
    _initialMusic = project?.musicTrack?.volume ?? 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final track = state.project?.musicTrack;

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
            Text('Audio Levels',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),

            _SliderBlock(
              icon: Icons.videocam_rounded,
              title: 'Original Audio',
              value: state.project?.originalAudioVolume ?? 1.0,
              mutedLabel: 'Muted',
              onChanged: (value) =>
                  state.setOriginalAudioVolumeLive(value),
            ),

            const SizedBox(height: 14),
            if (track != null)
              _SliderBlock(
                icon: Icons.music_note_rounded,
                title: track.name,
                value: track.volume.clamp(0.0, 1.0),
                mutedLabel: 'Silent',
                onChanged: (value) => state.setMusicVolumeLive(value),
              )
            else
              Row(
                children: [
                  const Icon(Icons.music_off_rounded,
                      size: 18, color: Colors.white38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No background music — add some via the Music tool.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: .4),
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
                      _revert();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final baseline = _baseline;
                      if (baseline == null) return Navigator.of(context).pop();
                      final project = state.project;
                      final original =
                          project?.originalAudioVolume ?? 1.0;
                      final music = project?.musicTrack?.volume ?? 1.0;
                      if (original != _initialOriginal ||
                          music != _initialMusic) {
                        state.insertUndoSnapshot(baseline);
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

  void _revert() {
    final state = context.read<EditorState>();
    state.setOriginalAudioVolumeLive(_initialOriginal);
    final track = state.project?.musicTrack;
    if (track != null && track.volume != _initialMusic) {
      state.setMusicVolumeLive(_initialMusic);
    }
  }
}

class _SliderBlock extends StatelessWidget {
  const _SliderBlock({
    required this.icon,
    required this.title,
    required this.value,
    required this.mutedLabel,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final double value;
  final String mutedLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = value <= 0;
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Text(
              muted ? mutedLabel : '${(value * 100).round()}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: muted
                    ? Colors.white.withValues(alpha: .4)
                    : Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.volume_mute_rounded,
                size: 20, color: Colors.white54),
            Expanded(
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: onChanged,
              ),
            ),
            const Icon(Icons.volume_up_rounded,
                size: 20, color: Colors.white54),
          ],
        ),
      ],
    );
  }
}
