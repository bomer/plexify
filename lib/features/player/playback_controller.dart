import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/audio/notification_permission.dart';
import '../../core/audio/playback_handler.dart';
import '../../core/audio/audio_cache.dart';
import '../../core/audio/playback_source.dart';
import '../../core/audio/playback_state_store.dart';
import '../../core/audio/quality_policy.dart';
import '../../core/plex/plex_client.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../core/settings/app_settings.dart';

/// Turns Plex tracks into something the audio engine can play.
///
/// This is the only place that knows how to get from a [PlexTrack] to a
/// playable URL, which keeps the URL-building decision — direct play or
/// transcode, per [QualityPolicy] — in one spot.
class PlaybackController {
  PlaybackController({
    required PlexifyAudioHandler handler,
    required PlexClient client,
    QualityPolicy quality = const QualityPolicy(),
    PlaybackStateStore? store,
    AudioCache? audioCache,
    QualityDecision? Function({required bool unmetered})? qualityOverride,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    String Function() newSession = _defaultSession,
  }) : _handler = handler,
       _client = client,
       _quality = quality,
       _store = store,
       _audioCache = audioCache,
       _qualityOverride = qualityOverride,
       _checkConnectivity =
           checkConnectivity ?? Connectivity().checkConnectivity,
       _newSession = newSession {
    // The handler knows a track is transcoded but not how to rebuild its URL,
    // which is this class's job and nobody else's.
    _handler.resolveSeekUrl = _seekUrl;
    _handler.resolveCacheFile = _cacheFile;
  }

  final PlexifyAudioHandler _handler;
  final PlexClient _client;
  final QualityPolicy _quality;

  /// Null in tests that do not care about persistence, which keeps
  /// `shared_preferences` off the path of everything else.
  final PlaybackStateStore? _store;

  /// Null in tests that do not care about caching, which keeps the filesystem
  /// off the path of everything else.
  final AudioCache? _audioCache;

  /// What the settings screen chose for the connection this device is on, or
  /// null to decide automatically.
  ///
  /// A callback rather than an [AppSettings] value, because the controller must
  /// not be rebuilt when an unrelated setting changes; this is read at the
  /// moment a queue is built and never held.
  final QualityDecision? Function({required bool unmetered})? _qualityOverride;

  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final String Function() _newSession;

  static String _defaultSession() => const Uuid().v4();

  /// Transcode sessions this controller has opened and not yet torn down.
  ///
  /// Plex does not stop these on its own — see
  /// `PlexClient.stopTranscodeSession` — so whatever opens one must also
  /// close it, or the server keeps transcoding into a buffer nobody is
  /// reading. Replacing the queue is where the previous batch's sessions
  /// become unreachable, so that is where they are torn down.
  final _openSessions = <String>{};

  /// Replaces the queue with [tracks] and starts at [startIndex].
  ///
  /// Unplayable tracks are dropped rather than left as gaps that would stall
  /// the queue, so [startIndex] is remapped onto the filtered list.
  ///
  /// Quality is decided once for the whole batch, not re-evaluated per track
  /// as playback advances — connectivity read here is what the entire queue
  /// plays under, and a change mid-queue takes effect on the *next* call to
  /// this method, never mid-track.
  Future<void> playTracks(
    List<PlexTrack> tracks, {
    int startIndex = 0,
    PlaybackSource? source,
  }) async {
    // Ask for notification permission at the moment its purpose is obvious.
    // Never gates playback — see NotificationPermission.
    await NotificationPermission.ensure();

    final playable = <PlexTrack>[];
    var adjustedStart = 0;

    for (var i = 0; i < tracks.length; i++) {
      if (!tracks[i].isPlayable) continue;
      if (i <= startIndex) adjustedStart = playable.length;
      playable.add(tracks[i]);
    }

    if (playable.isEmpty) return;

    final connectivity = await _checkConnectivity();
    _cacheFillAllowed = QualityPolicy.unmetered(connectivity);
    // The previous queue's files stop being protected the moment it is
    // replaced; whatever is still in the new one is re-marked as it is built.
    _audioCache?.releaseAll();
    await _audioCache?.ensureReady();

    final outgoingSessions = _openSessions.toList();
    _openSessions.clear();

    final items = <MediaItem>[];
    for (final track in playable) {
      final item = _toMediaItem(track, connectivity, source);
      if (item != null) items.add(item);
    }

    if (items.isEmpty) return;

    await _handler.setQueueAndPlay(items, initialIndex: adjustedStart);
    unawaited(save());
    // Reads what was actually written and evicts down to budget. Deliberately
    // after the queue is playing: this touches the filesystem and nothing
    // about it should delay the first note.
    unawaited(_audioCache?.settle() ?? Future.value());

    for (final session in outgoingSessions) {
      unawaited(_client.stopTranscodeSession(session));
    }
  }

  /// Runs [work] after whatever queue rebuild is already in flight.
  ///
  /// `setAudioSources` aborts a load that is still running when a second one
  /// starts, and the abandoned one completes with "Loading interrupted".
  /// Startup hits this every time: the restore begins loading, the connection
  /// resolves a moment later, and the rebuild lands on top of it. Both are
  /// fire-and-forget, so the interruption surfaced as an unhandled exception.
  Future<void> _queued(Future<void> Function() work) {
    final next = (_rebuilding ?? Future<void>.value()).then(
      (_) => work(),
      // A failure in the previous rebuild is its own caller's problem; it must
      // not poison every rebuild that follows.
      onError: (Object _) => work(),
    );
    _rebuilding = next;
    return next;
  }

  Future<void>? _rebuilding;

  /// Rebuilds the loaded queue against the current connection, resuming where
  /// it was.
  ///
  /// Every URL in a queue is fixed at the moment it is built, and both kinds
  /// embed the server address that was live then. Walk out of the house and
  /// every one of them points at a LAN address that no longer resolves — not
  /// only the track playing, but every track after it, because they were all
  /// handed to the engine up front. Skipping forward therefore finds one dead
  /// URL after another, which is exactly what it feels like.
  ///
  /// Re-deciding quality at the same time is the point rather than a bonus:
  /// the reason the address changed is usually that the network did, and a
  /// direct-play FLAC chosen on the LAN is the wrong call on the cellular
  /// connection that replaced it.
  ///
  /// Rebuilt from the queue's own `extras` rather than from Plex or drift, so
  /// it needs no round trip at the moment the connection is least trustworthy.
  Future<void> resumeOnNewConnection() => _queued(_resumeOnNewConnection);

  Future<void> _resumeOnNewConnection() async {
    final items = _handler.queue.value;
    if (items.isEmpty) return;

    final index = _handler.currentIndex;
    if (index == null || index < 0 || index >= items.length) return;

    final resumeAt = _handler.position;
    final connectivity = await _checkConnectivity();
    _cacheFillAllowed = QualityPolicy.unmetered(connectivity);
    _audioCache?.releaseAll();
    await _audioCache?.ensureReady();

    final outgoingSessions = _openSessions.toList();
    _openSessions.clear();

    final rebuilt = <MediaItem>[];
    for (final item in items) {
      final next = _rebuild(item, connectivity);
      // A track that cannot be rebuilt is dropped rather than left as a dead
      // entry the queue would stall on.
      if (next != null) rebuilt.add(next);
    }
    if (rebuilt.isEmpty) return;

    // A re-resolve that lands on the same address changes nothing, and most
    // do — the monitor re-races on every transport change, and the LAN is
    // usually still the LAN. Reloading anyway would interrupt playback, start
    // a fresh transcode session, and at startup would fight the restore that
    // had only just finished.
    if (rebuilt.length == items.length) {
      var identical = true;
      for (var i = 0; i < rebuilt.length; i++) {
        if (rebuilt[i].id != items[i].id) {
          identical = false;
          break;
        }
      }
      if (identical) {
        _openSessions.addAll(outgoingSessions);
        return;
      }
    }

    final resumeIndex = index.clamp(0, rebuilt.length - 1);
    final current = rebuilt[resumeIndex];

    // A transcode cannot be seeked, so it is rebuilt already starting at
    // `resumeAt` and the handler is told the stream begins there. A direct
    // play seeks normally.
    final streamStartsAt = _isTranscode(current) ? resumeAt : Duration.zero;
    if (streamStartsAt > Duration.zero) {
      final url = await _seekUrl(current, resumeAt);
      if (url != null) rebuilt[resumeIndex] = current.copyWith(id: url);
    }

    await _handler.resumeQueue(
      rebuilt,
      index: resumeIndex,
      resumeAt: resumeAt,
      streamStartsAt: streamStartsAt,
    );
    unawaited(save());

    for (final session in outgoingSessions) {
      unawaited(_client.stopTranscodeSession(session));
    }
  }

  static bool _isTranscode(MediaItem item) =>
      item.extras?['qualityDecision'] == QualityDecision.transcode.name;

  /// The same track, decided again and given a URL from the current client.
  MediaItem? _rebuild(MediaItem item, List<ConnectivityResult> connectivity) {
    final extras = item.extras;
    final ratingKey = extras?['ratingKey'] as String?;
    if (ratingKey == null) return null;

    return _build(
      item: item,
      ratingKey: ratingKey,
      partKey: extras?['partKey'] as String?,
      sourceKbps: extras?['sourceKbps'] as int?,
      thumb: extras?['thumb'] as String?,
      albumRatingKey: extras?['albumRatingKey'] as String?,
      source: PlaybackSource.decode(extras?['source']),
      connectivity: connectivity,
    );
  }

  MediaItem? _toMediaItem(
    PlexTrack track,
    List<ConnectivityResult> connectivity,
    PlaybackSource? source,
  ) {
    final art = _client.artworkUrl(track.thumb, width: 600, height: 600);
    return _build(
      item: MediaItem(
        id: '',
        title: track.title,
        album: track.album,
        artist: track.artist,
        duration: track.duration,
        artUri: art == null ? null : Uri.parse(art),
      ),
      ratingKey: track.ratingKey,
      partKey: track.partKey,
      sourceKbps: track.sourceKbps,
      thumb: track.thumb,
      albumRatingKey: track.albumRatingKey,
      source: source,
      connectivity: connectivity,
    );
  }

  /// Decides quality, builds the URL, and records everything a later rebuild
  /// needs.
  ///
  /// [partKey] and [sourceKbps] are carried on the `MediaItem` rather than
  /// looked up again because a rebuild happens when the connection has just
  /// failed — the worst possible moment to need the network or a database
  /// read to answer what the queue already knew.
  MediaItem? _build({
    required MediaItem item,
    required String ratingKey,
    required String? partKey,
    required int? sourceKbps,
    required String? thumb,
    required String? albumRatingKey,
    required PlaybackSource? source,
    required List<ConnectivityResult> connectivity,
  }) {
    final decision = _quality.decide(
      connectivity: connectivity,
      server: _client.server,
      sourceKbps: sourceKbps,
      override: _qualityOverride?.call(
        unmetered: QualityPolicy.unmetered(connectivity),
      ),
    );

    String? url;
    String? session;
    if (decision.isTranscode) {
      session = _newSession();
      _openSessions.add(session);
      url = _client.transcodeUrl(ratingKey, session: session);
    } else {
      url = partKey == null ? null : _client.directPlayUrlFor(partKey);
    }
    if (url == null) return null;

    return item.copyWith(
      // audio_service uses id as the playback URL.
      id: url,
      extras: {
        // Kept around because scrobbling needs it and the URL can't be
        // reversed back into a ratingKey.
        'ratingKey': ratingKey,
        // #24's cache key: (ratingKey, qualityDecision). A copy transcoded
        // for cellular must never be served forever once back on the LAN,
        // which is what keying on ratingKey alone would do.
        'qualityDecision': decision.name,
        'transcodeSession': ?session,
        // The facts a rebuild needs and cannot derive from a URL.
        'partKey': ?partKey,
        'sourceKbps': ?sourceKbps,
        // Carried so the player's own artwork can go through ArtworkCache
        // like every grid does. `artUri` below is a URL and therefore useless
        // as a cache key — it embeds the address and the token, both of which
        // move. Same thumb as the album grid, so the two share one cached
        // file rather than fetching the same image twice.
        'thumb': ?thumb,
        // So Now Playing can offer the album as a destination rather than
        // just a line of text. The track knows its album; the MediaItem did
        // not.
        'albumRatingKey': ?albumRatingKey,
        // What the queue was started from, so "Jump back in" can offer the
        // playlist you actually put on rather than the album a track happens
        // to belong to.
        'source': ?source?.encode(),
      },
    );
  }

  /// Where this track may be cached, or null to stream it straight through.
  ///
  /// Three reasons to decline, and each is a bug if it is got wrong.
  ///
  /// **A URL carrying an `offset`** is the tail of a transcode, not the track.
  /// Cached under the track's key it would be served next time as though it
  /// were the whole thing, and the first two thirds would simply be missing.
  ///
  /// **A metered connection.** `LockCachingAudioSource` downloads the *whole*
  /// file even when you skip after ten seconds, so filling the cache on
  /// cellular spends data on music nobody heard. Playback still works there;
  /// it just streams.
  ///
  /// **No key.** Without a ratingKey and a decision there is nothing safe to
  /// name the file after, and naming it after the URL is invariant 4.
  File? _cacheFile(MediaItem item) {
    final cache = _audioCache;
    if (cache == null || !_cacheFillAllowed) return null;

    final extras = item.extras;
    final ratingKey = extras?['ratingKey'] as String?;
    final decision = extras?['qualityDecision'] as String?;
    if (ratingKey == null || decision == null) return null;

    if (Uri.parse(item.id).queryParameters['offset'] case final o?
        when o != '0') {
      return null;
    }

    final quality = QualityDecision.values
        .where((q) => q.name == decision)
        .firstOrNull;
    if (quality == null) return null;

    return cache.fileFor(AudioKey(ratingKey, quality));
  }

  /// Whether the connection this queue was built on is one worth filling the
  /// cache over. Set alongside the quality decision, from the same reading.
  bool _cacheFillAllowed = false;

  /// The same transcode, restarted at [offset].
  ///
  /// Reuses the session the track is already playing under rather than opening
  /// a new one — Plex replaces the stream for a session it knows, where a
  /// fresh id would leave the old transcode running for nobody.
  Future<String?> _seekUrl(MediaItem item, Duration offset) async {
    final ratingKey = item.extras?['ratingKey'] as String?;
    final session = item.extras?['transcodeSession'] as String?;
    if (ratingKey == null || session == null) return null;
    return _client.transcodeUrl(ratingKey, session: session, offset: offset);
  }

  /// Writes the current queue and position out, so the next launch can pick
  /// it up.
  ///
  /// Cheap enough to call on every queue change and on a timer: a few hundred
  /// small maps through `jsonEncode`, never on the frame path.
  Future<void> save() async {
    final store = _store;
    if (store == null) return;

    final items = _handler.queue.value;
    if (items.isEmpty) return store.clear();

    final index = _handler.currentIndex ?? 0;
    await store.write(
      SavedPlayback(
        tracks: [for (final item in items) _toSaved(item)],
        index: index,
        position: _handler.position,
        source: PlaybackSource.decode(
          items[index.clamp(0, items.length - 1)].extras?['source'],
        ),
      ),
    );
  }

  /// Loads the last session back into the queue, **paused**.
  ///
  /// Paused because opening an app is not the same as asking it to make a
  /// noise — a phone unlocked in a quiet room should not start playing. The
  /// mini player appears with the track it left on and pressing play resumes
  /// where it stopped, which is the behaviour being copied.
  ///
  /// URLs are built fresh rather than restored, so quality is decided against
  /// the network the app has *now*. Nothing here touches Plex or drift: the
  /// stored session carries its own facts, so it restores before the first
  /// sync and while offline.
  Future<void> restore() => _queued(_restore);

  Future<void> _restore() async {
    final saved = _store?.read();
    if (saved == null || saved.isEmpty) return;
    // Never over the top of something already playing. A slow restore racing
    // a user who has already tapped an album must lose.
    if (_handler.queue.value.isNotEmpty) return;

    final connectivity = await _checkConnectivity();
    if (_handler.queue.value.isNotEmpty) return;
    _cacheFillAllowed = QualityPolicy.unmetered(connectivity);
    _audioCache?.releaseAll();
    await _audioCache?.ensureReady();

    final items = <MediaItem>[];
    for (final track in saved.tracks) {
      final item = _build(
        item: MediaItem(
          id: '',
          title: track.title,
          album: track.album,
          artist: track.artist,
          duration: track.durationMs == null
              ? null
              : Duration(milliseconds: track.durationMs!),
        ),
        ratingKey: track.ratingKey,
        partKey: track.partKey,
        sourceKbps: track.sourceKbps,
        thumb: track.thumb,
        albumRatingKey: track.albumRatingKey,
        source: saved.source,
        connectivity: connectivity,
      );
      if (item != null) items.add(item);
    }
    if (items.isEmpty) return;

    final index = saved.index.clamp(0, items.length - 1);
    final current = items[index];
    final streamStartsAt = _isTranscode(current)
        ? saved.position
        : Duration.zero;
    if (streamStartsAt > Duration.zero) {
      final url = await _seekUrl(current, saved.position);
      if (url != null) items[index] = current.copyWith(id: url);
    }

    // `resumeQueue` starts playing only if it was already playing, and at
    // startup nothing is — which is exactly the behaviour wanted here.
    await _handler.resumeQueue(
      items,
      index: index,
      resumeAt: saved.position,
      streamStartsAt: streamStartsAt,
    );
  }

  SavedTrack _toSaved(MediaItem item) {
    final extras = item.extras;
    return SavedTrack(
      ratingKey: extras?['ratingKey'] as String? ?? '',
      title: item.title,
      album: item.album,
      artist: item.artist,
      thumb: extras?['thumb'] as String?,
      partKey: extras?['partKey'] as String?,
      sourceKbps: extras?['sourceKbps'] as int?,
      durationMs: item.duration?.inMilliseconds,
      albumRatingKey: extras?['albumRatingKey'] as String?,
    );
  }

  /// Stops every transcode session this controller still has open.
  ///
  /// Called when the connection this controller belongs to goes away — see
  /// [playbackControllerProvider] — so signing out or switching servers
  /// doesn't leave the old one transcoding for nobody.
  void disposeSessions() {
    // The handler outlives this controller, so a resolver left behind would
    // rebuild seek URLs against a server this app is no longer signed in to.
    if (_handler.resolveSeekUrl == _seekUrl) _handler.resolveSeekUrl = null;
    for (final session in _openSessions) {
      unawaited(_client.stopTranscodeSession(session));
    }
    _openSessions.clear();
  }
}

/// Where the last session is kept. Overridden in `main()` for the same reason
/// `settingsStoreProvider` is: it is only available asynchronously.
final playbackStateStoreProvider = Provider<PlaybackStateStore>(
  (ref) => throw StateError(
    'playbackStateStoreProvider must be overridden in main()',
  ),
);

/// Null until a server connection exists.
final playbackControllerProvider = Provider<PlaybackController?>((ref) {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;
  final controller = PlaybackController(
    handler: ref.watch(audioHandlerProvider),
    client: client,
    store: ref.watch(playbackStateStoreProvider),
    audioCache: ref.watch(audioCacheProvider),
    // Read at the moment a queue is built, not watched: the controller must
    // not be rebuilt because someone changed the theme, and a queue already
    // loaded holds URLs that a new decision could not change anyway.
    qualityOverride: ({required bool unmetered}) =>
        ref.read(settingsProvider).qualityOverrideFor(unmetered: unmetered),
  );
  ref.onDispose(controller.disposeSessions);
  return controller;
});

/// Keeps playback working across a change of server address.
///
/// Two halves of one problem, both invisible without this. **Nothing else can
/// see playback fail**: the audio engine does its own HTTP, so a queue full of
/// dead URLs never reaches [ConnectionHealth] and the reconnect waits on the
/// 30-second poll to notice something the user noticed immediately. And
/// **nothing else rebuilds the queue**: re-resolving replaces the client, but
/// the URLs already handed to the engine keep pointing at the old address, so
/// skipping forward finds one dead track after another.
///
/// A playback failure is reported as a *trigger* on the existing recovery
/// path rather than as a new one, per invariant 9.
///
/// Nothing reads its value — it exists for its side effects, so [AppShell]
/// watches it to keep it alive for the session.
final playbackRecoveryProvider = Provider<void>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final health = ref.watch(connectionHealthProvider);

  handler.onPlaybackFailed = health.recordUnreachable;
  ref.onDispose(() => handler.onPlaybackFailed = null);

  // Watched, not read: this rebuilds whenever the connection re-resolves,
  // which is precisely when the queue needs rebuilding too.
  final controller = ref.watch(playbackControllerProvider);
  if (controller == null) return;

  // On the first build there is no queue to rescue, so this is where the last
  // session comes back instead. Ordered this way round deliberately: a
  // restore that ran unconditionally could overwrite a queue the rebuild had
  // just repaired.
  if (handler.queue.value.isEmpty) {
    unawaited(controller.restore());
  } else {
    unawaited(controller.resumeOnNewConnection());
  }

  // Position is not worth a write per frame, and a write per track would lose
  // most of a long one. Ten seconds costs nothing and is the resolution
  // anyone would notice.
  final ticker = Timer.periodic(
    const Duration(seconds: 10),
    (_) => unawaited(controller.save()),
  );
  ref.onDispose(ticker.cancel);
});
