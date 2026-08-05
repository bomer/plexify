import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// What an image is, independently of where it is being fetched from.
///
/// **The whole point is what is not in here.** The artwork URL embeds the
/// server's base address *and* the Plex token, and both move — the token when
/// it is refreshed, the address every time the connection is re-raced between
/// LAN, remote and relay. Keying a cache on the URL means every network change
/// misses on every visible thumbnail, which is precisely the moment a cache is
/// supposed to earn its keep.
///
/// The thumb path and the requested size are the two things that actually
/// determine the bytes, so they are the key.
@immutable
class ArtworkKey {
  const ArtworkKey(this.thumb, this.size);

  /// Plex's path for the image, e.g. `/library/metadata/41/thumb/1699887…`.
  ///
  /// Already carries a timestamp, so new artwork for the same album is a
  /// different key rather than a stale hit.
  final String thumb;

  /// The size asked of Plex's photo transcoder. Two sizes of one image are two
  /// different files and must not share an entry.
  final int size;

  /// A filename that survives a round trip through the filesystem.
  ///
  /// base64url of the key rather than a hash: reversible, collision-free, and
  /// deterministic across runs — `String.hashCode` is not guaranteed stable
  /// between Dart versions, and a cache that silently misses after an SDK
  /// upgrade is indistinguishable from one that does not work.
  String get fileName => base64Url.encode(utf8.encode('$thumb|$size'));

  @override
  bool operator ==(Object other) =>
      other is ArtworkKey && other.thumb == thumb && other.size == size;

  @override
  int get hashCode => Object.hash(thumb, size);

  @override
  String toString() => 'ArtworkKey($thumb, $size)';
}

/// Artwork bytes on disk, bounded and evicted least-recently-used.
///
/// Hand-rolled rather than `cached_network_image`, for two reasons that both
/// matter here. That package keys on the URL, which is the one thing this cache
/// must *not* do; and it brings `flutter_cache_manager` and `sqflite`, adding a
/// second SQLite binding to an app that already ships drift and has to work on
/// Windows. Fetching bytes, writing a file and deleting the oldest is a small
/// enough job to own.
///
/// The index lives in memory and is rebuilt from the directory on first use.
/// Nothing about it is persisted: after a restart the least-recently-used order
/// falls back to file modification time, which is close enough for artwork and
/// costs no writes on the read path. A cache that wrote a row per thumbnail
/// would put a database write into every scroll frame.
class ArtworkCache {
  ArtworkCache({Directory? directory, int? maxBytes, http.Client? httpClient})
    : _override = directory,
      maxBytes = maxBytes ?? defaultMaxBytes,
      _http = httpClient ?? http.Client();

  /// Deliberately modest. Artwork is thumbnails, not audio — the 300px grid
  /// images are a few tens of kilobytes each, so this holds thousands. The
  /// audio cache is the one that needs gigabytes.
  ///
  /// Phones are tighter about storage than desktops and hold a smaller share of
  /// the library on screen, so they get less.
  static final int defaultMaxBytes = Platform.isAndroid
      ? 64 * 1024 * 1024
      : 256 * 1024 * 1024;

  final int maxBytes;
  final http.Client _http;

  /// Where to put files, for tests. Null means ask the platform.
  ///
  /// Only *where*, deliberately — everything else about opening still happens,
  /// including the scan. An injected directory that skipped the scan would make
  /// the cold-start path the one thing tests could not reach, which is exactly
  /// the path most likely to be wrong.
  final Directory? _override;

  Future<Directory>? _opening;

  final _index = <String, _Entry>{};
  final _inFlight = <String, Future<Uint8List?>>{};

  /// Monotonic, so "least recently used" is a comparison rather than a clock.
  /// A wall clock would tie at millisecond resolution during a fast scroll.
  int _clock = 0;

  /// Total bytes currently held. Exposed for the settings screen and tests.
  int get bytesHeld => _index.values.fold(0, (sum, e) => sum + e.bytes);

  int get entryCount => _index.length;

  /// Counters for the Sync status screen.
  ///
  /// Every other background mechanism in this app publishes its state there,
  /// and this one did not — which is exactly why "no artwork on the grid, but
  /// fine on the album page" could not be diagnosed without a device in hand.
  /// A cache that silently returns nothing looks identical whether the server
  /// refused, the directory could not be written, or the screen simply asked
  /// before the connection existed.
  int get hits => _hits;
  int get misses => _misses;
  int get fetchFailures => _fetchFailures;

  /// Asked for while disconnected: no cached copy *and* no URL to fetch one
  /// with. Non-zero here alongside blank artwork means the screen is asking
  /// before the client exists, not that anything is broken.
  int get skippedNoUrl => _skippedNoUrl;

  String? get lastError => _lastError;

  int _hits = 0;
  int _misses = 0;
  int _fetchFailures = 0;
  int _skippedNoUrl = 0;
  String? _lastError;

  /// The bytes for [key], from disk if they are there and from [url] if not.
  ///
  /// Returns null when the image is not cached and cannot be fetched — either
  /// because there is no connection to build a URL from, or because the request
  /// failed. Callers show the placeholder; a missing thumbnail is never worth
  /// an exception.
  Future<Uint8List?> load(ArtworkKey key, String? url) {
    // One fetch per key, however many cells ask for it. A grid scrolled quickly
    // requests the same album from several builds before the first completes,
    // and without this each would open its own connection.
    final existing = _inFlight[key.fileName];
    if (existing != null) return existing;

    final pending = _load(key, url);
    _inFlight[key.fileName] = pending;
    return pending.whenComplete(() => _inFlight.remove(key.fileName));
  }

  Future<Uint8List?> _load(ArtworkKey key, String? url) async {
    final directory = await _open();
    final file = File('${directory.path}/${key.fileName}');

    final entry = _index[key.fileName];
    if (entry != null) {
      try {
        final bytes = await file.readAsBytes();
        entry.used = ++_clock;
        _hits++;
        return bytes;
      } on Object {
        // Indexed but unreadable — deleted from under us, or a write that was
        // interrupted. Drop it and fall through to fetching again.
        _index.remove(key.fileName);
      }
    }

    if (url == null) {
      _skippedNoUrl++;
      return null;
    }

    _misses++;
    final Uint8List bytes;
    try {
      final response = await _http.get(Uri.parse(url));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        _fetchFailures++;
        _lastError = response.statusCode == 200
            ? 'Plex answered 200 with an empty body'
            : 'Plex answered HTTP ${response.statusCode}';
        return null;
      }
      bytes = response.bodyBytes;
    } on Object catch (e) {
      _fetchFailures++;
      _lastError = '$e';
      return null;
    }

    try {
      await file.writeAsBytes(bytes, flush: false);
      _index[key.fileName] = _Entry(bytes: bytes.length, used: ++_clock);
      await _evict();
    } on Object catch (e) {
      // A cache that cannot write is still a working image loader, so this
      // does not fail the load — but it does mean every image is fetched
      // again on every launch, which is worth being able to see.
      _lastError = 'Could not write to the cache: $e';
    }

    return bytes;
  }

  /// Removes everything. Used when signing out and by the settings screen.
  ///
  /// Never throws. Sign-out calls this, and artwork failing to delete is not a
  /// reason to abandon a teardown that is also clearing the token and the
  /// library.
  Future<void> clear() async {
    _index.clear();
    try {
      final directory = await _open();
      await for (final entity in directory.list()) {
        await entity.delete();
      }
    } on Object {
      // A file we cannot delete is evicted later; a directory we cannot open
      // holds nothing we could have deleted anyway.
    }
  }

  /// Deletes least-recently-used entries until the budget is met.
  Future<void> _evict() async {
    var total = bytesHeld;
    if (total <= maxBytes) return;

    final byAge = _index.entries.toList()
      ..sort((a, b) => a.value.used.compareTo(b.value.used));

    final directory = await _open();
    for (final entry in byAge) {
      if (total <= maxBytes) break;
      _index.remove(entry.key);
      total -= entry.value.bytes;
      try {
        await File('${directory.path}/${entry.key}').delete();
      } on Object {
        // Already gone. The index is what the budget is computed from, and it
        // has been corrected either way.
      }
    }
  }

  /// Opens the directory and rebuilds the index from what is already there.
  ///
  /// Memoised on the future rather than the value, so several images racing on
  /// a cold start share one scan instead of each triggering their own.
  Future<Directory> _open() => _opening ??= _scan();

  Future<Directory> _scan() async {
    final Directory directory;
    try {
      directory =
          _override ??
          Directory('${(await getApplicationSupportDirectory()).path}/artwork');
      await directory.create(recursive: true);
    } on Object catch (e) {
      // Not memoised as a failure. path_provider can fail transiently during
      // startup, and holding onto a rejected future would leave the cache dead
      // for the rest of the session rather than for one image.
      _opening = null;
      _lastError = 'Could not open the cache directory: $e';
      rethrow;
    }

    try {
      final files = <(String, FileStat)>[];
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        files.add((_baseName(entity.path), await entity.stat()));
      }

      // Modification time is the only ordering a fresh process has. It is not
      // true last-use, but it is the right shape: what was written longest ago
      // goes first.
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (name, stat) in files) {
        _index[name] = _Entry(bytes: stat.size, used: ++_clock);
      }
    } on Object {
      // An unreadable cache directory is an empty one.
    }

    return directory;
  }

  static String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;
}

class _Entry {
  _Entry({required this.bytes, required this.used});

  final int bytes;
  int used;
}
