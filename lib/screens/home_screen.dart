import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../services/ffmpeg_service.dart';
import '../services/session_service.dart';
import '../state/editor_state.dart';
import 'editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _restoreAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoResume());
  }

  /// Silent auto-resume: if an active (non-expired) session exists, open the
  /// editor on it. Runs exactly once so returning from the editor never
  /// re-triggers it.
  Future<void> _maybeAutoResume() async {
    if (_restoreAttempted) return;
    _restoreAttempted = true;
    if (!mounted) return;
    final state = context.read<EditorState>();
    final navigator = Navigator.of(context);
    final id = await state.restoreActiveSession();
    if (id != null && mounted) {
      await navigator.push(EditorScreen.route());
    }
  }

  Future<void> _pick(BuildContext context) async {
    final state = context.read<EditorState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final path = await state.pickVideoFile();
    if (path == null) {
      _showErrorIfAny(messenger, state);
      return;
    }

    final info = await state.inspectVideoFile(path);
    if (info == null) {
      _showError(messenger, state.projectError ?? 'Could not inspect video.');
      return;
    }
    if (!context.mounted ||
        !await _confirmImport(context, path: path, info: info)) {
      return;
    }

    final opened = await state.openVideo(path);
    if (opened) {
      await navigator.push(EditorScreen.route());
    } else {
      _showError(messenger, state.projectError ?? 'Could not open video.');
    }
  }

  Future<void> _openRecent(BuildContext context, SessionRecord record) async {
    final state = context.read<EditorState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final opened = await state.openRecentSession(record.id);
    if (opened) {
      await navigator.push(EditorScreen.route());
    } else {
      _showError(messenger, 'Could not open this project.');
    }
  }

  void _showErrorIfAny(ScaffoldMessengerState messenger, EditorState state) {
    final error = state.projectError;
    if (error != null) _showError(messenger, error);
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmImport(
    BuildContext context, {
    required String path,
    required MediaInfo info,
  }) async {
    final int size;
    try {
      size = await File(path).length();
    } on FileSystemException {
      if (context.mounted) {
        _showError(
          ScaffoldMessenger.of(context),
          'The selected file is no longer available.',
        );
      }
      return false;
    }
    if (!context.mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ready to edit?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  path.split(Platform.pathSeparator).last,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 16),
                _ImportDetail(
                  label: 'Duration',
                  value: formatClock(info.duration),
                ),
                _ImportDetail(
                  label: 'Resolution',
                  value: '${info.width} × ${info.height}',
                ),
                _ImportDetail(
                  label: 'Audio',
                  value: info.hasAudio ? 'Included' : 'No audio track',
                ),
                _ImportDetail(
                  label: 'File size',
                  value: _formatFileSize(size),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A local draft copy will be created so you can resume this '
                  'edit later.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Choose another'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open editor'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.accent,
                          AppTheme.accent.withValues(alpha: .55),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.movie_creation_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Video Editor',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create multi-clip videos with trims, music, text,\n'
                    'transitions, and on-device export.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .6),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: state.isLoadingProject
                        ? null
                        : () => _pick(context),
                    icon: const Icon(Icons.video_library_rounded),
                    label: const Text('Select Video'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Start with an MP4 or MOV video. Your edits are saved '
                    'on this device as a draft.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .55),
                      height: 1.4,
                    ),
                  ),
                  ValueListenableBuilder<List<SessionRecord>>(
                    valueListenable: state.recentSessions,
                    builder: (context, sessions, _) {
                      if (sessions.isEmpty) return const SizedBox.shrink();
                      return _RecentSection(
                        sessions: sessions,
                        onOpen: (r) => _openRecent(context, r),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (state.isLoadingProject || state.isRestoring)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading…'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImportDetail extends StatelessWidget {
  const _ImportDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.sessions, required this.onOpen});

  final List<SessionRecord> sessions;
  final ValueChanged<SessionRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<EditorState>();
    return Container(
      margin: const EdgeInsets.only(top: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recent',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface.withValues(alpha: .75),
                ),
              ),
              const Spacer(),
              Text(
                '${sessions.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final record in sessions) ...[
            _RecentTile(
              record: record,
              onTap: () => onOpen(record),
              onDelete: () => state.deleteRecentSession(record.id),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  final SessionRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final poster = record.posterPath;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: poster != null && poster.isNotEmpty
                    ? Image.file(
                        File(poster),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _thumbFallback(theme),
                      )
                    : _thumbFallback(theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.clipCount} clip${record.clipCount == 1 ? '' : 's'} · ${timeAgo(record.lastOpenedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: .5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: theme.colorScheme.onSurface.withValues(alpha: .5),
                tooltip: 'Remove',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback(ThemeData theme) => Container(
    width: 56,
    height: 56,
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.videocam_rounded,
      color: theme.colorScheme.onSurface.withValues(alpha: .35),
    ),
  );
}
