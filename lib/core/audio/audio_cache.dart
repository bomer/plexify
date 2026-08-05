import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'quality_policy.dart';

/// Where a cached track lives, and why that is not just its ratingKey.
///
/// A direct-played FLAC and a transcoded mp3 of the same track are the same
/// music and completely different bytes. Keyed on the ratingKey alone, the
/// copy transcoded on a train would be served for ever once back on the LAN,
/// and the fidelity the quality decision exists to protect would silently
/// never arrive. This is invariant 2 in PROJECT.md, written down before the
/// cache existed precisely because it is invisible once broken.
@immutable
class AudioKey {
  const AudioKey(this.ratingKey, this.decision);

  final String ratingKey;
  final QualityDecision decision;

  String get fileName => '$ratingKey.${decision.name}';

  @override
  bool operator ==(Object other) =>
      other is AudioKey &&
      other.ratingKey == ratingKey &&
      other.decision == decision;

  @override
  int get hashCode => Object.hash(ratingKey, decision);

  @override
  String toString() => 'AudioKey($fileName)';
}

/// Audio on disk, bounded and evicted least-recently-used.
///
/// Unlike the artwork cache this does not fetch anything. `just_audio`'s
/// `LockCachingAudioSource` streams and writes the file itself; all this owns
/// is *where* each track goes, how much space the whole thing may take, and
/// what gets deleted when it takes too much. That division matters: the
/// download happens while the track plays, so anything clever here would be
/// competing with playback for the same bytes.
class AudioCache {
  AudioCache({Directory? directory, int? maxBytes})
    : _override = directory,
      maxBytes = maxBytes ?? defaultMaxBytes;

  /// Generous next to the artwork cache because the unit is a whole track:
  /// a FLAC album is comfortably 300MB, so a budget in the hundreds of
  /// megabytes holds a handful of albums and evicts constantly.
  ///
  /// Phones are tighter about storage, and cache less of the library because
  /// less of it is reachable on a small screen in one sitting.
  static final int defaultMaxBytes = Platform.isAndroid
      ? 2 * 1024 * 1024 * 1024
      : 10 * 1024 * 1024 * 1024;

  final int maxBytes;

  /// Where to put files, for tests. Only *where*: the scan still happens, so
  /// the cold-start path is the one tests exercise rather than the one they
  /// skip. Learned from the artwork cache, where injecting a directory
  /// silently bypassed the index rebuild.
  final Directory? _override;

  Directory? _directory;
  Future<Directory>? _opening;

  final _index = <String, _Entry>{};

  /// Files currently backing a loaded audio source.
  ///
  /// Eviction must never delete one of these. `LockCachingAudioSource` holds
  /// the handle for the life of the queue entry and writes to it as the track
  /// streams, so deleting underneath it truncates the download and the track
  /// stops mid-play with no error anyone would connect to the cache.
  final _inUse = <String>{};

  int _clock = 0;

  int get bytesHeld => _index.values.fold(0, (sum, e) => sum + e.bytes);

  int get entryCount => _index.length;

  int get evictions => _evictions;
  int _evictions = 0;
  String? get lastError => _lastError;
  String? _lastError;

  /// Resolves the directory and rebuilds the index from what is on disk.
  ///
  /// Called before a queue is built so [fileFor] can stay synchronous, which
  /// is what lets the audio sources be constructed in one pass rather than
  /// awaiting per track.
  Future<void> ensureReady() async {
    if (_directory != null) return;
    try {
      _directory = await (_opening ??= _scan());
    } on Object catch (e) {
      // Not memoised as a failure: a cache that cannot open is a cache that
      // does nothing, not an app that cannot play music.
      _opening = null;
      _lastError = 'Could not open the audio cache: $e';
    }
  }

  /// Null until [ensureReady] has run, and null forever if it failed. Callers
  /// fall back to streaming without a cache, which is exactly how playback
  /// worked before this existed.
  File? fileFor(AudioKey key) {
    final directory = _directory;
    if (directory == null) return null;

    final file = File('${directory.path}/${key.fileName}');
    _inUse.add(key.fileName);
    // Touched on use rather than on write, so a track played from cache moves
    // to the back of the eviction queue instead of ageing out while in
    // rotation.
    final entry = _index[key.fileName];
    if (entry != null) entry.used = ++_clock;
    return file;
  }

  /// Says the queue no longer references these keys, so they may be evicted.
  ///
  /// Called when a queue is replaced. Anything not in the new queue is fair
  /// game; anything still in it is re-marked by [fileFor] on the way through.
  void releaseAll() => _inUse.clear();

  /// Brings the index up to date with what was actually written, then evicts.
  ///
  /// Sizes are read from disk rather than tracked as bytes arrive, because the
  /// writing is `LockCachingAudioSource`'s and it reports nothing useful about
  /// partial files.
  Future<void> settle() async {
    final directory = _directory;
    if (directory == null) return;

    try {
      _index.clear();
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = _baseName(entity.path);
        final stat = await entity.stat();
        _index[name] = _Entry(
          bytes: stat.size,
          // Modification time is the only ordering a fresh process has, and
          // for audio it is close to true last-use: the file is written while
          // the track plays.
          used: ++_clock,
        );
      }
    } on Object catch (e) {
      _lastError = 'Could not read the audio cache: $e';
      return;
    }

    await _evict();
  }

  /// Deletes everything. Never throws: this runs on the way out of a session.
  Future<void> clear() async {
    final directory = _directory;
    _index.clear();
    _inUse.clear();
    if (directory == null) return;
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
      await directory.create(recursive: true);
    } on Object catch (e) {
      _lastError = 'Could not clear the audio cache: $e';
    }
  }

  Future<void> _evict() async {
    final directory = _directory;
    if (directory == null) return;

    var total = bytesHeld;
    if (total <= maxBytes) return;

    final candidates = _index.entries.where((e) => !_inUse.contains(e.key));
    final ordered = candidates.toList()
      ..sort((a, b) => a.value.used.compareTo(b.value.used));

    for (final entry in ordered) {
      if (total <= maxBytes) break;
      try {
        final file = File('${directory.path}/${entry.key}');
        if (file.existsSync()) await file.delete();
        total -= entry.value.bytes;
        _index.remove(entry.key);
        _evictions++;
      } on Object catch (e) {
        // A file that will not delete is one entry over budget, not a reason
        // to stop evicting the rest.
        _lastError = 'Could not evict from the audio cache: $e';
      }
    }
  }

  Future<Directory> _scan() async {
    final directory =
        _override ??
        Directory('${(await getApplicationSupportDirectory()).path}/audio');
    await directory.create(recursive: true);
    return directory;
  }

  static String _baseName(String path) =>
      path.split(Platform.pathSeparator).last.split('/').last;
}

class _Entry {
  _Entry({required this.bytes, required this.used});
  final int bytes;
  int used;
}
