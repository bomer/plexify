import '../../core/catalog/catalog_models.dart';
import '../../core/qbit/qbit_client.dart';
import '../../core/qbit/qbit_models.dart';
import '../../core/qbit/torrent_ranking.dart';

/// What came back from looking for a record, and what was done about it.
class AcquireOutcome {
  const AcquireOutcome({
    this.queued,
    this.candidates = const [],
    this.error,
    this.pluginsMissing = false,
  });

  const AcquireOutcome.failed(String this.error)
    : queued = null,
      candidates = const [],
      pluginsMissing = false;

  /// The result that was added, when one was good enough to add without asking.
  final RankedTorrent? queued;

  /// Everything found, best first. Populated whether or not anything was
  /// queued, so "change that" is always one tap away.
  final List<RankedTorrent> candidates;

  final String? error;

  /// qBittorrent has no search plugins installed or enabled.
  ///
  /// Called out separately because it is the one failure that looks exactly
  /// like success: the search endpoints answer happily and return nothing, so
  /// without this it reads as "nobody is seeding this album" for every album.
  final bool pluginsMissing;

  bool get isEmpty => candidates.isEmpty && error == null;
}

/// Finds and queues a record the library does not hold.
///
/// The whole flow in one place: build a query from structured metadata, run it,
/// rank what comes back, and either add the obvious answer or hand the list to
/// the user.
///
/// **The query is built from MusicBrainz's fields, not from what was typed.**
/// A raw search string finds torrents whose *name* contains it, which for
/// "ok computer" includes tribute albums, karaoke versions and an unrelated
/// record by someone else. Artist plus album title is what actually identifies
/// the thing.
///
/// The year is deliberately **not** in the query even though it is known.
/// Torrent names carry it inconsistently — perhaps half do — so requiring it
/// halves the results for no gain in correctness. It earns its keep in
/// [rankTorrents] instead, where a name that does contain the right year is
/// scored up and one that does not is merely not scored up.
class AcquireController {
  const AcquireController(this._client);

  final QbitClient _client;

  /// Searches for [release] and queues the obvious answer if there is one.
  ///
  /// "One click" in the sense the artist page needs, without ever being one
  /// click away from downloading the wrong record: [bestAutomaticChoice] only
  /// returns something whose filename actually names this album and this
  /// artist. When it does not, nothing is added and the caller shows the list.
  Future<AcquireOutcome> queueBest(CatalogRelease release) async {
    final found = await find(release);
    if (found.error != null || found.candidates.isEmpty) return found;

    final best = bestAutomaticChoice(found.candidates);
    if (best == null) return found;

    try {
      await _client.addTorrent(best.result.fileUrl);
    } on QbitException catch (e) {
      return AcquireOutcome(candidates: found.candidates, error: e.message);
    }
    return AcquireOutcome(queued: best, candidates: found.candidates);
  }

  /// Searches without adding anything.
  Future<AcquireOutcome> find(CatalogRelease release) async {
    try {
      if (!await _client.hasSearchPlugins()) {
        return const AcquireOutcome(
          pluginsMissing: true,
          error:
              'qBittorrent has no search plugins enabled, so it can search '
              'nothing. Add one in qBittorrent under View, Search engine.',
        );
      }

      final results = await _client.search(queryFor(release));
      return AcquireOutcome(
        candidates: rankTorrents(
          results,
          artist: release.artist,
          album: release.title,
          year: release.year,
        ),
      );
    } on QbitException catch (e) {
      return AcquireOutcome.failed(e.message);
    } on Object catch (e) {
      return AcquireOutcome.failed('Could not reach qBittorrent: $e');
    }
  }

  /// Queues one specific result the user picked.
  Future<String?> add(QbitSearchResult result) async {
    try {
      await _client.addTorrent(result.fileUrl);
      return null;
    } on QbitException catch (e) {
      return e.message;
    } on Object catch (e) {
      return 'Could not reach qBittorrent: $e';
    }
  }

  /// The search pattern for a release.
  ///
  /// Exposed so it is testable on its own, and because it is the one string in
  /// this flow whose shape decides whether anything is found at all.
  static String queryFor(CatalogRelease release) =>
      '${release.artist} ${release.title}'.trim();
}
