import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../state/editor_state.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/export_progress.dart';
import '../widgets/video_preview.dart';
import '../widgets/video_timeline.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const EditorScreen());
  }

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const _guidancePreferenceKey = 'editor.guidanceSeen.v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showFirstUseGuidance(),
    );
  }

  Future<void> _showFirstUseGuidance() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted || preferences.getBool(_guidancePreferenceKey) == true) {
        return;
      }
      await preferences.setBool(_guidancePreferenceKey, true);
      if (mounted) await _showGuidance(context);
    } catch (_) {
      // Preference storage is non-essential; a missing platform channel must
      // never prevent the editor from opening.
    }
  }

  Future<void> _showGuidance(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.tips_and_updates_outlined),
      title: const Text('Quick editing guide'),
      content: const Text(
        '1. Tap a clip to select it.\n'
        '2. Drag the playhead to seek; drag trim handles to set its range.\n'
        '3. Long-press and drag a clip to reorder it.\n\n'
        'Use Undo after any edit, then choose Export when your timeline is ready.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  Future<void> _renameProject(BuildContext context) async {
    final state = context.read<EditorState>();
    final controller = TextEditingController(text: state.projectName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
          decoration: const InputDecoration(labelText: 'Project name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && context.mounted) state.renameProject(name);
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
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.select((EditorState s) => s.projectName)),
                if (context.select((EditorState s) => s.isSavingProject))
                  const Text('Saving…', style: TextStyle(fontSize: 11)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Rename project',
                onPressed: () => _renameProject(context),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline_rounded),
                tooltip: 'Editing help',
                onPressed: () => _showGuidance(context),
              ),
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
