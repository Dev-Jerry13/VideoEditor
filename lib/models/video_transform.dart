/// Visual geometry settings for a clip: crop window, rotation and flips.
///
/// Everything is stored NORMALIZED (fractions of the source frame) so the
/// same values drive the Flutter preview and the FFmpeg export at any
/// resolution.
enum Rotation {
  none(0),
  clockwise90(1),
  clockwise180(2),
  clockwise270(3);

  const Rotation(this.quarterTurns);

  /// Number of 90° clockwise turns — drives both RotatedBox and the count
  /// of FFmpeg `transpose` filters.
  final int quarterTurns;

  /// Whether rotating swaps width and height (odd number of quarter turns).
  bool get swapsDimensions => quarterTurns.isOdd;
}

class CropSettings {
  const CropSettings({
    this.left = 0,
    this.top = 0,
    this.right = 1,
    this.bottom = 1,
  }) : assert(left >= 0 && left <= 1, 'left must be normalized'),
       assert(top >= 0 && top <= 1, 'top must be normalized'),
       assert(right > left, 'right must be greater than left'),
       assert(bottom > top, 'bottom must be greater than top');

  /// The untouched frame.
  static const CropSettings full = CropSettings();

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  static CropSettings fromJson(Map<String, dynamic> json) => CropSettings(
    left: (json['left'] as num?)?.toDouble() ?? 0,
    top: (json['top'] as num?)?.toDouble() ?? 0,
    right: (json['right'] as num?)?.toDouble() ?? 1,
    bottom: (json['bottom'] as num?)?.toDouble() ?? 1,
  );

  double get widthFraction => right - left;

  double get heightFraction => bottom - top;

  bool get isIdentity => left == 0 && top == 0 && right == 1 && bottom == 1;

  CropSettings copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    return CropSettings(
      left: left ?? this.left,
      top: top ?? this.top,
      right: right ?? this.right,
      bottom: bottom ?? this.bottom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CropSettings &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

class TransformSettings {
  const TransformSettings({
    this.rotation = Rotation.none,
    this.flipHorizontal = false,
    this.flipVertical = false,
  });

  static const TransformSettings identity = TransformSettings();

  final Rotation rotation;
  final bool flipHorizontal;
  final bool flipVertical;

  Map<String, dynamic> toJson() => {
    'rotation': rotation.name,
    'flipHorizontal': flipHorizontal,
    'flipVertical': flipVertical,
  };

  static TransformSettings fromJson(Map<String, dynamic> json) =>
      TransformSettings(
        rotation: Rotation.values.firstWhere(
          (r) => r.name == json['rotation'],
          orElse: () => Rotation.none,
        ),
        flipHorizontal: json['flipHorizontal'] == true,
        flipVertical: json['flipVertical'] == true,
      );

  bool get isIdentity =>
      rotation == Rotation.none && !flipHorizontal && !flipVertical;

  TransformSettings copyWith({
    Rotation? rotation,
    bool? flipHorizontal,
    bool? flipVertical,
  }) {
    return TransformSettings(
      rotation: rotation ?? this.rotation,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TransformSettings &&
      other.rotation == rotation &&
      other.flipHorizontal == flipHorizontal &&
      other.flipVertical == flipVertical;

  @override
  int get hashCode => Object.hash(rotation, flipHorizontal, flipVertical);
}

class VideoTransform {
  const VideoTransform({
    this.crop = CropSettings.full,
    this.transform = TransformSettings.identity,
  });

  static const VideoTransform identity = VideoTransform();

  final CropSettings crop;
  final TransformSettings transform;

  Map<String, dynamic> toJson() => {
    'crop': crop.toJson(),
    'transform': transform.toJson(),
  };

  static VideoTransform fromJson(Map<String, dynamic> json) => VideoTransform(
    crop: CropSettings.fromJson(
      (json['crop'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    transform: TransformSettings.fromJson(
      (json['transform'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );

  bool get isIdentity => crop.isIdentity && transform.isIdentity;

  VideoTransform copyWith({
    CropSettings? crop,
    TransformSettings? transform,
  }) {
    return VideoTransform(
      crop: crop ?? this.crop,
      transform: transform ?? this.transform,
    );
  }
}
