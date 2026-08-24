import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/time_utils.dart';

/// Small ✚ pill rendered over a transition seam in the timeline. Tapping it
/// opens the transition sheet for the seam's LEFT clip. Hidden entirely when
/// the overlap resolves to zero so hard cuts stay visually clean.
class TransitionMarker extends StatelessWidget {
  const TransitionMarker({
    super.key,
    required this.effective,
    this.onTap,
  });

  final Duration effective;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (effective <= Duration.zero) return const SizedBox.shrink();
    return Tooltip(
      message: 'Transition · ${formatClock(effective)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.accent, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.merge_rounded,
                  size: 11, color: AppTheme.accent),
              const SizedBox(width: 3),
              Text(
                formatClock(effective),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
