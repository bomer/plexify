import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/playback_handler.dart';
import 'db/app_database.dart';
import 'db/mappers.dart';
import 'db/normalise.dart';
import 'plex/plex_auth.dart';
import 'plex/plex_client.dart';
import 'plex/plex_identity.dart';
import 'plex/plex_models.dart';
import 'plex/plex_server.dart';
import 'sync/library_sync.dart';

/// The application's provider graph.
///
/// Declared explicitly rather than generated, so the dependencies between these
/// are readable top to bottom without needing to understand build_runner.
///
/// Two providers ([plexIdentityProvider] and [audioHandlerProvider]) are only
/// available asynchronously at startup, so they throw here and are replaced with
/// real values via `overrides` in `main.dart`. Reading one before that override
/// is a programming error, and failing loudly is better than handing back a
/// half-initialised audio engine.

final plexIdentityProvider = Provider<PlexIdentity>(
  (ref) =>
      throw StateError('plexIdentityProvider must be overridden in main()'),
);

final audioHandlerProvider = Provider<PlexifyAudioHandler>(
  (ref) =>
      throw StateError('audioHandlerProvider must be overridden in main()'),
);

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

/// Connects to the first reachable server on the account.
///
/// v1 assumes a single server; a picker comes later if that turns out to be
/// wrong. Returns null when nothing could be reached, which the UI surfaces as
/// a retry rather than an error — being off the LAN is normal, not exceptional.
final connectServerProvider = FutureProvider<PlexServer?>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) return null;

  final discovery = ref.watch(plexDiscoveryProvider);
  final servers = await discovery.listServers(token);

  for (final resource in servers) {
    final connected = await discovery.connect(resource, accountToken: token);
    if (connected != null) return connected;
  }
  return null;
});

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
final plexClientProvider = Provider<PlexClient?>((ref) {
  final server = ref.watch(plexServerProvider);
  if (server == null) return null;
  final client = PlexClient(
    server: server,
    identity: ref.watch(plexIdentityProvider),
  );
  ref.onDispose(client.close);
  return client;
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

/// Runs the library sync and reports progress.
///
/// Starts as soon as a server and music section are available, and resumes
/// rather than restarts: if a previous run finished, only rows changed since
/// its cursor are fetched; if it was interrupted, `initialSyncComplete` is
/// still false and the full pass runs again.
///
/// Deliberately not awaited by anything — browsing must never block on sync.
final librarySyncProvider = StreamProvider<SyncProgress>((ref) async* {
  final client = ref.watch(plexClientProvider);
  if (client == null) return;

  final section = await ref.watch(musicSectionProvider.future);
  if (section == null) return;

  final db = ref.watch(databaseProvider);

  final existing = await (db.select(
    db.syncState,
  )..where((s) => s.sectionKey.equals(section.key))).getSingleOrNull();

  // Only trust the delta cursor if a full pass previously completed against
  // this same server. Otherwise start from scratch.
  final resumable =
      existing != null &&
      existing.initialSyncComplete &&
      existing.serverClientIdentifier == client.server.clientIdentifier;

  yield* LibrarySync(client: client, db: db).run(
    section,
    serverClientIdentifier: client.server.clientIdentifier,
    minUpdatedAt: resumable ? existing.lastSyncedUpdatedAt : 0,
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

/// Albums played most recently, for Home.
final recentlyPlayedProvider = StreamProvider<List<PlexAlbum>>((ref) async* {
  final db = ref.watch(databaseProvider);
  await for (final rows in db.watchRecentlyPlayedAlbums()) {
    yield rows.map((r) => r.toDomain()).toList();
  }
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

    await db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        db.tracks,
        live.map(
          (t) => TracksCompanion.insert(
            ratingKey: t.ratingKey,
            title: t.title,
            normalisedTitle: normalise(t.title),
            albumRatingKey: Value(t.albumRatingKey),
            albumTitle: Value(t.album),
            artistTitle: Value(t.artist),
            trackIndex: Value(t.index),
            discIndex: Value(t.discIndex),
            durationMs: Value(t.durationMs),
            partKey: Value(t.partKey),
            container: Value(t.container),
            thumb: Value(t.thumb),
            updatedAt: Value(t.updatedAt),
            addedAt: Value(t.addedAt),
            lastViewedAt: Value(t.lastViewedAt),
            userRating: Value(t.userRating),
          ),
        ),
      );
    });

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

    await db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        db.tracks,
        live.map(
          (t) => TracksCompanion.insert(
            ratingKey: t.ratingKey,
            title: t.title,
            normalisedTitle: normalise(t.title),
            albumRatingKey: Value(t.albumRatingKey ?? albumRatingKey),
            albumTitle: Value(t.album),
            artistTitle: Value(t.artist),
            trackIndex: Value(t.index),
            discIndex: Value(t.discIndex),
            durationMs: Value(t.durationMs),
            partKey: Value(t.partKey),
            container: Value(t.container),
            thumb: Value(t.thumb),
            updatedAt: Value(t.updatedAt),
            addedAt: Value(t.addedAt),
            lastViewedAt: Value(t.lastViewedAt),
            userRating: Value(t.userRating),
          ),
        ),
      );
    });
  } on Object {
    // Cached content stays on screen; nothing to surface.
  }
}
