import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/normalise.dart';
import 'catalog_models.dart';

/// Reads and writes the catalog cache.
///
/// The counterpart of `LibraryWriter`, and here for the same reason (invariant
/// 8): one place that knows how a [CatalogRelease] becomes rows, so a field
/// added to the model reaches every path at once rather than being populated by
/// search and null on the artist page.
///
/// **Why a cache at all.** MusicBrainz permits roughly one request a second and
/// answers 503 when pushed, so every avoided request is a second somebody does
/// not spend waiting. Opening an artist page is the case that matters: the same
/// discography, asked for repeatedly, whose answer changes about once a year.
class CatalogStore {
  const CatalogStore(this._db);

  final AppDatabase _db;

  /// How long an answer stays good.
  ///
  /// A week is long enough that browsing never waits and short enough that a
  /// record released since is not hidden for a season. There is no cheap way to
  /// ask MusicBrainz "has this changed?", so this is a guess by construction —
  /// which is why [releasesFor] returns stale answers rather than nothing when
  /// the network is unavailable.
  static const freshFor = Duration(days: 7);

  static String searchKey(String query) => 'search:${normalise(query)}';
  static String artistKey(String artistMbid) => 'artist:$artistMbid';

  /// A cached answer, with whether it is still fresh.
  ///
  /// Both halves are returned because the caller wants different things from
  /// them: stale results are still worth *showing* while a refresh runs, and
  /// showing nothing until MusicBrainz answers would make an artist page blank
  /// for a second every time it opened.
  Future<({List<CatalogRelease> releases, bool fresh})?> answerFor(
    String queryKey,
  ) async {
    final row = await (_db.select(
      _db.catalogQueries,
    )..where((q) => q.queryKey.equals(queryKey))).getSingleOrNull();
    if (row == null) return null;

    final ids = row.mbids.split(',').where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) {
      // A remembered empty answer. Real, and worth keeping: an artist with no
      // MusicBrainz discography would otherwise re-ask on every visit.
      return (
        releases: const <CatalogRelease>[],
        fresh: _isFresh(row.fetchedAt),
      );
    }

    final rows = await (_db.select(
      _db.catalogReleases,
    )..where((r) => r.mbid.isIn(ids))).get();

    // Restored to the order the answer was given in, which the ids carry and
    // the rows do not. For search that order is MusicBrainz's own relevance
    // ranking, and losing it would leave results in whatever order SQLite
    // happened to return.
    final byId = {for (final row in rows) row.mbid: row};
    return (
      releases: [
        for (final id in ids)
          if (byId[id] != null) _toModel(byId[id]!),
      ],
      fresh: _isFresh(row.fetchedAt),
    );
  }

  /// Stores an answer and the releases it names.
  Future<void> saveAnswer(
    String queryKey,
    List<CatalogRelease> releases,
  ) async {
    await _db.transaction(() async {
      if (releases.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(
            _db.catalogReleases,
            releases.map(
              (r) => CatalogReleasesCompanion.insert(
                mbid: r.mbid,
                title: r.title,
                artist: r.artist,
                artistMbid: Value(r.artistMbid),
                year: Value(r.year),
                kind: r.kind.name,
                secondaryTypes: Value(r.secondaryTypes.join(',')),
              ),
            ),
          );
        });
      }

      await _db
          .into(_db.catalogQueries)
          .insertOnConflictUpdate(
            CatalogQueriesCompanion.insert(
              queryKey: queryKey,
              mbids: releases.map((r) => r.mbid).join(','),
              fetchedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    });
  }

  /// A previously resolved artist id.
  ///
  /// The outer null means "never looked up"; a row whose `mbid` is null means
  /// "looked up, MusicBrainz has nobody by that name". Those must stay
  /// distinguishable or every unknown artist re-queries forever.
  Future<({String? mbid, String? name, bool fresh})?> artistFor(
    String libraryName,
  ) async {
    final row =
        await (_db.select(_db.catalogArtists)
              ..where((a) => a.normalisedName.equals(normalise(libraryName))))
            .getSingleOrNull();
    if (row == null) return null;
    return (
      mbid: row.mbid,
      name: row.resolvedName,
      fresh: _isFresh(row.fetchedAt),
    );
  }

  Future<void> saveArtist(
    String libraryName, {
    String? mbid,
    String? resolvedName,
  }) async {
    await _db
        .into(_db.catalogArtists)
        .insertOnConflictUpdate(
          CatalogArtistsCompanion.insert(
            normalisedName: normalise(libraryName),
            mbid: Value(mbid),
            resolvedName: Value(resolvedName),
            fetchedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  static bool _isFresh(int fetchedAtMillis) =>
      DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis))
          .abs() <
      freshFor;

  static CatalogRelease _toModel(CatalogReleaseRow row) => CatalogRelease(
    mbid: row.mbid,
    title: row.title,
    artist: row.artist,
    artistMbid: row.artistMbid,
    year: row.year,
    kind: ReleaseKind.parse(row.kind),
    secondaryTypes: row.secondaryTypes.isEmpty
        ? const []
        : row.secondaryTypes.split(','),
  );
}
