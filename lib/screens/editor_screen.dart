import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../state/editor_state.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/export_progress.dart';
import '../widgets/video_preview.dart';
import '../widgets/video_timeline.dart';

class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const EditorScreen());
  }

  @override
  Widget build(BuildContext context) {
    final canLeave =
        context.select((EditorState s) => s.exportPhase) != ExportPhase.exporting;

    return PopScope(
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          context.read<EditorState>().closeProject();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cancel or wait for the export to finish first.'),
          ),
        );
      },
      child: _ActionErrorSnackbars(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Video Editor'),
            actions: [
              Builder(
                builder: (context) {
                  final hasProject =
                      context.select((EditorState s) => s.hasProject);
                  final exporting = context.select((EditorState s) =>
                      s.exportPhase == ExportPhase.exporting);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      onPressed: hasProject && !exporting
                          ? () => showExportSheet(context)
                          : null,
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Export'),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: const [
                Expanded(child: VideoPreview()),
                _SelectedClipInfo(),
                VideoTimeline(height: 208),
                EditorToolbar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows "Clip 2 · 00:07" for the selected clip (plan §3).
class _SelectedClipInfo extends StatelessWidget {
  const _SelectedClipInfo();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final selected = state.selectedClip;
    if (selected == null || state.clips.length < 2) {
      return const SizedBox(height: 4);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.accent.withValues(alpha: .5)),
          ),
          child: Text(
            'Clip ${state.selectedIndex + 1} · ${formatClock(selected.trimmedDuration)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: .85),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// Surfaces asynchronous action failures (picker/probe/controller errors
/// raised outside the toolbar) as snackbars, then clears them.
class _ActionErrorSnackbars extends StatefulWidget {
  const _ActionErrorSnackbars({required this.child});

  final Widget child;

  @override
  State<_ActionErrorSnackbars> createState() => _ActionErrorSnackbarsState();
}

class _ActionErrorSnackbarsState extends State<_ActionErrorSnackbars> {
  String? _consumed;

  @override
  Widget build(BuildContext context) {
    final error = context.select((EditorState s) => s.actionError);
    if (error != null && error != _consumed) {
      _consumed = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
        context.read<EditorState>().clearActionError();
      });
    }
    return widget.child;
  }
}
