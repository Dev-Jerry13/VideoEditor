/// Look presets applied per clip. Preview uses ColorFilter matrices; export
/// translates each value into FFmpeg filters — both sides live in one
/// mapping table so they cannot drift apart.
enum VideoFilter {
  none('Original'),
  grayscale('Grayscale'),
  warm('Warm'),
  cool('Cool'),
  vintage('Vintage'),
  highContrast('High Contrast'),
  bright('Bright'),
  fade('Fade');

  const VideoFilter(this.label);

  final String label;

  String get code => name;

  static VideoFilter fromCode(String? code) {
    for (final value in VideoFilter.values) {
      if (value.name == code) return value;
    }
    return VideoFilter.none;
  }
}
