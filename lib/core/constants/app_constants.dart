abstract final class AppConstants {
  /// Minimum selectable trim window so start/end handles cannot collapse.
  static const Duration minTrimGap = Duration(milliseconds: 300);

  /// Minimum length of any clip after a split or trim operation.
  static const Duration minClipDuration = Duration(milliseconds: 100);

  /// Number of snapshots kept in the undo/redo history.
  static const int historyLimit = 30;

  /// How many distinct source videos stay initialized for preview at once.
  static const int previewControllerPoolSize = 3;

  /// Roughly one filmstrip frame per this much source footage.
  static const int thumbnailIntervalMs = 1000;

  /// Upper bound of frames extracted per source video.
  static const int thumbnailMaxPerSource = 120;

  static const int thumbnailMinPerSource = 14;

  static const int thumbnailMaxWidth = 160;

  static const int thumbnailQuality = 80;

  static const String exportsDirName = 'exports';

  static const String galleryAlbum = 'Video Editor';

  static const String videoCodecPreset = 'veryfast';

  static const String audioBitrate = '128k';

  // -- Phase 3: speed ---------------------------------------------------------

  static const double minPlaybackSpeed = 0.25;

  static const double maxPlaybackSpeed = 2.0;

  /// Presets offered by the speed selector, in order.
  static const List<double> speedPresets = [
    0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0,
  ];

  // -- Phase 3: text overlays ---------------------------------------------------

  /// Font size is stored as a fraction of the video height so it scales
  /// across resolutions; these bound that fraction.
  static const double defaultTextFontSize = 0.06;

  static const double minTextFontSize = 0.02;

  static const double maxTextFontSize = 0.30;

  /// Window given to a freshly inserted overlay, clamped to the timeline.
  static const Duration defaultTextOverlayDuration = Duration(seconds: 4);

  // -- Phase 3: audio ------------------------------------------------------------

  static const double maxAudioVolume = 1.0;

  /// Slack allowed between the music player and the expected position
  /// before a corrective seek is issued during preview.
  static const Duration musicSyncTolerance = Duration(milliseconds: 180);

  // -- Phase 4: transitions ------------------------------------------------------

  static const Duration defaultTransitionDuration = Duration(milliseconds: 500);

  static const List<Duration> transitionDurationChoices = [
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(milliseconds: 750),
    Duration(seconds: 1),
    Duration(milliseconds: 1500),
    Duration(seconds: 2),
  ];

  /// Largest overlap a boundary supports: half the shorter neighbour's
  /// OUTPUT duration so neither side collapses into the transition.
  static Duration maxTransitionDuration(Duration leftEff, Duration rightEff) {
    final shorter = leftEff < rightEff ? leftEff : rightEff;
    return Duration(milliseconds: shorter.inMilliseconds ~/ 2);
  }

  // -- Phase 4: aspect ratio -----------------------------------------------------

  /// null means "derive from the first clip". Values are 'w:h' strings.
  static const List<String?> aspectRatioChoices = [
    null,
    '16:9',
    '9:16',
    '1:1',
    '4:3',
    '3:4',
  ];

  /// Minimum crop window size as a fraction of the source frame.
  static const double minCropFraction = 0.1;
}
