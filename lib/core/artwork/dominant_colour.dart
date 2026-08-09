import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Picks one colour to build a background from, given raw RGBA pixels.
///
/// Deliberately not the arithmetic mean. Averaging a sleeve gives grey almost
/// every time: opposite hues cancel, and the result is the same murk for a
/// black metal cover and a Motown one. This buckets instead, so it returns a
/// colour that is genuinely *in* the picture rather than one halfway between
/// all of them.
///
/// Three rules decide the winner, and each exists because of a way covers
/// break a simpler one:
///
/// - **Near-black and near-white are excluded.** Sleeve borders, white vinyl
///   labels and letterboxing are often the single largest block of pixels on
///   the image, and a background derived from them is either invisible or
///   blinding.
/// - **Saturation is weighted, not required.** Weighted, because a large muted
///   field should still beat a small vivid one; not required, because plenty of
///   covers genuinely are monochrome and returning nothing for them would mean
///   the gradient appears for some albums and not others with no pattern a user
///   could see.
/// - **The winning bucket's own average is returned**, not the bucket's centre.
///   Quantising to 4 bits a channel is coarse enough that the centre visibly
///   misses, most obviously on skin tones and sunsets.
///
/// Returns null only when there is nothing to judge: no pixels, or every one of
/// them transparent or excluded.
Color? dominantColour(Uint8List rgba, {int stride = 1}) {
  if (rgba.length < 4) return null;

  final counts = <int, int>{};
  final sums = <int, List<int>>{};

  final step = 4 * (stride < 1 ? 1 : stride);
  for (var i = 0; i + 3 < rgba.length; i += step) {
    final a = rgba[i + 3];
    // Anything see-through says nothing about the colour underneath it.
    if (a < 128) continue;

    final r = rgba[i];
    final g = rgba[i + 1];
    final b = rgba[i + 2];

    final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (max <= 40 || min >= 225) continue;

    // Four bits a channel. Fine enough to keep two shades of the same colour
    // apart, coarse enough that a gradient in the artwork lands in one bucket
    // rather than fifty.
    final bucket = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);

    // Saturation as the spread between the brightest and dimmest channel,
    // which needs no conversion and orders colours the same way HSV would.
    final weight = 1 + (max - min);
    counts[bucket] = (counts[bucket] ?? 0) + weight;
    final sum = sums[bucket] ??= [0, 0, 0, 0];
    sum[0] += r;
    sum[1] += g;
    sum[2] += b;
    sum[3] += 1;
  }

  if (counts.isEmpty) return null;

  var best = counts.keys.first;
  for (final entry in counts.entries) {
    if (entry.value > counts[best]!) best = entry.key;
  }

  final sum = sums[best]!;
  final n = sum[3];
  return Color.fromARGB(255, sum[0] ~/ n, sum[1] ~/ n, sum[2] ~/ n);
}

/// Resolves an [ImageProvider] far enough to read its pixels, then throws the
/// decoded frame away.
///
/// Sampled at [edge] pixels square rather than full size. A 600px sleeve is
/// 1.4MB of RGBA and the answer is identical from a thumbnail, so decoding the
/// large one would be a megabyte of allocation per track change for a
/// background tint.
///
/// Returns null on any failure. This is decoration: an artwork that will not
/// load, a platform that cannot decode it, or a disconnected server all end the
/// same way, with the theme's own colour used instead.
Future<Color?> colourOfImage(ImageProvider provider, {int edge = 48}) async {
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(
    ImageConfiguration(size: Size(edge.toDouble(), edge.toDouble())),
  );

  // **Detached after the future settles, not from inside the callback.**
  // `addListener` invokes the listener synchronously when the image is already
  // decoded, which is the common case here because the transport bar is
  // usually showing the same sleeve, and removing a listener from inside its
  // own dispatch is asking for trouble for no gain.
  final listener = ImageStreamListener(
    (frame, _) {
      if (!completer.isCompleted) completer.complete(frame.image.clone());
    },
    // An artwork that will not load is not an error worth propagating: this is
    // a background tint, and the caller already treats null as "use the
    // theme's own colour".
    onError: (_, _) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );
  stream.addListener(listener);

  final image = await completer.future;
  stream.removeListener(listener);
  if (image == null) return null;

  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    // Every pixel of a small image costs nothing, and skipping any of a 48px
    // thumbnail would start to matter.
    return dominantColour(data.buffer.asUint8List());
  } on Object {
    return null;
  } finally {
    image.dispose();
  }
}
