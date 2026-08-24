import '../../models/video_transform.dart';

/// Pure crop-window geometry shared by the crop sheet UI and its tests.
///
/// Everything here works in NORMALIZED frame fractions (plan §22), takes the
/// TRUE source aspect ratio as input, and never mutates its arguments.
const _minFraction = 0.1;

/// Largest window of [outputRatio] (w/h) fitting a source of [sourceRatio],
/// keeping the previous window's center where the new size allows.
///
/// [outputRatio] null means "full frame". The result always yields an output
/// frame whose aspect equals [outputRatio] REGARDLESS of the source shape,
/// because fractions are solved against [sourceRatio].
CropSettings cropWindowForRatio({
  required double sourceRatio,
  required double? outputRatio,
  CropSettings anchor = CropSettings.full,
}) {
  if (outputRatio == null || sourceRatio <= 0) return CropSettings.full;

  final double wFrac;
  final double hFrac;
  if (outputRatio >= sourceRatio) {
    wFrac = 1;
    hFrac = (sourceRatio / outputRatio).clamp(_minFraction, 1);
  } else {
    hFrac = 1;
    wFrac = (outputRatio / sourceRatio).clamp(_minFraction, 1);
  }

  final prevCx = (anchor.left + anchor.right) / 2;
  final prevCy = (anchor.top + anchor.bottom) / 2;
  final left = wFrac >= 1 ? 0.0 : (prevCx - wFrac / 2).clamp(0.0, 1 - wFrac);
  final top = hFrac >= 1 ? 0.0 : (prevCy - hFrac / 2).clamp(0.0, 1 - hFrac);
  return CropSettings(
    left: left,
    top: top,
    right: left + wFrac,
    bottom: top + hFrac,
  );
}

/// Output aspect ratio (w/h) a crop window produces on [sourceRatio].
double croppedRatio(CropSettings crop, double sourceRatio) =>
    sourceRatio * crop.widthFraction / crop.heightFraction;

/// Whether the crop window currently produces [targetRatio] (null = full
/// frame). Tolerance is relative so both tiny and huge ratios match well.
bool cropMatchesRatio(
  CropSettings crop,
  double? targetRatio,
  double sourceRatio,
) {
  if (targetRatio == null) return crop.isIdentity;
  if (targetRatio <= 0 || sourceRatio <= 0) return false;
  final out = croppedRatio(crop, sourceRatio);
  return ((out - targetRatio) / targetRatio).abs() < 0.02;
}

/// Pans the window by normalized deltas ([dx]/[dy] as fractions of the FULL
/// frame), clamped inside the source bounds. Callers decide the SIGN — pass
/// negated drag deltas for the standard "content follows finger" feel.
CropSettings panCrop(CropSettings crop, double dx, double dy) {
  final w = crop.widthFraction;
  final h = crop.heightFraction;
  final left = w >= 1 ? 0.0 : (crop.left + dx).clamp(0.0, 1 - w);
  final top = h >= 1 ? 0.0 : (crop.top + dy).clamp(0.0, 1 - h);
  return crop.copyWith(
    left: left,
    top: top,
    right: left + w,
    bottom: top + h,
  );
}
