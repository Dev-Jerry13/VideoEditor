import '../core/constants/app_constants.dart';

/// Visual transition applied at the boundary AFTER a specific clip.
///
/// Transitions OVERLAP their two neighbours (xfade semantics): the
/// following clip starts [duration] before the previous one ends, which
/// shortens the project timeline accordingly.
enum TransitionType {
  none('None'),
  fade('Fade'),
  dissolve('Dissolve'),
  black('Black'),
  white('White'),
  slideLeft('Slide Left'),
  slideRight('Slide Right'),
  zoom('Zoom');

  const TransitionType(this.label);

  final String label;
}

class ClipTransition {
  /// Stored durations are trusted to come from [AppConstants.transitionDurationChoices];
  /// anything impossible is clamped at resolve time, so construction stays const.
  const ClipTransition({
    required this.type,
    this.duration = AppConstants.defaultTransitionDuration,
  });

  static const ClipTransition none = ClipTransition(type: TransitionType.none);

  final TransitionType type;

  /// Stored raw; the timeline resolver CLAMPS it against what the adjacent
  /// clips can support so every consumer sees the same effective value.
  final Duration duration;

  bool get isActive => type != TransitionType.none;

  /// Effective overlap after clamping to the neighbours' capacity.
  Duration effectiveFor(Duration leftEff, Duration rightEff) {
    if (!isActive) return Duration.zero;
    final maxAllowed = AppConstants.maxTransitionDuration(leftEff, rightEff);
    return duration > maxAllowed ? maxAllowed : duration;
  }

  ClipTransition copyWith({
    TransitionType? type,
    Duration? duration,
  }) {
    return ClipTransition(
      type: type ?? this.type,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClipTransition &&
      other.type == type &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(type, duration);
}
