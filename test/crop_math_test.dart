import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/core/utils/crop_math.dart';
import 'package:video_editor/models/video_transform.dart';

const _landscape = 16 / 9;
const _portrait = 9 / 16;
const _square = 1.0;

void main() {
  group('cropWindowForRatio', () {
    test('null target returns the full frame', () {
      expect(cropWindowForRatio(sourceRatio: _portrait, outputRatio: null),
          CropSettings.full);
      expect(
          cropWindowForRatio(
            sourceRatio: _landscape,
            outputRatio: null,
            anchor: const CropSettings(left: .2, top: .1, right: .8, bottom: .9),
          ),
          CropSettings.full);
    });

    test('16:9 on a 16:9 source is a no-op window', () {
      final c = cropWindowForRatio(sourceRatio: _landscape, outputRatio: 16 / 9);
      expect(c, CropSettings.full);
    });

    test('wider-than-source targets fill width and shrink height', () {
      // 2.35:1 cinemascope on landscape video.
      final c = cropWindowForRatio(
        sourceRatio: _landscape,
        outputRatio: 2.35,
      );
      expect(c.widthFraction, 1);
      expect(c.heightFraction, closeTo(_landscape / 2.35, 1e-9));
      expect(croppedRatio(c, _landscape), closeTo(2.35, 1e-9));
    });

    test('narrower-than-source targets fill height and shrink width', () {
      final c = cropWindowForRatio(sourceRatio: _landscape, outputRatio: 1);
      expect(c.heightFraction, 1);
      expect(c.widthFraction, closeTo(_square / _landscape, 1e-9));
      expect(croppedRatio(c, _landscape), closeTo(1, 1e-9));
    });

    test('PORTRAIT source: the 16:9 preset really yields 16:9', () {
      final c = cropWindowForRatio(sourceRatio: _portrait, outputRatio: 16 / 9);
      // Window must be a thin horizontal band across the portrait frame.
      expect(c.left, 0);
      expect(c.right, 1);
      expect(c.heightFraction, closeTo(_portrait / (16 / 9), 1e-9));
      expect(croppedRatio(c, _portrait), closeTo(16 / 9, 1e-9));
    });

    test('PORTRAIT source: square preset crops vertically (band)', () {
      final c = cropWindowForRatio(sourceRatio: _portrait, outputRatio: 1);
      // Square is WIDER than a portrait frame → fill width, shrink height.
      expect(c.left, 0);
      expect(c.right, 1);
      expect(c.heightFraction, closeTo(_portrait, 1e-9));
      expect(c.top, closeTo((1 - _portrait) / 2, 1e-9));
      expect(croppedRatio(c, _portrait), closeTo(1, 1e-9));
    });

    test('anchor center is preserved when the new size allows it', () {
      const anchor =
          CropSettings(left: .5, top: .25, right: 1, bottom: .75); // center (.75,.5)
      final c = cropWindowForRatio(
        sourceRatio: _landscape,
        outputRatio: 4 / 3,
        anchor: anchor,
      );
      // wFrac = (4/3)/(16/9) = .75 → left range [0,.25]; center .75 wants
      // left=.375, clamped to .25.
      expect(c.left, closeTo(.25, 1e-9));
      expect((c.left + c.right) / 2, closeTo(.625, 1e-9));
      expect(c.top, 0);
      expect(croppedRatio(c, _landscape), closeTo(4 / 3, 1e-9));
    });

    test('minimum fraction floor is respected for extreme ratios', () {
      final c = cropWindowForRatio(
        sourceRatio: _landscape,
        outputRatio: 100, // absurdly wide
      );
      expect(c.heightFraction, greaterThanOrEqualTo(.1 - 1e-12));
    });
  });

  group('cropMatchesRatio', () {
    test('full frame only matches a null target on odd sources', () {
      expect(cropMatchesRatio(CropSettings.full, null, _landscape), isTrue);
      // On a 16:9 source the full frame IS 16:9 — both chips can match;
      // the sheet resolves ties by checking Full FIRST.
      expect(
          cropMatchesRatio(CropSettings.full, 16 / 9, _landscape), isTrue);
      expect(
          cropMatchesRatio(CropSettings.full, 16 / 9, _portrait), isFalse);
    });

    test('generic matching works across orientations', () {
      final squareOnPortrait =
          cropWindowForRatio(sourceRatio: _portrait, outputRatio: 1);
      expect(cropMatchesRatio(squareOnPortrait, 1, _portrait), isTrue);

      final wide16x9OnPortrait =
          cropWindowForRatio(sourceRatio: _portrait, outputRatio: 16 / 9);
      expect(
          cropMatchesRatio(wide16x9OnPortrait, 16 / 9, _portrait), isTrue);
      // The same window does NOT match other presets.
      expect(cropMatchesRatio(wide16x9OnPortrait, 1, _portrait), isFalse);
    });
  });

  group('panCrop', () {
    test('pans by normalized deltas and keeps the window size', () {
      const c =
          CropSettings(left: .1, top: .1, right: .6, bottom: .6); // 0.5×0.5
      final panned = panCrop(c, .2, -.05);
      expect(panned.left, closeTo(.3, 1e-9));
      expect(panned.top, closeTo(.05, 1e-9));
      expect(panned.widthFraction, .5);
      expect(panned.heightFraction, .5);
    });

    test('clamps inside the frame on every side', () {
      const c = CropSettings(left: 0, top: 0, right: .5, bottom: .5);
      expect(panCrop(c, -10, 10).left, 0);
      expect(panCrop(c, -10, 10).top, .5);

      const rightHalf =
          CropSettings(left: .5, top: 0, right: 1, bottom: .5);
      expect(panCrop(rightHalf, 10, 0).right, 1);
      expect(panCrop(rightHalf, 10, 0).left, .5);
    });

    test('full-axis windows stay pinned to that axis', () {
      const band = CropSettings(left: 0, top: .2, right: 1, bottom: .8);
      final panned = panCrop(band, .3, .1);
      expect(panned.left, 0);
      expect(panned.right, 1);
      expect(panned.top, closeTo(.3, 1e-9));
    });
  });
}
