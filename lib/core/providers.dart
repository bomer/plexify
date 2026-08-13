import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../features/acquire/acquire_controller.dart';
import '../features/acquire/slskd_acquire_controller.dart';
import 'acquire/download_monitor.dart';
import 'acquire/download_source.dart';
import 'slskd/slskd_client.dart';
import 'slskd/slskd_credentials.dart';
import 'package:flutter/painting.dart' show Color, ImageProvider;

import 'artwork/artwork_cache.dart';
import 'artwork/artwork_image.dart';
import 'artwork/dominant_colour.dart';
import 'audio/audio_cache.dart';
import 'audio/playback_handler.dart';
import 'audio/timeline_reporter.dart';
import 'catalog/catalog_matcher.dart';
import 'catalog/catalog_models.dart';
import 'catalog/catalog_service.dart';
import 'catalog/catalog_store.dart';
import 'catalog/musicbrainz_client.dart';
import 'db/app_database.dart';
import 'db/mappers.dart';
import 'db/normalise.dart';
import 'db/shelf_item.dart';
import 'discovery/discovery.dart';
import 'qbit/qbit_client.dart';
import 'qbit/qbit_credentials.dart';
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
///
/// The budget is *read* at construction and *listened* to afterwards, never
/// watched: watching would rebuild the cache on every change, which is the one
/// thing the sentence above says must not happen. The listener is created with
/// the instance and lives exactly as long as it does, so an instance that
/// exists always has the current budget.
final artworkCacheProvider = Provider<ArtworkCache>((ref) {
  final settings = ref.read(settingsProvider);
  final cache = ArtworkCache(maxBytes: settings.artworkCacheMaxBytes);
  ref.listen(
    settingsProvider.select((s) => s.artworkCacheMaxBytes),
    (_, next) => unawaited(cache.applyBudget(next)),
  );
  return cache;
});

/// Audio on disk.
///
/// One instance for the app's lifetime, like the artwork cache and for the
/// same reason: it holds the in-memory index that makes eviction possible. It
/// also holds the in-use set, which is the stronger reason — see
/// [AudioCache.applyBudget].
final audioCacheProvider = Provider<AudioCache>((ref) {
  final settings = ref.read(settingsProvider);
  final cache = AudioCache(maxBytes: settings.audioCacheMaxBytes);
  ref.listen(
    settingsProvider.select((s) => s.audioCacheMaxBytes),
    (_, next) => unawaited(cache.applyBudget(next)),
  );
  return cache;
});

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
    // True when the app wants a connection and has never got one. Signing out
    // makes it false, so the retry does not run on the login screen.
    needsConnection: () =>
        ref.read(authTokenProvider) != null &&
        ref.read(plexServerProvider) == null,
    reconnect: () async {
      // Invalidating rebuilds the client, the notification socket and the sync
      // scheduler against whichever address wins the race this time. The album
      // grid streams from drift, so the UI does not blank while that happens —
      // the additive-cache rule paying for itself.
      final before = ref.read(plexServerProvider)?.baseUrl;
      ref.invalidate(connectServerProvider);
      final after = (await ref.read(connectServerProvider.future))?.baseUrl;
      // Reported rather than assumed. Discovery keeps the last address that
      // worked when nothing answers, so "the future resolved" is not the same
      // as "we moved". See ConnectionMonitor.
      return after != null && after != before;
    },
  );
  monitor.start();
  // Re-arms the disconnected retry whenever the app drops back to having no
  // server — signing out and back into one that will not answer, most of all.
  // Without this the retry loop could only ever be started by a launch that
  // failed, and every later route to having nothing would be a dead end again.
  ref.listen(plexServerProvider, (_, next) {
    if (next == null) unawaited(monitor.retryIfDisconnected());
  });
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
    required this.musicSections,
    required this.serverArtists,
    required this.serverAlbums,
    required this.serverTracks,
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

  /// Titles of every music section on the server.
  ///
  /// More than one means the sync is only ever seeing the first, because
  /// [PlexClient.musicSection] takes the first and v1 assumes there is one.
  /// That is the first thing to check when the cached counts are short.
  final List<String> musicSections;

  /// What Plex says the synced section holds, or null if it would not say.
  final int? serverArtists;
  final int? serverAlbums;
  final int? serverTracks;

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

/// What each disk cache is holding, and what it is allowed to hold.
class CacheUsage {
  const CacheUsage({
    required this.audioFiles,
    required this.audioBytes,
    required this.audioBudget,
    required this.artworkFiles,
    required this.artworkBytes,
    required this.artworkBudget,
  });

  final int audioFiles;
  final int audioBytes;
  final int audioBudget;
  final int artworkFiles;
  final int artworkBytes;
  final int artworkBudget;
}

/// Measures both caches, and enforces their budgets while it is at it.
///
/// Both indexes are built lazily by use, so on a cold start with nothing played
/// and no image shown they are empty while the directories are not. Reporting
/// that as "0 bytes" on the one screen whose job is to say how much space this
/// app is taking would be worse than saying nothing.
///
/// Watching the two budgets is what makes the numbers move when one is lowered:
/// the eviction below runs in the same pass, so the figure shown is what is
/// left afterwards rather than what was there before.
final cacheUsageProvider = FutureProvider<CacheUsage>((ref) async {
  // Selected rather than watching the whole object, so changing the theme does
  // not rescan two directories.
  final audioBudget = ref.watch(
    settingsProvider.select((s) => s.audioCacheMaxBytes),
  );
  final artworkBudget = ref.watch(
    settingsProvider.select((s) => s.artworkCacheMaxBytes),
  );

  final audio = ref.watch(audioCacheProvider);
  final artwork = ref.watch(artworkCacheProvider);

  await audio.applyBudget(audioBudget);
  await audio.ensureReady();
  await audio.settle();

  await artwork.applyBudget(artworkBudget);
  await artwork.ensureReady();

  return CacheUsage(
    audioFiles: audio.entryCount,
    audioBytes: audio.bytesHeld,
    audioBudget: audio.maxBytes,
    artworkFiles: artwork.entryCount,
    artworkBytes: artwork.bytesHeld,
    artworkBudget: artwork.maxBytes,
  );
});

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
  //
  // **Every music section, not just the one being synced.** `musicSection()`
  // takes the first and v1 assumes there is only one, which is fine until
  // there are two: the second's music is then invisible with nothing on screen
  // to say so, and the symptom is a track count lower than Plex's own.
  var musicSections = <PlexSection>[];
  try {
    musicSections = [
      for (final s in await client?.sections() ?? const <PlexSection>[])
        if (s.isMusic) s,
    ];
  } on Object {
    musicSections = const [];
  }
  final section = musicSections.firstOrNull;

  // What Plex says the section holds, next to what the cache holds. The two
  // disagreeing is the only way to tell a sync that has not finished from one
  // that finished and missed something, and they looked identical before.
  int? serverTracks;
  int? serverAlbums;
  int? serverArtists;
  if (client != null && section != null) {
    try {
      serverArtists = await client.sectionCount(
        section.key,
        type: PlexClient.typeArtist,
      );
      serverAlbums = await client.sectionCount(
        section.key,
        type: PlexClient.typeAlbum,
      );
      serverTracks = await client.sectionCount(
        section.key,
        type: PlexClient.typeTrack,
      );
    } on Object {
      // Diagnostic. A server that will not answer leaves these blank rather
      // than failing the whole screen.
    }
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
      ReconnectReason.neverConnected => 'Never connected this session',
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
    musicSections: [for (final s in musicSections) s.title],
    serverArtists: serverArtists,
    serverAlbums: serverAlbums,
    serverTracks: serverTracks,
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
/// Whether the Artists list is filtered to favourites.
///
/// Separate from `albumFavouritesOnlyProvider` rather than shared: the two
/// lists are looked at for different reasons and remembering them together
/// would mean filtering one hid the other.
final artistFavouritesOnlyProvider = StateProvider<bool>((ref) => false);

final artistsProvider = StreamProvider<List<PlexArtist>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final favouritesOnly = ref.watch(artistFavouritesOnlyProvider);
  await for (final rows in db.watchArtists(favouritesOnly: favouritesOnly)) {
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
/// How the Playlists list is ordered. Not persisted: it is a way of looking
/// through a list, like the album sort beside it, rather than a preference.
final playlistSortProvider = StateProvider<PlaylistSort>(
  (ref) => PlaylistSort.recent,
);

final playlistsProvider = StreamProvider<List<PlexPlaylist>>((ref) async* {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(plexClientProvider);
  final sort = ref.watch(playlistSortProvider);

  await for (final rows in db.watchPlaylists(sort: sort)) {
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

/// The playlists shown directly in the sidebar, most recently opened first.
///
/// **Its own query rather than a slice of [playlistsProvider].** That one now
/// follows whatever sort the Playlists screen is set to, and taking the first
/// few of an A to Z list would quietly turn the sidebar into an alphabetical
/// stub the moment someone changed the sort on another screen.
final recentPlaylistsProvider = StreamProvider<List<PlexPlaylist>>((
  ref,
) async* {
  final db = ref.watch(databaseProvider);
  final limit = ref.watch(settingsProvider.select((s) => s.sidebarPlaylists));
  if (limit <= 0) {
    yield const [];
    return;
  }

  await for (final rows in db.watchPlaylists(limit: limit)) {
    yield [for (final row in rows) row.toDomain()];
  }
});

/// Albums this device started playing, newest first.
final recentlyPlayedAlbumsProvider = StreamProvider<List<ShelfItem>>((
  ref,
) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchRecentlyPlayedAlbums()) {
    yield [
      for (final (row, startedAt) in rows)
        ShelfItem.album(row.toDomain(), startedAt),
    ];
  }
});

/// Playlists this device started playing, newest first.
final recentlyPlayedPlaylistsProvider = StreamProvider<List<ShelfItem>>((
  ref,
) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchRecentlyPlayedPlaylists()) {
    yield [
      for (final (row, startedAt) in rows)
        ShelfItem.playlist(row.toDomain(), startedAt),
    ];
  }
});

/// Home's "Jump back in", from this device and from every other one.
///
/// The local half is merged in Dart rather than in SQL because albums and
/// playlists live in different tables with no sensible join, and the lists are
/// twenty rows each: sorting them here costs nothing and keeps both queries
/// simple and separately testable.
///
/// **The server half is what makes this survive a new phone.** See
/// [jumpBackIn] for why it is a union of the two rather than a choice between
/// them. It resolves asynchronously and the row is populated from the local
/// table in the meantime, so a cold start is never waiting on the network for
/// a shelf it could already draw.
final recentlyPlayedProvider = Provider<AsyncValue<List<ShelfItem>>>((ref) {
  final albums = ref.watch(recentlyPlayedAlbumsProvider);
  final playlists = ref.watch(recentlyPlayedPlaylistsProvider);

  if (albums.isLoading && playlists.isLoading) {
    return const AsyncValue<List<ShelfItem>>.loading();
  }

  final local = <ShelfItem>[
    ...albums.valueOrNull ?? const <ShelfItem>[],
    ...playlists.valueOrNull ?? const <ShelfItem>[],
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final merged = ref.watch(_serverPlaysProvider).valueOrNull;
  if (merged == null) return AsyncValue.data(local.take(20).toList());

  return AsyncValue.data(
    jumpBackIn(
      local: local,
      serverPlays: merged.plays,
      albumOfTrack: merged.albumOfTrack,
      owned: merged.owned,
    ),
  );
});

/// The server's play history, with everything needed to turn it into tiles.
///
/// Fetched once per session rather than watched. It is one request against an
/// endpoint that answers with a thousand rows, and the local half of the shelf
/// already updates live, so re-asking on every rebuild would buy nothing.
final _serverPlaysProvider = FutureProvider<_ServerPlays?>((ref) async {
  final client = ref.watch(plexClientProvider);
  final section = await ref.watch(musicSectionProvider.future);
  if (client == null || section == null) return null;

  final plays = await client.playHistory(section.key);
  if (plays.isEmpty) return null;

  // Plex's history rows name the track and not the album, so the link comes
  // from the synced tracks table. Artwork and titles come from the cache too,
  // which is why this costs one request however many albums come back.
  final db = ref.watch(databaseProvider);
  final albumOfTrack = await db.albumKeysForTracks(
    plays.map((play) => play.trackRatingKey),
  );
  final rows = await db.albumsByKeys({
    for (final play in plays)
      ?(play.albumRatingKey ?? albumOfTrack[play.trackRatingKey]),
  });

  return _ServerPlays(
    plays: plays,
    albumOfTrack: albumOfTrack,
    owned: {for (final row in rows) row.ratingKey: row.toDomain()},
  );
});

class _ServerPlays {
  const _ServerPlays({
    required this.plays,
    required this.albumOfTrack,
    required this.owned,
  });

  final List<PlexPlay> plays;
  final Map<String, String> albumOfTrack;
  final Map<String, PlexAlbum> owned;
}

/// Albums added most recently, for Home.
final recentlyAddedProvider = StreamProvider<List<PlexAlbum>>((ref) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchRecentlyAddedAlbums()) {
    yield rows.map((r) => r.toDomain()).toList();
  }
});

// ---------------------------------------------------------------------------
// Discovery shelves.
//
// The rows on Home that are not simply "what you did lately". Four of them,
// deliberately split down the middle: two read the local cache and are on
// screen before the first frame is painted, two ask the server and appear a
// moment later or never.
//
// **Every one of them is nullable, and null means the row does not exist.**
// None of these is load-bearing. A server that is unreachable, that does not
// grant history to this account, or that has no genre tags produces a Home
// screen with fewer rows on it, never an error and never a spinner. That is
// the whole reason the client methods behind them swallow their failures.
// ---------------------------------------------------------------------------

/// How long an album has to sit unplayed before it counts as buried.
///
/// Ninety days rather than a week: the point is the part of the library that
/// has fallen out of view, and everything added in the last month is still on
/// the "Recently added" row two shelves up.
const _buriedAfter = Duration(days: 90);

/// "Buried treasure" — albums nothing has ever played, reshuffled daily.
final buriedTreasureShelfProvider = StreamProvider<DiscoveryShelf?>((
  ref,
) async* {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final cutoff =
      now.subtract(_buriedAfter).millisecondsSinceEpoch ~/
      Duration.millisecondsPerSecond;

  await for (final rows in db.watchNeverPlayedAlbums(addedBefore: cutoff)) {
    yield buriedTreasureShelf([
      for (final row in rows) row.toDomain(),
    ], seed: daySeed(now));
  }
});

/// The rows the server publishes for this library, in the order it lists them.
///
/// **This replaces three hand-rolled approximations of rows Plex was already
/// offering.** "More by {artist}", "More in {genre}" and "Most played in
/// {month}" were each built here from scratch, and `/hubs/sections` names all
/// three, fills them, orders them, and adds several nobody had thought of: top
/// albums from a decade, artists not played in five years, sonic stations. Two
/// bugs lived in the versions this deletes and neither could have existed in
/// this one, because none of the work is ours.
///
/// **Nothing is keyed on a hub identifier.** What a section publishes varies by
/// server version and by whether sonic analysis has run, so a row is rendered
/// because it arrived with a title and some albums, not because it was
/// recognised. That also means a server upgrade can only ever add rows here.
///
/// Album hubs only, for now. Artists, stations and music videos each need a
/// tile and a tap this app does not have, and a heading with nothing under it
/// is worse than an absent row.
final hubShelvesProvider = FutureProvider<List<DiscoveryShelf>>((ref) async {
  final client = ref.watch(plexClientProvider);
  final section = await ref.watch(musicSectionProvider.future);
  if (client == null || section == null) return const [];

  return [
    for (final hub in await client.sectionHubs(section.key))
      if (!_duplicatesALocalShelf.contains(hub.kind))
        ?DiscoveryShelf.of(hub.title, _tilesFor(hub)),
  ];
});

/// Whichever of a hub's three item kinds it turned out to hold.
///
/// Stations are the odd one and were dropped for a while because of it: they
/// are the only tiles that play rather than open, since a station's key is a
/// play queue source and cannot be fetched at all.
List<ShelfItem> _tilesFor(PlexHub hub) {
  if (hub.albums.isNotEmpty) return DiscoveryShelf.albums(hub.albums);
  if (hub.artists.isNotEmpty) return DiscoveryShelf.artists(hub.artists);
  return DiscoveryShelf.stations(hub.stations);
}

/// Hubs skipped because a local row already answers them, faster.
///
/// Recently added is on screen before the first frame from the cache and is the
/// same six albums the server would send a moment later. The rest of the hubs
/// have no local equivalent, which is why they are worth the request.
///
/// Matched against [PlexHub.kind] and not the raw identifier, which carries the
/// section id on the end.
const _duplicatesALocalShelf = {'music.recent.added'};

/// A colour taken from one piece of artwork, for tinting behind it.
///
/// Asks for the artwork at the size the transport bar already uses, so this is
/// a hit on an image that is almost always decoded already rather than a second
/// fetch of the same sleeve at a size nothing displays.
///
/// Null is a normal answer, not a failure to handle: no artwork, a sleeve that
/// will not decode, a disconnected server, or a cover with nothing in it but
/// black and white. Every caller falls back to the theme.
final artworkColourProvider = FutureProvider.family<Color?, String>((
  ref,
  thumb,
) async {
  if (thumb.isEmpty) return null;
  final url = ref
      .watch(plexClientProvider)
      ?.artworkUrl(thumb, width: 300, height: 300);

  final ImageProvider provider = PlexArtwork(
    thumb: thumb,
    size: 300,
    cache: ref.watch(artworkCacheProvider),
    url: url,
  );
  return colourOfImage(provider);
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

/// One album from the cache, for turning a name on screen into a destination.
///
/// Null when the cache has not reached it. The caller shows plain text rather
/// than a link in that case, which is better than a tappable name that opens
/// an empty page.
final albumByKeyProvider = FutureProvider.autoDispose
    .family<PlexAlbum?, String>((ref, ratingKey) async {
      final db = ref.watch(databaseProvider);
      final row = await (db.select(
        db.albums,
      )..where((a) => a.ratingKey.equals(ratingKey))).getSingleOrNull();
      return row?.toDomain();
    });

/// One artist's rating, live.
///
/// Narrower than watching the whole row so the header does not rebuild on
/// unrelated sync writes, and the same shape as `watchTrackRating`.
final artistRatingProvider = StreamProvider.autoDispose.family<int?, String>((
  ref,
  ratingKey,
) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.artists)
    ..where((a) => a.ratingKey.equals(ratingKey));
  return query.watchSingleOrNull().map((row) => row?.userRating).distinct();
});

/// One artist from the cache. See [albumByKeyProvider].
final artistByKeyProvider = FutureProvider.autoDispose
    .family<PlexArtist?, String>((ref, ratingKey) async {
      final db = ref.watch(databaseProvider);
      final row = await (db.select(
        db.artists,
      )..where((a) => a.ratingKey.equals(ratingKey))).getSingleOrNull();
      return row?.toDomain();
    });

// ---------------------------------------------------------------------------
// The catalog: records that exist, as opposed to records you own.
//
// Everything below here is gated on `settings.catalogEnabled` and does nothing
// at all when it is off — no client is built, no request is made, and the two
// places it surfaces render nothing. That is the point of the switch: on a
// phone this is noise, and "off" has to mean off rather than hidden.
// ---------------------------------------------------------------------------

/// Whether to look up records the library does not hold.
final catalogEnabledProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider.select((s) => s.catalogEnabled)),
);

/// The MusicBrainz web service.
///
/// One instance for the app's lifetime, because the pacing queue lives inside
/// it: rebuilding it would reset the clock that keeps requests a second apart,
/// which is the one thing the rate limit cares about.
final musicBrainzClientProvider = Provider<MusicBrainzClient>((ref) {
  final client = MusicBrainzClient();
  ref.onDispose(client.close);
  return client;
});

final catalogServiceProvider = Provider<CatalogService>(
  (ref) => CatalogService(
    client: ref.watch(musicBrainzClientProvider),
    store: CatalogStore(ref.watch(databaseProvider)),
  ),
);

/// Which albums the library already holds, as a set of match keys.
///
/// A stream rather than a future so a download that lands and syncs disappears
/// from "missing" on its own, which is the one moment anybody is looking
/// closely. `autoDispose` because rebuilding this on every album write during a
/// first sync is only affordable while something is actually watching.
final ownedIndexProvider = StreamProvider.autoDispose<OwnedIndex>((ref) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchAlbumIdentities()) {
    yield OwnedIndex([
      for (final row in rows)
        OwnedAlbum(title: row.title, artist: row.artist, mbid: row.mbid),
    ]);
  }
});

/// Records matching a search, minus the ones already in the library.
///
/// Deliberately a separate provider from [searchResultsProvider] rather than
/// another field on it. The two tiers have to be able to arrive at different
/// times: local results are on screen in milliseconds and this one is paced
/// behind a rate limit, and folding them into one future would make the fast
/// half wait for the slow half — which is precisely what the two-tier design
/// exists to prevent.
final catalogSearchProvider = FutureProvider.autoDispose
    .family<List<CatalogRelease>, String>((ref, query) async {
      if (!ref.watch(catalogEnabledProvider)) return const [];
      if (query.trim().length < 3) return const [];

      final releases = await ref.watch(catalogServiceProvider).search(query);

      final owned = await ref.watch(ownedIndexProvider.future);
      // Primary works only. A search for an artist otherwise returns forty
      // compilations before the record anybody meant.
      return owned.missingFrom(releases.where((r) => r.isPrimaryWork));
    });

/// Artists matching a search who are not in the library at all.
///
/// **The way in to a record by somebody you own nothing by.** Without this the
/// catalog tier can only offer individual albums, so finding a band means
/// recognising one of their records by name; there is no "show me everything
/// they made".
///
/// Costs one paced MusicBrainz request beyond the album search, which is
/// affordable for exactly the reason the two-tier design exists: this sits
/// below results that are already on screen, and being slow here can never make
/// the library feel slow.
final catalogArtistSearchProvider = FutureProvider.autoDispose
    .family<List<CatalogArtist>, String>((ref, query) async {
      if (!ref.watch(catalogEnabledProvider)) return const [];
      if (query.trim().length < 3) return const [];

      final found = await ref.watch(catalogServiceProvider).artistsMatching(
        query,
      );
      if (found.isEmpty) return const [];

      // Anyone already in the library belongs to the tier above, and listing
      // them twice invites downloading records that are already there.
      // Normalised because the library spells performers however the file tags
      // did and MusicBrainz spells them canonically.
      final mine = {
        for (final artist in await ref.watch(databaseProvider).watchArtists().first)
          normalise(artist.title),
      };

      final seen = <String>{};
      return [
        for (final artist in found)
          if (artist.name.isNotEmpty &&
              !mine.contains(normalise(artist.name)) &&
              seen.add(artist.mbid))
            artist,
      ];
    });

/// One unowned artist's records.
///
/// Keyed on the mbid alone, unlike [missingAlbumsProvider], because there is no
/// library artist to diff against and nothing here needs a name to ask about.
final catalogDiscographyProvider = FutureProvider.autoDispose
    .family<Discography, String>((ref, mbid) async {
      if (!ref.watch(catalogEnabledProvider)) {
        return const Discography.unknownArtist();
      }
      return ref.watch(catalogServiceProvider).discographyForMbid(mbid);
    });

/// What an artist released that the library does not have.
///
/// Keyed on the ratingKey *and* the name because both are needed and neither is
/// derivable from the other here: the name is what MusicBrainz is asked about,
/// and the ratingKey is what the library is asked about. A record is used so
/// the family key compares structurally.
typedef ArtistRef = ({String ratingKey, String name});

final missingAlbumsProvider = FutureProvider.autoDispose
    .family<MissingAlbums, ArtistRef>((ref, artist) async {
      if (!ref.watch(catalogEnabledProvider)) return const MissingAlbums.off();

      final db = ref.watch(databaseProvider);
      final discography = await ref
          .watch(catalogServiceProvider)
          .discographyFor(artist.name);

      if (!discography.resolved) return const MissingAlbums.unresolved();

      // Matched against this artist's own albums, with the artist name itself
      // left out of the comparison. The library spells performers however the
      // file tags did — "Beatles, The", "Bowie, David" — and MusicBrainz spells
      // them canonically, so requiring both to agree would report a complete
      // discography as entirely missing.
      final owned = OwnedIndex([
        for (final row in await db.albumIdentitiesForArtist(artist.ratingKey))
          OwnedAlbum(title: row.title, artist: row.artist, mbid: row.mbid),
      ], requireArtist: false);

      final missing = owned.missingFrom(
        discography.releases.where((r) => r.isPrimaryWork),
      );
      missing.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));

      return MissingAlbums(
        releases: missing,
        matchedName: discography.artistName,
        totalKnown: discography.releases.where((r) => r.isPrimaryWork).length,
      );
    });

/// The albums an artist made and the library does not have.
class MissingAlbums {
  const MissingAlbums({
    required this.releases,
    this.matchedName,
    this.totalKnown = 0,
  }) : state = MissingAlbumsState.ready;

  const MissingAlbums.off()
    : releases = const [],
      matchedName = null,
      totalKnown = 0,
      state = MissingAlbumsState.disabled;

  const MissingAlbums.unresolved()
    : releases = const [],
      matchedName = null,
      totalKnown = 0,
      state = MissingAlbumsState.unresolved;

  final List<CatalogRelease> releases;

  /// What MusicBrainz called this artist. Shown when it differs from the
  /// library's spelling, so a wrong match is visible rather than presenting as
  /// a discography full of records the artist never made.
  final String? matchedName;

  /// How many primary works MusicBrainz lists in total, so the count can read
  /// "4 of 19 missing" rather than a bare number with nothing to compare it to.
  final int totalKnown;

  final MissingAlbumsState state;
}

enum MissingAlbumsState {
  /// The setting is off. Nothing was asked and nothing is shown.
  disabled,

  /// MusicBrainz has nobody by this name, or nobody confidently enough. A real
  /// answer, and distinct from "no albums missing".
  unresolved,

  ready,
}

// ---------------------------------------------------------------------------
// qBittorrent.
// ---------------------------------------------------------------------------

final qbitCredentialsProvider = Provider<QbitCredentials>(
  (ref) => QbitCredentials(),
);

/// A configured qBittorrent client, or null.
///
/// Null for three different reasons that all mean the same thing to a caller —
/// no address set, no credentials saved, or the catalog switch off — so they
/// collapse into one. The screens that use this all have something sensible to
/// show for null, which is a link into Settings.
///
/// A future because the credentials come from the platform keystore, which is
/// asynchronous. Rebuilt whenever the address changes, so saving a new one in
/// Settings takes effect without a restart.
final qbitClientProvider = FutureProvider<QbitClient?>((ref) async {
  if (!ref.watch(catalogEnabledProvider)) return null;

  final url = ref.watch(settingsProvider.select((s) => s.qbitUrl));
  if (url == null || url.isEmpty) return null;

  final saved = await ref.watch(qbitCredentialsProvider).read();
  final username = saved.username;
  final password = saved.password;
  if (username == null || username.isEmpty || password == null) return null;

  final client = QbitClient(
    baseUrl: url,
    username: username,
    password: password,
  );
  ref.onDispose(client.close);
  return client;
});

// ---------------------------------------------------------------------------
// slskd, and choosing between the two download sources.
// ---------------------------------------------------------------------------

final slskdCredentialsProvider = Provider<SlskdCredentials>(
  (ref) => SlskdCredentials(),
);

/// A configured slskd client, or null.
///
/// Null for the same three reasons `qbitClientProvider` is, collapsed the same
/// way: the catalog is off, no address, or no API key. Rebuilt when the address
/// changes so saving a new one takes effect without a restart.
final slskdClientProvider = FutureProvider<SlskdClient?>((ref) async {
  if (!ref.watch(catalogEnabledProvider)) return null;

  final url = ref.watch(settingsProvider.select((s) => s.slskdUrl));
  if (url == null || url.isEmpty) return null;

  final apiKey = await ref.watch(slskdCredentialsProvider).read();
  if (apiKey == null || apiKey.isEmpty) return null;

  final client = SlskdClient(baseUrl: url, apiKey: apiKey);
  ref.onDispose(client.close);
  return client;
});

/// Which source the user chose. Read on its own so screens that only need the
/// name do not wait on a client being built.
final downloadSourceKindProvider = Provider<DownloadSourceKind>(
  (ref) => ref.watch(settingsProvider.select((s) => s.downloadSource)),
);

/// The one source that does the downloading, or null when it is not set up.
///
/// **Only the chosen one is ever built.** The other client is never
/// constructed, so an slskd address left over from an experiment costs no
/// requests while qBittorrent is selected.
final downloadSourceProvider = FutureProvider<DownloadSource?>((ref) async {
  switch (ref.watch(downloadSourceKindProvider)) {
    case DownloadSourceKind.qbittorrent:
      final client = await ref.watch(qbitClientProvider.future);
      return client == null ? null : AcquireController(client);
    case DownloadSourceKind.soulseek:
      final client = await ref.watch(slskdClientProvider.future);
      return client == null ? null : SlskdAcquireController(client);
  }
});

/// Watches what is arriving and asks Plex to rescan when something lands.
///
/// Nothing reads its value — it exists for its side effects, like
/// [liveSyncProvider], so [AppShell] watches it to keep it alive for the
/// session. Null when the chosen source is not configured, so a phone with the
/// catalog switched off never makes a request.
final downloadMonitorProvider = Provider<DownloadMonitor?>((ref) {
  final poll = switch (ref.watch(downloadSourceKindProvider)) {
    DownloadSourceKind.qbittorrent => switch (ref
        .watch(qbitClientProvider)
        .valueOrNull) {
      final client? => () async => [
        for (final torrent in await client.torrents()) torrent.asJob,
      ],
      null => null,
    },
    DownloadSourceKind.soulseek => switch (ref
        .watch(slskdClientProvider)
        .valueOrNull) {
      final client? => () async => [
        for (final download in await client.downloads()) download.asJob,
      ],
      null => null,
    },
  };
  if (poll == null) return null;

  final monitor = DownloadMonitor(
    poll: poll,
    onComplete: () async {
      // The same two steps the refresh button runs, in the same order: ask Plex
      // to look at the disk, then sync what it found. Deliberately not a new
      // path into the cache (invariant 10) — a download is one more trigger for
      // machinery that already exists.
      final plex = ref.read(plexClientProvider);
      final section = await ref.read(musicSectionProvider.future);
      if (plex != null && section != null) {
        await plex.refreshSection(section.key);
      }
      await ref.read(syncSchedulerProvider)?.refreshNow();
    },
  );
  monitor.start();
  ref.onDispose(monitor.stop);
  return monitor;
});

/// What is arriving, live.
final downloadsProvider = StreamProvider<List<DownloadJob>>((ref) {
  final monitor = ref.watch(downloadMonitorProvider);
  if (monitor == null) return const Stream<List<DownloadJob>>.empty();
  // Seeded with whatever the last poll saw, so opening the screen shows the
  // current state rather than waiting out an interval for the next tick.
  return monitor.jobs.transform(
    StreamTransformer.fromBind((stream) async* {
      yield monitor.latest;
      yield* stream;
    }),
  );
});
