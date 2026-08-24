import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

import '../core/theme/app_theme.dart';
import '../models/export_settings.dart';
import '../services/save_destination_service.dart';
import '../state/editor_state.dart';

Future<void> showExportSheet(BuildContext context) {
  final state = context.read<EditorState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => ChangeNotifierProvider<EditorState>.value(
      value: state,
      child: const _ExportSheet(),
    ),
  );
}

class _ExportSheet extends StatelessWidget {
  const _ExportSheet();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: context.select(
        (EditorState s) => s.exportPhase != ExportPhase.exporting,
      ),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) context.read<EditorState>().dismissExportSheet();
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Consumer<EditorState>(
          builder: (context, state, _) {
            switch (state.exportPhase) {
              case ExportPhase.idle:
                return const _SettingsForm();
              case ExportPhase.exporting:
                return const _ProgressView();
              case ExportPhase.success:
                return const _SuccessView();
              case ExportPhase.failed:
                return const _ErrorView();
            }
          },
        ),
      ),
    );
  }
}

// -- Settings ------------------------------------------------------------------

class _SettingsForm extends StatefulWidget {
  const _SettingsForm();

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  ExportResolution _resolution = ExportResolution.p1080;
  ExportQuality _quality = ExportQuality.medium;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

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
            Text('Export Video', style: textTheme.titleLarge),
            const SizedBox(height: 20),
            Text('Resolution',
                style: textTheme.labelLarge
                    ?.copyWith(color: Colors.white70)),
            const SizedBox(height: 8),
            ...ExportResolution.values.map(
              (r) => _OptionRow(
                title: r.label,
                selected: _resolution == r,
                onTap: () => setState(() => _resolution = r),
              ),
            ),
            const SizedBox(height: 16),
            Text('Quality',
                style: textTheme.labelLarge
                    ?.copyWith(color: Colors.white70)),
            const SizedBox(height: 8),
            ...ExportQuality.values.map(
              (q) => _OptionRow(
                title: q.label,
                selected: _quality == q,
                onTap: () => setState(() => _quality = q),
              ),
            ),
            const SizedBox(height: 16),
            Text('Save to',
                style: textTheme.labelLarge
                    ?.copyWith(color: Colors.white70)),
            const SizedBox(height: 8),
            ..._buildDestinationRows(context),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.read<EditorState>().startExport(
                    resolution: _resolution,
                    quality: _quality,
                  ),
              child: const Text('Export Video'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDestinationRows(BuildContext context) {
    final state = context.watch<EditorState>();

    return [
      _OptionRow(
        title: 'Gallery',
        subtitle: 'Auto-save to your photo library',
        selected: state.saveDestination == SaveDestination.gallery,
        onTap: () => context
            .read<EditorState>()
            .setSaveDestination(SaveDestination.gallery),
      ),
      _OptionRow(
        title: 'Device folder',
        subtitle: state.savedFolderName ?? 'Choose a folder…',
        selected: state.saveDestination == SaveDestination.folder,
        trailing:
            state.saveDestination == SaveDestination.folder &&
                    state.savedFolderName != null
                ? TextButton(
                  onPressed: () =>
                      context.read<EditorState>().chooseSaveFolder(),
                  child: const Text('Change'),
                )
                : null,
        onTap: () => context
            .read<EditorState>()
            .setSaveDestination(SaveDestination.folder),
      ),
      _OptionRow(
        title: 'Ask every time',
        subtitle: 'Pick a location after each export',
        selected: state.saveDestination == SaveDestination.askEveryTime,
        onTap: () => context
            .read<EditorState>()
            .setSaveDestination(SaveDestination.askEveryTime),
      ),
    ];
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color:
                  selected ? AppTheme.accent : Colors.white38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: .4),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

// -- Progress ------------------------------------------------------------------

class _ProgressView extends StatelessWidget {
  const _ProgressView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: context.read<EditorState>().exportProgressValue,
              builder: (context, progress, _) => Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 0.999),
                      minHeight: 10,
                      backgroundColor: AppTheme.surfaceRaised,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(progress * 100).floor()}%',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<String?>(
              valueListenable: context.read<EditorState>().exportStageNotifier,
              builder: (context, stage, _) => Text(stage ?? 'Exporting…'),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => context.read<EditorState>().cancelExport(),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Success -------------------------------------------------------------------

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final result = state.lastExport;
    final delivery = state.lastDelivery;

    final statusText = switch (delivery?.status) {
      DeliveryStatus.saved => 'Saved to ${delivery!.locationLabel ?? 'app storage'}',
      DeliveryStatus.cancelled =>
        'Not saved yet — the file stays in app storage',
      DeliveryStatus.failed =>
        "Couldn't save to the selected location. Try again or use Share.",
      null => 'Saved to app storage',
    };
    final needsRetry =
        delivery == null ||
        delivery.status != DeliveryStatus.saved;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF34D399), size: 64),
            const SizedBox(height: 12),
            Text('Export complete',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: .6)),
            ),
            if (result != null) ...[
              const SizedBox(height: 4),
              Text(
                result.fileName,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: .35),
                ),
              ),
            ],
            if (needsRetry && result != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.read<EditorState>().redeliver(),
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: const Text('Save Again'),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: result == null
                        ? null
                        : () => _share(context, result.outputPath),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: result == null
                        ? null
                        : () => _openPreview(context, result.outputPath),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Preview'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Sharing is not available right now.')),
      );
    }
  }

  void _openPreview(BuildContext context, String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ExportedVideoPage(path: path),
      ),
    );
  }
}

class _ExportedVideoPage extends StatefulWidget {
  const _ExportedVideoPage({required this.path});

  final String path;

  @override
  State<_ExportedVideoPage> createState() => _ExportedVideoPageState();
}

class _ExportedVideoPageState extends State<_ExportedVideoPage> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _controller.play();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Preview'),
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: GestureDetector(
                  onTap: () async {
                    if (_controller.value.isPlaying) {
                      await _controller.pause();
                    } else {
                      await _controller.play();
                    }
                  },
                  child: VideoPlayer(_controller),
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

// -- Error ---------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView();

  @override
  Widget build(BuildContext context) {
    final error =
        context.select((EditorState s) => s.exportError ?? 'Export failed.');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFF87171), size: 56),
            const SizedBox(height: 12),
            Text('Export failed',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              error.split('\n').first,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: .65)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        context.read<EditorState>().dismissExportSheet(),
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        context.read<EditorState>().dismissExportSheet(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try Again'),
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
