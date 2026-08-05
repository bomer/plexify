import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'artwork/artwork_cache.dart';
import 'audio/audio_cache.dart';
import 'audio/playback_handler.dart';
import 'audio/timeline_reporter.dart';
import 'db/app_database.dart';
import 'db/mappers.dart';
import 'db/recently_played.dart';
import 'plex/connection_health.dart';
import 'plex/connection_monitor.dart';
import 'plex/plex_auth.dart';
import 'plex/plex_client.dart';
import 'plex/plex_identity.dart';
import 'plex/plex_models.dart';
import 'plex/plex_notifications.dart';
import 'plex/plex_server.dart';
import 'settings/app_settings.dart';
import 'sync/library_sync.dart';
import 'sync/library_writer.dart';
import 'sync/live_sync.dart';
import 'sync/sync_scheduler.dart';

/// The application's provider graph.
///
/// Declared explicitly rather than generated, so the dependencies between these
/// are readable top to bottom without needing to understand build_runner.
///
/// Two providers ([plexIdentityProvider] and [audioHandlerProvider]) are only
/// available asynchronously at startup, so they throw here and are replaced with
/// real values via `overrides` in `main.dart`. Reading one before that override
/// is a programming error, and failing loudly is better than handing back a
/// half-initialised audio engine. `settingsStoreProvider`, in
/// `settings/app_settings.dart`, is overridden the same way and for the same
/// reason.

final plexIdentityProvider = Provider<PlexIdentity>(
  (ref) =>
      throw StateError('plexIdentityProvider must be overridden in main()'),
);

final audioHandlerProvider = Provider<PlexifyAudioHandler>(
  (ref) =>
      throw StateError('audioHandlerProvider must be overridden in main()'),
);

/// Artwork on disk.
///
/// One instance for the app's lifetime — it holds the in-memory index that
/// makes eviction possible, and rebuilding it would mean rescanning the
/// directory. Not tied to the connection: cached images render with no server
/// at all, which is what lets a grid draw while offline.
final artworkCacheProvider = Provider<ArtworkCache>((ref) => ArtworkCache());

/// Audio on disk.
///
/// One instance for the app's lifetime, like the artwork cache and for the
/// same reason: it holds the in-memory index that makes eviction possible.
final audioCacheProvider = Provider<AudioCache>((ref) => AudioCache());

/// The local library cache.
///
/// Single instance for the app's lifetime — drift holds an open SQLite
/// connection, so rebuilding this provider would leak file handles.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final plexAuthProvider = Provider<PlexAuth>(
  (ref) => PlexAuth(identity: ref.watch(plexIdentityProvider)),
);

final plexDiscoveryProvider = Provider<PlexDiscovery>((ref) {
  final discovery = PlexDiscovery(identity: ref.watch(plexIdentityProvider));
  ref.onDispose(discovery.close);
  return discovery;
});

/// The stored Plex account token, or null when signed out.
///
/// Seeded at startup from secure storage so a returning user skips the link
/// flow entirely.
final authTokenProvider = StateProvider<String?>((ref) => null);

/// Connects to a server on the account.
///
/// Returns null when nothing could be reached, which the UI surfaces as a retry
/// rather than an error — being off the LAN is normal, not exceptional.
///
/// **Which server** depends on whether the user has chosen one. With no
/// preference — the normal case, and the only one on a single-server account —
/// the first that answers wins. With a preference set, *only* that server is
/// tried. Falling back to a different one would be actively harmful: the two
/// libraries have overlapping ratingKeys, so each connection would wipe the
/// other's cache and resync from scratch, and a server that comes and goes
/// would leave the app thrashing between two full syncs.
///
/// Falling back to the last address that worked is deliberate, and the reason
/// is not cosmetic. Resolving to null would leave no client; with no client
/// nothing makes requests; with no requests [ConnectionHealth] can never see
/// another failure, so nothing would ever trigger another attempt. The app
/// would sit disconnected until the OS happened to report a network change or
/// the user found the button in Settings. Keeping the stale address keeps the
/// poll running, and the failures it produces are exactly what drives the next
/// retry.
///
/// Nothing is lost by holding it: browsing reads from drift, and artwork
/// already falls back to a placeholder when a request fails.
final connectServerProvider = FutureProvider<PlexServer?>((ref) async {
  final sticky = ref.watch(_lastGoodServerProvider);
  final token = ref.watch(authTokenProvider);
  final preferred = ref.watch(
    settingsProvider.select((s) => s.preferredServerId),
  );

  // Signing out is a real disconnection, not a failed lookup.
  if (token == null) {
    sticky.value = null;
    return null;
  }

  // The last-good address is only good for the server we still want. Holding
  // one from a server the user has just switched away from would hand it
  // straight back the moment the new one failed to answer.
  if (preferred != null && sticky.value?.clientIdentifier != preferred) {
    sticky.value = null;
  }

  final discovery = ref.watch(plexDiscoveryProvider);

  try {
    final servers = await discovery.listServers(token);
    for (final resource in servers) {
      if (preferred != null && resource.clientIdentifier != preferred) continue;
      final connected = await discovery.connect(resource, accountToken: token);
      if (connected != null) {
        sticky.value = connected;
        return connected;
      }
    }
  } on Object {
    // Listing servers goes to plex.tv, which is unreachable on exactly the
    // occasions this matters most. An error here is not a signed-out state.
  }

  return sticky.value;
});

/// Every server on the account, for the picker. Not probed for reachability.
///
/// Deliberately not `keepAlive`: this is a plex.tv round trip that only the
/// picker needs, and a stale list is worse than a fresh one — a server added
/// since launch should appear.
final accountServersProvider = FutureProvider.autoDispose<List<PlexResource>>((
  ref,
) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) return const [];
  return ref.watch(plexDiscoveryProvider).listServers(token);
});

/// Holds a value across rebuilds of the provider that computes it.
class _Sticky<T> {
  T? value;
}

/// The last address that answered, kept so a failed re-resolve does not drop
/// the app to "not connected".
final _lastGoodServerProvider = Provider<_Sticky<PlexServer>>(
  (ref) => _Sticky<PlexServer>(),
);

/// The connected server, or null while connecting or if nothing was reachable.
final plexServerProvider = Provider<PlexServer?>(
  (ref) => ref.watch(connectServerProvider).valueOrNull,
);

/// Null until both a token and a reachable server exist.
///
/// Derived straight from [connectServerProvider] rather than mirrored into
/// mutable state. An earlier version published the server via a microtask,
/// which let the album list build one frame early with a null client and flash
/// "No albums found" before correcting itself.
///
/// Rebuilt whenever [connectServerProvider] is invalidated, which is how a
/// change of network reaches every caller at once: the socket, the scheduler
/// and every screen all watch downstream of here.
final plexClientProvider = Provider<PlexClient?>((ref) {
  final server = ref.watch(plexServerProvider);
  if (server == null) return null;
  final client = PlexClient(
    server: server,
    identity: ref.watch(plexIdentityProvider),
    // Wrapped so every request reports whether it reached anything. This is the
    // only way the app finds out that the address chosen at startup has stopped
    // working.
    httpClient: HealthReportingClient(
      http.Client(),
      ref.watch(connectionHealthProvider),
    ),
  );
  ref.onDispose(client.close);
  return client;
});

/// Whether the current connection is reaching the server.
///
/// Lives for the life of the app, deliberately outside the client it observes —
/// it has to survive the reconnect it triggers.
final connectionHealthProvider = Provider<ConnectionHealth>((ref) {
  final health = ConnectionHealth();
  ref.onDispose(health.dispose);
  return health;
});

/// Transport changes reported by the OS.
///
/// Says a network appeared or went away, not that anything is reachable
/// through it — a wifi network with no route out still reports as connected.
/// Useful only as a prompt to re-check.
final networkChangesProvider = Provider<Stream<void>>(
  (ref) => Connectivity().onConnectivityChanged.map((_) {}),
);

/// Re-resolves the server connection when the current one stops working.
///
/// Nothing reads its value; it exists for its side effects, so something must
/// `watch` it for the triggers to be wired up at all. [AppShell] does.
final connectionMonitorProvider = Provider<ConnectionMonitor>((ref) {
  final monitor = ConnectionMonitor(
    health: ref.watch(connectionHealthProvider),
    networkChanges: ref.watch(networkChangesProvider),
    reconnect: () async {
      // Invalidating rebuilds the client, the notification socket and the sync
      // scheduler against whichever address wins the race this time. The album
      // grid streams from drift, so the UI does not blank while that happens —
      // the additive-cache rule paying for itself.
      ref.invalidate(connectServerProvider);
      await ref.read(connectServerProvider.future);
    },
  );
  monitor.start();
  ref.onDispose(monitor.stop);
  return monitor;
});

/// Whether a reconnect is in flight, for the mini player to say so.
///
/// A reconnect takes seconds and playback has usually just stopped, so the
/// alternative to showing this is a silent player that looks broken.
final reconnectingProvider = StreamProvider<bool>((ref) {
  final monitor = ref.watch(connectionMonitorProvider);
  return monitor.reconnectingChanges;
});

/// The music library section on the connected server.
final musicSectionProvider = FutureProvider<PlexSection?>((ref) async {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;
  return client.musicSection();
});

/// How the album grid is sorted.
final albumSortProvider = StateProvider<AlbumSort>(
  (ref) => AlbumSort.recentlyAdded,
);

/// Albums, read from the local cache.
///
/// A stream, so the grid fills progressively as sync writes pages rather than
/// appearing only once sync finishes.
///
/// Reading from cache is what makes browsing instant, but it must never be the
/// reason something is missing. While the cache is still empty this falls
/// through to a live Plex read, so a fresh install is usable during the first
/// sync rather than showing "no albums".
final albumsProvider = StreamProvider<List<PlexAlbum>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final sort = ref.watch(albumSortProvider);
  final favouritesOnly = ref.watch(albumFavouritesOnlyProvider);

  await for (final rows in db.watchAlbums(
    sort: sort,
    favouritesOnly: favouritesOnly,
  )) {
    // The live fallback is unfiltered, so it must not stand in for an empty
    // favourites result — "no favourites yet" is a real answer, not a cold
    // cache.
    if (favouritesOnly) {
      yield rows.map((r) => r.toDomain()).toList();
      continue;
    }
    if (rows.isEmpty) {
      final fallback = await ref.read(albumsFallbackProvider.future);
      if (fallback.isNotEmpty) {
        yield fallback;
        continue;
      }
    }
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// Whether the album grid is filtered to favourites.
final albumFavouritesOnlyProvider = StateProvider<bool>((ref) => false);

/// Favourite albums — four stars or better.
final favouriteAlbumsProvider = StreamProvider<List<PlexAlbum>>((ref) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchFavouriteAlbums()) {
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// One track's rating, live from the cache.
final trackRatingProvider = StreamProvider.family<int?, String>((
  ref,
  ratingKey,
) {
  return ref.watch(databaseProvider).watchTrackRating(ratingKey);
});

/// Favourite tracks — four stars or better.
final favouriteTracksProvider = StreamProvider<List<PlexTrack>>((ref) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchFavouriteTracks()) {
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// Live Plex read, used only while the cache is still empty.
final albumsFallbackProvider = FutureProvider<List<PlexAlbum>>((ref) async {
  final client = ref.watch(plexClientProvider);
  final section = await ref.watch(musicSectionProvider.future);
  if (client == null || section == null) return const [];
  return client.albums(section.key);
});

/// Owns when the library syncs: once at startup, then on a cheap poll.
///
/// Held as its own provider so pull-to-refresh and the app-resume hook have
/// something to call. Nothing awaits it — browsing must never block on sync.
final syncSchedulerProvider = Provider<SyncScheduler?>((ref) {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;

  final scheduler = SyncScheduler(
    client: client,
    db: ref.watch(databaseProvider),
  );
  unawaited(scheduler.start());
  ref.onDispose(scheduler.stop);
  return scheduler;
});

/// Sync progress, for the banner.
final librarySyncProvider = StreamProvider<SyncProgress>((ref) {
  final scheduler = ref.watch(syncSchedulerProvider);
  if (scheduler == null) return const Stream<SyncProgress>.empty();
  return scheduler.progress;
});

/// The push-notification connection to Plex.
///
/// Held separately from [liveSyncProvider] so the app-resume hook has something
/// to prod: the OS routinely kills sockets while backgrounded, and waiting out
/// a backoff to notice would reintroduce exactly the lag this removes.
final plexNotificationSocketProvider = Provider<PlexNotificationSocket?>((ref) {
  final server = ref.watch(plexServerProvider);
  if (server == null) return null;

  final socket = PlexNotificationSocket(
    server: server,
    identity: ref.watch(plexIdentityProvider),
  );
  socket.start();
  ref.onDispose(socket.stop);
  return socket;
});

/// Applies pushed changes to the cache.
///
/// Nothing reads this provider's value — it exists for its side effects, so
/// something must `watch` it for the connection to be made at all. [AppShell]
/// does, for the lifetime of the signed-in session.
final liveSyncProvider = Provider<LiveSync?>((ref) {
  final client = ref.watch(plexClientProvider);
  final socket = ref.watch(plexNotificationSocketProvider);
  if (client == null || socket == null) return null;

  final sync = LiveSync(
    client: client,
    db: ref.watch(databaseProvider),
    changes: socket.changes,
  );
  sync.start();
  ref.onDispose(sync.stop);
  return sync;
});

/// Reports playback to Plex so history stays in one place.
///
/// Like [liveSyncProvider], nothing reads its value — it exists for its side
/// effects, so [AppShell] watches it to keep it alive for the session.
final timelineReporterProvider = Provider<TimelineReporter?>((ref) {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;

  final handler = ref.watch(audioHandlerProvider);
  final reporter = TimelineReporter(
    client: client,
    writer: LibraryWriter(ref.watch(databaseProvider)),
    mediaItems: handler.mediaItem,
    playbackStates: handler.playbackState,
    // A getter rather than the position stream, which fires five times a
    // second for a reporter that needs it every ten. The handler's own
    // position rather than the player's, because a seeked transcode runs on a
    // stream that restarted at an offset — the player's clock would report a
    // track two thirds through as barely started, and the scrobble would
    // never fire.
    position: () => handler.position,
  );
  reporter.start();
  ref.onDispose(reporter.stop);
  return reporter;
});

/// Everything the sync layer knows about itself, gathered for the status
/// screen.
///
/// Read on demand rather than streamed: this is a diagnostic snapshot, and a
/// live-updating one would be harder to read, not easier.
class SyncDiagnostics {
  const SyncDiagnostics({
    required this.serverName,
    required this.serverUrl,
    required this.route,
    required this.failedRequests,
    required this.reconnects,
    required this.lastReconnectAt,
    required this.lastReconnectReason,
    required this.timelineReports,
    required this.scrobbles,
    required this.lastReportAt,
    required this.reportError,
    required this.socketConnected,
    required this.framesReceived,
    required this.changesSeen,
    required this.changesApplied,
    required this.lastFrameAt,
    required this.socketError,
    required this.lastPollAt,
    required this.lastSyncAt,
    required this.passes,
    required this.isSyncing,
    required this.syncError,
    required this.lastSyncRowCount,
    required this.storedUpdatedAt,
    required this.serverUpdatedAt,
    required this.storedScannedAt,
    required this.serverScannedAt,
    required this.cursor,
    required this.initialSyncComplete,
    required this.artists,
    required this.albums,
    required this.tracks,
    required this.playlists,
    required this.ratedAlbums,
    required this.artworkHits,
    required this.artworkMisses,
    required this.artworkFetchFailures,
    required this.artworkSkippedNoUrl,
    required this.artworkFiles,
    required this.artworkBytes,
    required this.artworkError,
    required this.audioFiles,
    required this.audioBytes,
    required this.audioEvictions,
    required this.audioError,
  });

  final String? serverName;
  final String? serverUrl;
  final String route;

  /// Requests in a row that reached nothing. Non-zero here while everything
  /// else looks healthy is the signature of an address that has gone stale.
  final int failedRequests;
  final int reconnects;
  final DateTime? lastReconnectAt;
  final String? lastReconnectReason;

  /// Plays reported to Plex. Zero after listening to something is the whole
  /// symptom of history quietly not being recorded.
  final int timelineReports;
  final int scrobbles;
  final DateTime? lastReportAt;
  final String? reportError;

  final bool socketConnected;
  final int framesReceived;
  final int changesSeen;
  final int changesApplied;
  final DateTime? lastFrameAt;
  final String? socketError;

  final DateTime? lastPollAt;
  final DateTime? lastSyncAt;
  final int passes;
  final bool isSyncing;
  final String? syncError;
  final int lastSyncRowCount;

  final int? storedUpdatedAt;
  final int? serverUpdatedAt;
  final int? storedScannedAt;
  final int? serverScannedAt;
  final int? cursor;
  final bool initialSyncComplete;

  final int artists;
  final int albums;
  final int tracks;
  final int playlists;
  final int ratedAlbums;

  /// Artwork cache. Blank thumbnails are the one failure with three completely
  /// different causes that look identical on screen, so all three are counted
  /// separately: served from disk, fetched, refused by Plex, and asked for
  /// before a connection existed.
  final int artworkHits;
  final int artworkMisses;
  final int artworkFetchFailures;
  final int artworkSkippedNoUrl;
  final int artworkFiles;
  final int artworkBytes;
  final String? artworkError;

  /// Audio cache. Evictions climbing fast is the signal the budget is too
  /// small for how the library is actually being listened to.
  final int audioFiles;
  final int audioBytes;
  final int audioEvictions;
  final String? audioError;
}

final syncDiagnosticsProvider = FutureProvider<SyncDiagnostics>((ref) async {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(plexClientProvider);
  final server = ref.watch(plexServerProvider);
  final socket = ref.watch(plexNotificationSocketProvider);
  final scheduler = ref.watch(syncSchedulerProvider);
  final live = ref.watch(liveSyncProvider);
  final health = ref.watch(connectionHealthProvider);
  final monitor = ref.watch(connectionMonitorProvider);
  final reporter = ref.watch(timelineReporterProvider);
  final artwork = ref.watch(artworkCacheProvider);
  final audio = ref.watch(audioCacheProvider);

  // Asked live, so the stored clocks can be compared against what Plex says
  // right now — the comparison that decides whether a sync happens at all.
  PlexSection? section;
  try {
    section = await client?.musicSection();
  } on Object {
    section = null;
  }

  final state = await db.select(db.syncState).get();
  final row = state.isEmpty ? null : state.first;

  return SyncDiagnostics(
    serverName: server?.name,
    serverUrl: server?.baseUrl,
    route: server?.routeLabel ?? '—',
    failedRequests: health.consecutiveFailures,
    reconnects: monitor.attempts,
    lastReconnectAt: monitor.lastAttemptAt,
    lastReconnectReason: switch (monitor.lastReason) {
      ReconnectReason.networkChanged => 'The network changed',
      ReconnectReason.connectionLost => 'Requests stopped arriving',
      ReconnectReason.manual => 'Asked for it',
      null => null,
    },
    timelineReports: reporter?.reports ?? 0,
    scrobbles: reporter?.scrobbles ?? 0,
    lastReportAt: reporter?.lastReportAt,
    reportError: reporter?.lastError,
    socketConnected: socket?.isConnected ?? false,
    framesReceived: socket?.framesReceived ?? 0,
    changesSeen: socket?.changesSeen ?? 0,
    changesApplied: live?.applied ?? 0,
    lastFrameAt: socket?.lastFrameAt,
    socketError: socket?.lastError,
    lastPollAt: scheduler?.lastPollAt,
    lastSyncAt: scheduler?.lastSyncAt,
    passes: scheduler?.passes ?? 0,
    isSyncing: scheduler?.isSyncing ?? false,
    syncError: scheduler?.lastError,
    lastSyncRowCount: scheduler?.lastSyncRowCount ?? 0,
    storedUpdatedAt: row?.serverUpdatedAt,
    serverUpdatedAt: section?.updatedAt,
    storedScannedAt: row?.serverScannedAt,
    serverScannedAt: section?.scannedAt,
    cursor: row?.lastSyncedUpdatedAt,
    initialSyncComplete: row?.initialSyncComplete ?? false,
    artists: await db.countArtists(),
    albums: await db.countAlbums(),
    tracks: await db.countTracks(),
    playlists: await db.countPlaylists(),
    ratedAlbums: await db.countRatedAlbums(),
    artworkHits: artwork.hits,
    artworkMisses: artwork.misses,
    artworkFetchFailures: artwork.fetchFailures,
    artworkSkippedNoUrl: artwork.skippedNoUrl,
    artworkFiles: artwork.entryCount,
    artworkBytes: artwork.bytesHeld,
    artworkError: artwork.lastError,
    audioFiles: audio.entryCount,
    audioBytes: audio.bytesHeld,
    audioEvictions: audio.evictions,
    audioError: audio.lastError,
  );
});

/// Artists, alphabetically.
final artistsProvider = StreamProvider<List<PlexArtist>>((ref) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchArtists()) {
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// One artist's albums, oldest first.
///
/// Falls back to a live Plex read when the cache has nothing for this artist —
/// an artist page opened before sync reaches them must still show their work
/// rather than looking like an empty discography.
final artistAlbumsProvider = StreamProvider.family<List<PlexAlbum>, String>((
  ref,
  artistRatingKey,
) async* {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(plexClientProvider);

  await for (final rows in db.watchAlbumsForArtist(artistRatingKey)) {
    if (rows.isEmpty && client != null) {
      try {
        final live = await client.albumsForArtist(artistRatingKey);
        if (live.isNotEmpty) {
          yield live;
          continue;
        }
      } on Object {
        // Fall through to the empty cached list.
      }
    }
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// Every track by an artist, in discography order.
final artistTracksProvider = StreamProvider.family<List<PlexTrack>, String>((
  ref,
  artistRatingKey,
) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchTracksForArtist(artistRatingKey)) {
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// Playlists, most recently played first.
///
/// Falls through to a live Plex read while the cache is empty, for the same
/// reason albums do: the sidebar must be usable during the first sync.
final playlistsProvider = StreamProvider<List<PlexPlaylist>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(plexClientProvider);

  await for (final rows in db.watchPlaylists()) {
    if (rows.isEmpty && client != null) {
      try {
        final live = await client.playlists();
        if (live.isNotEmpty) {
          yield live;
          continue;
        }
      } on Object {
        // Fall through to the empty cached list.
      }
    }
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// The handful of playlists shown directly in the sidebar.
final recentPlaylistsProvider = Provider<AsyncValue<List<PlexPlaylist>>>((ref) {
  return ref.watch(playlistsProvider).whenData((all) => all.take(8).toList());
});

/// Albums this device started playing, newest first.
final recentlyPlayedAlbumsProvider = StreamProvider<List<RecentlyPlayed>>((
  ref,
) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchRecentlyPlayedAlbums()) {
    yield [
      for (final (row, startedAt) in rows)
        RecentlyPlayed.album(row.toDomain(), startedAt),
    ];
  }
});

/// Playlists this device started playing, newest first.
final recentlyPlayedPlaylistsProvider = StreamProvider<List<RecentlyPlayed>>((
  ref,
) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchRecentlyPlayedPlaylists()) {
    yield [
      for (final (row, startedAt) in rows)
        RecentlyPlayed.playlist(row.toDomain(), startedAt),
    ];
  }
});

/// What was listened to, of either kind, newest first — Home's "Jump back in".
///
/// Merged here rather than in SQL because the two live in different tables
/// with no sensible join, and the lists are twenty rows each: sorting them in
/// Dart costs nothing and keeps both queries simple and separately testable.
///
/// Loading only while *both* are, so the shelf does not flash a half-list on
/// the way in.
final recentlyPlayedProvider = Provider<AsyncValue<List<RecentlyPlayed>>>((
  ref,
) {
  final albums = ref.watch(recentlyPlayedAlbumsProvider);
  final playlists = ref.watch(recentlyPlayedPlaylistsProvider);

  if (albums.isLoading && playlists.isLoading) {
    return const AsyncValue<List<RecentlyPlayed>>.loading();
  }

  final merged = <RecentlyPlayed>[
    ...albums.valueOrNull ?? const <RecentlyPlayed>[],
    ...playlists.valueOrNull ?? const <RecentlyPlayed>[],
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  return AsyncValue.data(merged.take(20).toList());
});

/// Albums added most recently, for Home.
final recentlyAddedProvider = StreamProvider<List<PlexAlbum>>((ref) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchRecentlyAddedAlbums()) {
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// Tracks in a playlist, cached with write-through on open.
///
/// Playlist items are not synced up front — one request per playlist for data
/// mostly never looked at — so the first open fetches from Plex and stores the
/// result. Subsequent opens are instant, and still revalidate.
final playlistTracksProvider = StreamProvider.family<List<PlexTrack>, String>((
  ref,
  playlistRatingKey,
) async* {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(plexClientProvider);

  if (client != null) {
    unawaited(_revalidatePlaylist(db, client, playlistRatingKey));
  }

  // Smart playlist contents are generated server-side from rules and change
  // without an updatedAt bump, so a cached copy goes stale silently. Wait for
  // the refresh rather than showing what we had last time.
  final row = await (db.select(
    db.playlists,
  )..where((p) => p.ratingKey.equals(playlistRatingKey))).getSingleOrNull();

  if ((row?.smart ?? false) && client != null) {
    try {
      final live = await client.playlistItems(playlistRatingKey);
      if (live.isNotEmpty) yield live;
    } on Object {
      // Fall through to whatever is cached.
    }
  }

  await for (final rows in db.watchPlaylistTracks(playlistRatingKey)) {
    if (rows.isEmpty && client != null) {
      final live = await client.playlistItems(playlistRatingKey);
      if (live.isNotEmpty) {
        yield live;
        continue;
      }
    }
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// Fetches a playlist's items and writes them through to the cache.
///
/// Tracks are upserted too, because a playlist can reference a track the
/// section walk has not reached yet — without this the join would drop it and
/// the playlist would silently render short.
Future<void> _revalidatePlaylist(
  AppDatabase db,
  PlexClient client,
  String playlistRatingKey,
) async {
  try {
    final live = await client.playlistItems(playlistRatingKey);
    if (live.isEmpty) return;

    await LibraryWriter(db).writeTracks(live);

    await db.replacePlaylistItems(playlistRatingKey, [
      for (final (index, track) in live.indexed)
        PlaylistItemsCompanion.insert(
          playlistRatingKey: playlistRatingKey,
          trackRatingKey: track.ratingKey,
          position: index,
        ),
    ]);
  } on Object {
    // Cached content stays on screen.
  }
}

/// Tracks for one album, keyed by its ratingKey.
///
/// Stale-while-revalidate: cached tracks render immediately, then Plex is asked
/// in the background and any differences are written through — the stream then
/// re-emits on its own.
///
/// If the cache holds nothing for this album, Plex is queried directly. That is
/// the additive rule in practice: an album the sync has not reached yet must
/// still open and play, not appear empty.
final tracksProvider = StreamProvider.family<List<PlexTrack>, String>((
  ref,
  albumRatingKey,
) async* {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(plexClientProvider);

  // Kick off revalidation without blocking the first frame.
  if (client != null) {
    unawaited(_revalidateAlbumTracks(db, client, albumRatingKey));
  }

  await for (final rows in db.watchTracksForAlbum(albumRatingKey)) {
    if (rows.isEmpty && client != null) {
      final live = await client.tracks(albumRatingKey);
      if (live.isNotEmpty) {
        yield live;
        continue;
      }
    }
    yield rows.map((r) => r.toDomain()).toList();
  }
});

/// Fetches an album's tracks from Plex and writes them through to the cache.
///
/// Failures are swallowed: this runs behind whatever is already on screen, and
/// a network blip should not surface as an error over content that rendered
/// perfectly well from cache.
Future<void> _revalidateAlbumTracks(
  AppDatabase db,
  PlexClient client,
  String albumRatingKey,
) async {
  try {
    final live = await client.tracks(albumRatingKey);
    if (live.isEmpty) return;

    await LibraryWriter(
      db,
    ).writeTracks(live, fallbackAlbumRatingKey: albumRatingKey);
  } on Object {
    // Cached content stays on screen; nothing to surface.
  }
}

/// What the user has typed into the search box.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Search results: the cache immediately, the server merged in behind it.
///
/// Local first and independently, which is what makes typing feel instant.
/// The server read then adds anything the cache has not reached, because the
/// cache is additive and must never be the reason something appears missing
/// (invariant 1) - an album added five minutes ago has to be findable.
///
/// Deduplicated on ratingKey, so a server result already in the cache does not
/// appear twice.
final searchResultsProvider = FutureProvider.autoDispose
    .family<SearchResults, String>((ref, query) async {
      if (query.trim().isEmpty) return const SearchResults.empty();

      final local = await ref.watch(databaseProvider).search(query);
      final artists = [for (final a in local.artists) a.toDomain()];
      final albums = [for (final a in local.albums) a.toDomain()];
      final tracks = [for (final t in local.tracks) t.toDomain()];

      final client = ref.watch(plexClientProvider);
      if (client != null) {
        final (liveAlbums, liveTracks) = await client.searchHubs(query);
        final seenAlbums = {for (final a in albums) a.ratingKey};
        final seenTracks = {for (final t in tracks) t.ratingKey};
        albums.addAll(liveAlbums.where((a) => seenAlbums.add(a.ratingKey)));
        tracks.addAll(liveTracks.where((t) => seenTracks.add(t.ratingKey)));
      }

      return SearchResults(artists: artists, albums: albums, tracks: tracks);
    });

/// Search results in the models the UI already speaks.
class SearchResults {
  const SearchResults({
    required this.artists,
    required this.albums,
    required this.tracks,
  });

  const SearchResults.empty()
    : artists = const [],
      albums = const [],
      tracks = const [];

  final List<PlexArtist> artists;
  final List<PlexAlbum> albums;
  final List<PlexTrack> tracks;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && tracks.isEmpty;
}
