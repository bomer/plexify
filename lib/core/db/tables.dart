import 'package:drift/drift.dart';

/// Local mirror of the Plex music library.
///
/// Every row carries the Plex `ratingKey` as its primary key. Those keys are
/// only unique **within a server**, so [SyncState] records which server the
/// cache belongs to and the sync layer wipes everything if that changes —
/// otherwise switching servers would silently blend two libraries together.
///
/// `updatedAt` is stored on every entity because it is what drives delta sync:
/// we ask Plex only for rows newer than the last successful sync.

@TableIndex(name: 'idx_artists_norm', columns: {#normalisedTitle})
@TableIndex(name: 'idx_artists_rating', columns: {#userRating})
class Artists extends Table {
  TextColumn get ratingKey => text()();
  TextColumn get title => text()();

  /// Punctuation-folded, lowercased copy of [title], indexed so search can hit
  /// it directly instead of normalising every row at query time.
  TextColumn get normalisedTitle => text()();

  TextColumn get thumb => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();
  IntColumn get addedAt => integer().nullable()();

  /// Plex `userRating`, 0-10, null when unrated. Indexed for the same reason
  /// as the album column: the Artists list filters on it.
  IntColumn get userRating => integer().nullable()();

  @override
  Set<Column> get primaryKey => {ratingKey};
}

@TableIndex(name: 'idx_albums_norm_title', columns: {#normalisedTitle})
@TableIndex(name: 'idx_albums_norm_artist', columns: {#normalisedArtist})
@TableIndex(name: 'idx_albums_artist_key', columns: {#artistRatingKey})
@TableIndex(name: 'idx_albums_added', columns: {#addedAt})
@TableIndex(name: 'idx_albums_rating', columns: {#userRating})
class Albums extends Table {
  TextColumn get ratingKey => text()();
  TextColumn get title => text()();
  TextColumn get normalisedTitle => text()();

  /// Plex exposes the album artist as `parentRatingKey` / `parentTitle`.
  TextColumn get artistRatingKey => text().nullable()();
  TextColumn get artistTitle => text()();
  TextColumn get normalisedArtist => text()();

  TextColumn get thumb => text().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get updatedAt => integer().nullable()();

  /// Indexed because "recently added" on the Home screen sorts by it.
  IntColumn get addedAt => integer().nullable()();

  /// Set when Plex reports a play. Drives "recently played".
  IntColumn get lastViewedAt => integer().nullable()();

  /// MusicBrainz release-group id, when Plex knows one.
  ///
  /// Phase 5 uses this to filter owned albums out of the "Not in your library"
  /// search tier. Where it is null, matching falls back to
  /// [normalisedArtist] + [normalisedTitle].
  TextColumn get mbid => text().nullable()();

  /// Plex `userRating`, 0–10, null when unrated. Indexed because the Favourites
  /// view and filters query on it.
  IntColumn get userRating => integer().nullable()();

  @override
  Set<Column> get primaryKey => {ratingKey};
}

@TableIndex(name: 'idx_tracks_norm', columns: {#normalisedTitle})
@TableIndex(name: 'idx_tracks_album', columns: {#albumRatingKey})
class Tracks extends Table {
  TextColumn get ratingKey => text()();
  TextColumn get title => text()();
  TextColumn get normalisedTitle => text()();

  TextColumn get albumRatingKey => text().nullable()();
  TextColumn get albumTitle => text().withDefault(const Constant(''))();
  TextColumn get artistTitle => text().withDefault(const Constant(''))();

  /// Track number within the album.
  IntColumn get trackIndex => integer().withDefault(const Constant(0))();

  IntColumn get discIndex => integer().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// Path to the actual file, e.g. `/library/parts/5678/1699.../file.flac`.
  /// Null means the track has no playable part.
  TextColumn get partKey => text().nullable()();

  /// Container format — used by the quality policy to decide whether the
  /// current platform can direct-play or needs a transcode.
  TextColumn get container => text().nullable()();

  /// Media > Part's own `size`, in bytes. Source bitrate is derived from this
  /// and [durationMs] rather than stored directly, so the quality policy asks
  /// nothing Plex didn't already send.
  IntColumn get partSizeBytes => integer().nullable()();

  TextColumn get thumb => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();
  IntColumn get addedAt => integer().nullable()();
  IntColumn get lastViewedAt => integer().nullable()();

  /// Plex `userRating`, 0–10, null when unrated.
  IntColumn get userRating => integer().nullable()();

  @override
  Set<Column> get primaryKey => {ratingKey};
}

@TableIndex(name: 'idx_playlists_viewed', columns: {#lastViewedAt})
class Playlists extends Table {
  TextColumn get ratingKey => text()();
  TextColumn get title => text()();
  TextColumn get normalisedTitle => text()();
  TextColumn get thumb => text().nullable()();
  IntColumn get itemCount => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get updatedAt => integer().nullable()();

  /// Indexed because the sidebar lists playlists by most recently played,
  /// which was a headline requirement.
  IntColumn get lastViewedAt => integer().nullable()();

  /// True for Plex smart playlists.
  ///
  /// Their contents are computed server-side and change without an `updatedAt`
  /// bump, so a cached copy goes stale silently — these must be revalidated on
  /// open rather than served cache-first.
  BoolColumn get smart => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {ratingKey};
}

@TableIndex(name: 'idx_playlist_items_playlist', columns: {#playlistRatingKey})
class PlaylistItems extends Table {
  TextColumn get playlistRatingKey => text()();
  TextColumn get trackRatingKey => text()();

  /// Explicit ordering — playlists are not sorted, they are arranged.
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {playlistRatingKey, position};
}

/// One row per library section, tracking how far sync has got.
///
/// [serverClientIdentifier] guards against ratingKey collisions: those keys are
/// unique per server, so pointing the app at a different server must invalidate
/// the whole cache rather than merge two libraries.
class SyncState extends Table {
  TextColumn get sectionKey => text()();
  TextColumn get serverClientIdentifier => text()();

  /// Our clock: the newest `updatedAt` we have successfully stored. Delta sync
  /// asks Plex only for rows at or after this.
  IntColumn get lastSyncedUpdatedAt =>
      integer().withDefault(const Constant(0))();

  /// Plex's clock, from `/library/sections`. Comparing these two is the cheap
  /// change-detection tier — one small response tells us whether a delta sync
  /// is worth doing at all.
  IntColumn get serverUpdatedAt => integer().nullable()();
  IntColumn get serverScannedAt => integer().nullable()();

  /// False until the first full pass finishes, so an interrupted initial sync
  /// resumes rather than being mistaken for an up-to-date cache.
  BoolColumn get initialSyncComplete =>
      boolean().withDefault(const Constant(false))();

  /// Wall-clock time of the last completed reconcile, which is how deletions
  /// are eventually noticed.
  IntColumn get lastReconcileAt => integer().nullable()();

  /// Wall-clock time of the last delta sweep, in milliseconds since the epoch.
  ///
  /// Persisted rather than held in memory because the sweep interval is meant
  /// to be five minutes of *elapsed time*, not five minutes of uptime. Kept in
  /// the scheduler alone it reset on every launch, so quitting and reopening
  /// ran a full sweep every time: ten relaunches in an hour meant ten sweeps
  /// of a library nothing had touched.
  IntColumn get lastDeltaSweepAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sectionKey};
}

/// What *this user on this device* started playing, and when.
///
/// Deliberately not `Albums.lastViewedAt`, which was the first attempt and
/// failed twice over. That column belongs to Plex: it is written by every
/// sync, so an album Plex stamped server-side reappeared on the shelf however
/// carefully the local write was suppressed — and it was only ever written at
/// the 90% scrobble mark, so putting a playlist on and leaving recorded
/// nothing at all.
///
/// This table is client-owned. Nothing in the sync path writes it, so nothing
/// can overwrite it, and it is stamped the moment playback *starts* — which is
/// what "jump back in" actually means.
@TableIndex(name: 'idx_playback_history_started', columns: {#startedAt})
class PlaybackHistory extends Table {
  /// `PlaybackSourceKind.name` — album, playlist or artist.
  TextColumn get kind => text()();

  TextColumn get ratingKey => text()();

  /// Epoch seconds, matching every other time column in this schema.
  IntColumn get startedAt => integer()();

  /// One row per thing, updated in place, so putting the same album on twice
  /// moves it up the shelf rather than appearing on it twice.
  @override
  Set<Column> get primaryKey => {kind, ratingKey};
}
