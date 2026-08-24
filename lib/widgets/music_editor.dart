import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../models/audio_track.dart';
import '../models/video_project.dart';
import '../state/editor_state.dart';

/// Background-music bottom sheet: pick/replace the audio file, tune its
/// volume and inspect the placement. Structural actions (add/replace/
/// remove) commit their own undo entries immediately; the volume slider
/// mutates live and collapses into ONE history entry on Done.
Future<void> showMusicSheet(BuildContext context) {
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
      child: const _MusicSheet(),
    ),
  );
}

class _MusicSheet extends StatefulWidget {
  const _MusicSheet();

  @override
  State<_MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<_MusicSheet> {
  /// Project state when the sheet opened — basis for the volume undo entry.
  VideoProject? _baseline;

  /// Volume at open time, for the change check on close.
  double _baselineVolume = 1.0;

  /// True once add/replace/remove ran this session; those actions record
  /// their own history, so Done must not double-book the baseline.
  bool _structuralChange = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<EditorState>();
    _baseline = state.project?.copy();
    _baselineVolume = state.project?.musicTrack?.volume ?? 1.0;
  }

  void _commitVolumeIfChanged() {
    if (_structuralChange || _baseline == null) return;
    final state = context.read<EditorState>();
    final track = state.project?.musicTrack;
    if (track == null || track.volume == _baselineVolume) return;
    state.insertUndoSnapshot(_baseline!);
  }

  Future<void> _pickAudio() async {
    final state = context.read<EditorState>();
    final ok = await state.addMusicFromPicker();
    if (!mounted) return;
    setState(() {
      if (ok) _structuralChange = true;
    });
    _surfaceError();
  }

  void _remove() {
    final state = context.read<EditorState>();
    state.removeMusic();
    if (!mounted) return;
    setState(() => _structuralChange = true);
    _surfaceError();
  }

  void _surfaceError() {
    final state = context.read<EditorState>();
    final error = state.actionError;
    if (error == null) return;
    state.clearActionError();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final busy =
        state.isLoadingProject || state.exportPhase == ExportPhase.exporting;
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
            Text('Background Music',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: busy ? null : _pickAudio,
              icon: const Icon(Icons.library_music_rounded, size: 20),
              label:
                  Text(track == null ? 'Select Audio File' : 'Replace Audio File'),
            ),
            if (track != null) ...[
              const SizedBox(height: 16),
              _InfoRow(icon: Icons.music_note_rounded, label: track.name,
                  strong: true),
              _InfoRow(
                icon: Icons.timer_outlined,
                label: 'Start ${formatClock(track.timelineStart)}'
                    ' · Length '
                    '${formatClock(effectiveMusicLength(track, state.totalDuration))}',
              ),
              _InfoRow(
                icon: track.volume <= 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                label: 'Volume ${(track.volume * 100).round()}%',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.volume_down_rounded,
                      size: 20, color: Colors.white54),
                  Expanded(
                    child: Slider(
                      value: track.volume.clamp(0.0, 1.0),
                      onChanged:
                          busy ? null : (value) => state.setMusicVolumeLive(value),
                    ),
                  ),
                  const Icon(Icons.volume_up_rounded,
                      size: 20, color: Colors.white54),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : _remove,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF87171),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Remove Music'),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Text(
                'Pick a song from your device. It plays over the timeline '
                'and is mixed into the exported file.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: .5),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                _commitVolumeIfChanged();
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Music window actually audible on this timeline: the track is clipped
/// when it runs past the end of the project.
Duration effectiveMusicLength(AudioTrack track, Duration total) {
  final available = total - track.timelineStart;
  if (available.isNegative) return Duration.zero;
  return track.sourceDuration > available ? available : track.sourceDuration;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: strong ? 14 : 13,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                color: Colors.white.withValues(alpha: strong ? .95 : .55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
