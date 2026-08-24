import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../state/editor_state.dart';
import 'editor_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Trim and export your videos,\nright on your device.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .6),
                            height: 1.5,
                          ),
                    ),
                    const SizedBox(height: 40),
                    FilledButton.icon(
                      onPressed:
                          state.isLoadingProject ? null : () => _pick(context),
                      icon: const Icon(Icons.video_library_rounded),
                      label: const Text('Select Video'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your videos never leave your device',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .4),
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (state.isLoadingProject)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Loading video…',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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

  Future<void> _pick(BuildContext context) async {
    final state = context.read<EditorState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final path = await state.pickVideoFile();
    if (path == null) {
      _showErrorIfAny(messenger, state);
      return;
    }

    final opened = await state.openVideo(path);
    if (opened) {
      await navigator.push(EditorScreen.route());
    } else {
      _showError(messenger, state.projectError ?? 'Could not open video.');
    }
  }

  void _showErrorIfAny(ScaffoldMessengerState messenger, EditorState state) {
    final error = state.projectError;
    if (error != null) _showError(messenger, error);
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
