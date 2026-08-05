import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'artwork_cache.dart';

/// Plex artwork as an [ImageProvider], backed by [ArtworkCache].
///
/// Being an ImageProvider rather than a `FutureBuilder` around bytes is what
/// makes Flutter's own in-memory [ImageCache] work: it keys on whatever
/// [obtainKey] returns, so a decoded image is shared between every cell showing
/// the same album — and, because the key is the thumb and size rather than the
/// URL, it survives a token refresh and a change of server address without a
/// single re-decode. `Image.memory` would key on the byte list's identity and
/// re-decode on every rebuild.
///
/// [url] is deliberately **not** part of the key. It is only consulted on a
/// miss, which is why a cached grid still renders with no connection at all.
@immutable
class PlexArtwork extends ImageProvider<ArtworkKey> {
  const PlexArtwork({
    required this.thumb,
    required this.size,
    required this.cache,
    required this.url,
  });

  final String thumb;
  final int size;
  final ArtworkCache cache;

  /// Where to fetch from if it is not cached, or null while disconnected.
  final String? url;

  @override
  Future<ArtworkKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(ArtworkKey(thumb, size));

  @override
  ImageStreamCompleter loadImage(ArtworkKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(key, decode),
      scale: 1,
      debugLabel: '$key',
    );
  }

  Future<ui.Codec> _decode(ArtworkKey key, ImageDecoderCallback decode) async {
    final bytes = await cache.load(key, url);
    if (bytes == null || bytes.isEmpty) {
      // Thrown rather than returned as a blank image so that `Image`'s
      // errorBuilder runs and shows the same placeholder as a missing thumb.
      // Flutter also drops the failed entry from its cache, so a rebuild once
      // the connection is back retries instead of showing the error forever.
      throw StateError('No artwork for $key');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is PlexArtwork &&
      other.thumb == thumb &&
      other.size == size &&
      other.url == url;

  @override
  int get hashCode => Object.hash(thumb, size, url);
}
