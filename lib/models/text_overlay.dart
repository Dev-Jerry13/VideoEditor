import 'package:flutter/painting.dart' show TextAlign;

import '../core/constants/app_constants.dart';

/// A text overlay positioned on the project preview.
///
/// Geometry is stored in NORMALIZED coordinates (0..1 fractions of the
/// video frame) so overlays survive resolution and aspect-ratio changes;
/// the same values drive the Flutter preview and the FFmpeg export.
enum OverlayTextColor {
  white('FFFFFF'),
  black('000000'),
  yellow('FFEB3B'),
  red('F44336'),
  cyan('00E5FF'),
  green('4CAF50');

  const OverlayTextColor(this.hex);

  /// Six-digit RGB, no leading '#'.
  final String hex;

  @override
  String toString() => '#$hex';
}

class TextOverlay {
  const TextOverlay({
    required this.id,
    required this.text,
    required this.startTime,
    required this.endTime,
    this.fontSize = AppConstants.defaultTextFontSize,
    this.x = 0.5,
    this.y = 0.5,
    this.alignment = TextAlign.center,
    this.bold = false,
    this.color = OverlayTextColor.white,
    this.background = true,
  }) : assert(text.length > 0, 'text must not be empty'),
       assert(x >= 0 && x <= 1, 'x must be normalized 0..1'),
       assert(y >= 0 && y <= 1, 'y must be normalized 0..1'),
       assert(endTime > startTime, 'overlay range must be positive');

  /// Font size as a fraction of the video height.
  final double fontSize;

  /// Horizontal anchor (0 = left edge, 1 = right edge).
  final double x;

  /// Vertical anchor (0 = top edge, 1 = bottom edge).
  final double y;

  final String id;
  final String text;

  /// Visibility window on the PROJECT timeline.
  final Duration startTime;
  final Duration endTime;

  final TextAlign alignment;
  final bool bold;
  final OverlayTextColor color;
  final bool background;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'fontSize': fontSize,
    'x': x,
    'y': y,
    'startMs': startTime.inMilliseconds,
    'endMs': endTime.inMilliseconds,
    'alignment': alignment.index,
    'bold': bold,
    'color': color.hex,
    'background': background,
  };

  static OverlayTextColor _colorFromHex(String? hex) {
    if (hex == null) return OverlayTextColor.white;
    for (final value in OverlayTextColor.values) {
      if (value.hex == hex) return value;
    }
    return OverlayTextColor.white;
  }

  static TextOverlay fromJson(Map<String, dynamic> json) {
    final startTime = Duration(milliseconds: json['startMs'] as int? ?? 0);
    final endMs = json['endMs'] as int?;
    final endTime = Duration(
      milliseconds: endMs ?? startTime.inMilliseconds + 1000,
    );
    return TextOverlay(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? ' ',
      fontSize:
          (json['fontSize'] as num?)?.toDouble() ??
          AppConstants.defaultTextFontSize,
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.5,
      startTime: startTime,
      endTime: endTime,
      alignment:
          TextAlign.values[(json['alignment'] as int? ?? TextAlign.center.index)
              .clamp(0, TextAlign.values.length - 1)],
      bold: json['bold'] == true,
      color: _colorFromHex(json['color'] as String?),
      background: json['background'] != false,
    );
  }

  Duration get duration => endTime - startTime;

  TextOverlay copyWith({
    String? id,
    String? text,
    double? fontSize,
    double? x,
    double? y,
    Duration? startTime,
    Duration? endTime,
    TextAlign? alignment,
    bool? bold,
    OverlayTextColor? color,
    bool? background,
  }) {
    return TextOverlay(
      id: id ?? this.id,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      x: x ?? this.x,
      y: y ?? this.y,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      alignment: alignment ?? this.alignment,
      bold: bold ?? this.bold,
      color: color ?? this.color,
      background: background ?? this.background,
    );
  }
}
