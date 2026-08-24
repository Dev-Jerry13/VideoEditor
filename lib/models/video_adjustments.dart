/// Per-clip color adjustments in USER units (−100..100). Conversion to
/// FFmpeg's ranges lives in the filter builder, never here — the UI works
/// exclusively with these values.
class VideoAdjustments {
  const VideoAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.temperature = 0,
  });

  static const VideoAdjustments neutral = VideoAdjustments();

  /// Range guard shared by the model and every live setter.
  static const double min = -100;
  static const double max = 100;

  final double brightness;
  final double contrast;
  final double saturation;
  final double temperature;

  bool get isNeutral =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      temperature == 0;

  static double clamp(double value) => value.clamp(min, max);

  VideoAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? temperature,
  }) {
    return VideoAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoAdjustments &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.temperature == temperature;

  @override
  int get hashCode =>
      Object.hash(brightness, contrast, saturation, temperature);
}
