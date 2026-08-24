enum ExportResolution {
  p720('720p', 720),
  p1080('1080p', 1080);

  const ExportResolution(this.label, this.height);

  final String label;

  /// Target height in pixels; export never upscales above the source.
  final int height;
}

enum ExportQuality {
  low('Low', 28),
  medium('Medium', 23),
  high('High', 18);

  const ExportQuality(this.label, this.crf);

  final String label;

  /// x264 constant rate factor; lower value means better quality/larger file.
  final int crf;
}
