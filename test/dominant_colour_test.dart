import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/artwork/dominant_colour.dart';

/// The colour behind the expanded player.
///
/// Every case here is a real album sleeve in miniature. The failure mode this
/// guards against is not a crash: it is a gradient that comes out the same
/// murky grey for every record in the library, which looks like the feature
/// simply not working and would be easy to ship.
void main() {
  /// Builds RGBA pixels from a list of (colour, how many).
  Uint8List pixels(List<(Color, int)> runs) {
    final out = BytesBuilder();
    for (final (colour, count) in runs) {
      for (var i = 0; i < count; i++) {
        out.add([
          (colour.r * 255).round(),
          (colour.g * 255).round(),
          (colour.b * 255).round(),
          (colour.a * 255).round(),
        ]);
      }
    }
    return out.toBytes();
  }

  test('finds the colour a cover is actually made of', () {
    final colour = dominantColour(
      pixels([(const Color(0xFFCC2200), 600), (const Color(0xFF113355), 100)]),
    );

    expect(colour!.r * 255, closeTo(0xCC, 8));
    expect(colour.g * 255, closeTo(0x22, 8));
  });

  test('does not average opposing colours into grey', () {
    // The reason this is a histogram rather than a mean. Half red and half
    // cyan averages to something near neutral, which is the same answer a
    // black metal sleeve and a Motown one would both get, and the gradient
    // would look broken rather than subtle.
    final colour = dominantColour(
      pixels([(const Color(0xFFDD0000), 500), (const Color(0xFF00DDDD), 400)]),
    )!;

    final max = [colour.r, colour.g, colour.b].reduce((a, b) => a > b ? a : b);
    final min = [colour.r, colour.g, colour.b].reduce((a, b) => a < b ? a : b);
    expect(max - min, greaterThan(0.3), reason: 'came out desaturated');
  });

  test('ignores a black border, however much of the cover it is', () {
    // Letterboxed and bordered sleeves are common, and the border is often the
    // single largest block of pixels on the image. A background derived from
    // it is invisible.
    final colour = dominantColour(
      pixels([(const Color(0xFF000000), 5000), (const Color(0xFF3388EE), 200)]),
    );

    expect(colour, isNotNull);
    expect(colour!.b, greaterThan(0.5));
  });

  test('ignores a white field for the same reason', () {
    final colour = dominantColour(
      pixels([(const Color(0xFFFFFFFF), 5000), (const Color(0xFFAA4400), 200)]),
    );

    expect(colour, isNotNull);
    expect(colour!.r, greaterThan(colour.b));
  });

  test('prefers a large muted field over a small vivid one', () {
    // Saturation is weighted, not required. A sleeve that is mostly dusty
    // green with one red dot on it is a green sleeve.
    final colour = dominantColour(
      pixels([(const Color(0xFF6A7A5A), 4000), (const Color(0xFFFF0000), 60)]),
    )!;

    expect(colour.g, greaterThan(colour.b));
    expect(colour.r * 255, lessThan(0x90));
  });

  test('still answers for a monochrome cover', () {
    // Plenty of records genuinely are. Returning null for them would make the
    // gradient appear for some albums and not others with no pattern anyone
    // could see, which reads as a bug.
    expect(dominantColour(pixels([(const Color(0xFF808080), 400)])), isNotNull);
  });

  test('transparent pixels say nothing about the colour underneath', () {
    final colour = dominantColour(
      pixels([(const Color(0x0000FF00), 4000), (const Color(0xFF2244CC), 200)]),
    )!;

    expect(colour.b, greaterThan(colour.g));
  });

  test('gives up rather than guessing when there is nothing to judge', () {
    expect(dominantColour(Uint8List(0)), isNull);
    // Every pixel excluded: pure black, which is a real cover and a real null.
    expect(dominantColour(pixels([(const Color(0xFF000000), 100)])), isNull);
    expect(dominantColour(pixels([(const Color(0x00000000), 100)])), isNull);
  });

  test('a stride samples the same picture', () {
    final image = pixels([
      (const Color(0xFFCC2200), 600),
      (const Color(0xFF113355), 100),
    ]);

    final every = dominantColour(image)!;
    final sampled = dominantColour(image, stride: 7)!;
    expect((every.r - sampled.r).abs(), lessThan(0.1));
  });
}
