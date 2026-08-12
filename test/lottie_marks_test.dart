import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// The two bundled animations are Krish's own downloads and ship exactly as
/// they were drawn — the flame white over grey, the target in its own red.
/// A colour delegate would repaint them silently and nothing would fail, so
/// these tests paint the real frames and read the pixels back: the artist's
/// colours must still be there, untouched.

/// Paints [composition] at [progress] into a bitmap and returns its pixels.
Future<Uint32List> _paint(
  LottieComposition composition,
  double progress, {
  int side = 240,
}) async {
  final drawable = LottieDrawable(composition)..setProgress(progress);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  drawable.draw(
    canvas,
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    fit: BoxFit.contain,
  );
  final image = await recorder.endRecording().toImage(side, side);
  final data =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return data!.buffer.asUint32List();
}

({int r, int g, int b, int a}) _channels(int abgr) => (
      r: abgr & 0xFF,
      g: (abgr >> 8) & 0xFF,
      b: (abgr >> 16) & 0xFF,
      a: (abgr >> 24) & 0xFF,
    );

/// A pixel that has picked up a hue — the tell-tale of a retint.
bool _isColoured(({int r, int g, int b, int a}) p) =>
    p.a > 200 && ((p.r - p.g).abs() > 12 || (p.g - p.b).abs() > 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the flame stays the white-and-grey fire it was drawn as', () async {
    final composition =
        await AssetLottie('assets/animation/streak_fire.json').load();
    // Mid-take: the fire is at its widest.
    final pixels = await _paint(composition, 0.55);

    var white = 0;
    var coloured = 0;
    for (final px in pixels) {
      final p = _channels(px);
      if (p.a > 200 && p.r > 240 && p.g > 240 && p.b > 240) white++;
      if (_isColoured(p)) coloured++;
    }
    expect(white, greaterThan(200), reason: 'the flame is white fire');
    expect(coloured, 0, reason: 'nothing may tint the flame');
  });

  test('the target keeps its own red and white', () async {
    final composition =
        await AssetLottie('assets/animation/target_stamp.json').load();
    // Late in the throw: the dart has landed and the rings are all visible.
    final pixels = await _paint(composition, 0.92);

    // The file's own fills, straight from the JSON.
    const red = 0xD54722;
    const white = 0xFFFFFF;
    final seen = <int>{};
    for (final px in pixels) {
      final p = _channels(px);
      if (p.a < 250) continue;
      seen.add((p.r << 16) | (p.g << 8) | p.b);
    }
    expect(seen, contains(red), reason: "the target's red must survive");
    expect(seen, contains(white), reason: "the target's white must survive");
  });
}
