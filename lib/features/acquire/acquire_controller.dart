import '../../core/acquire/download_source.dart';
import '../../core/catalog/catalog_models.dart';
import '../../core/qbit/qbit_client.dart';
import '../../core/qbit/qbit_models.dart';
import '../../core/qbit/torrent_ranking.dart';

/// The qBittorrent half of [DownloadSource].
///
/// The whole flow in one place: build a query from structured metadata, run it,
/// rank what comes back, and either add the obvious answer or hand the list to
/// the user.
class AcquireController implements DownloadSource {
  const AcquireController(this._client);

  final QbitClient _client;

  @override
  DownloadSourceKind get kind => DownloadSourceKind.qbittorrent;

  /// Searches for [release] and queues the obvious answer if there is one.
  ///
  /// "One click" in the sense the artist page needs, without ever being one
  /// click away from downloading the wrong record: [bestAutomaticChoice] only
  /// returns something whose filename actually names this album and this
  /// artist. When it does not, nothing is added and the caller shows the list.
  @override
  Future<AcquireOutcome> queueBest(CatalogRelease release) async {
    final found = await find(release);
    if (found.error != null || found.candidates.isEmpty) return found;

    final best = bestAutomaticChoice([
      for (final candidate in found.candidates)
        (candidate as TorrentCandidate).torrent,
    ]);
    if (best == null) return found;

    try {
      await _client.addTorrent(best.result.fileUrl);
    } on QbitException catch (e) {
      return AcquireOutcome(
        kind: kind,
        candidates: found.candidates,
        error: e.message,
      );
    }
    return AcquireOutcome(
      kind: kind,
      queued: TorrentCandidate(best),
      candidates: found.candidates,
    );
  }

  /// Searches without adding anything.
  @override
  Future<AcquireOutcome> find(CatalogRelease release) async {
    try {
      if (!await _client.hasSearchPlugins()) {
        return AcquireOutcome(
          kind: kind,
          unusable: true,
          error:
              'qBittorrent has no search plugins enabled, so it can search '
              'nothing. Add one in qBittorrent under View, Search engine.',
        );
      }

      final results = await _client.search(DownloadSource.queryFor(release));
      return AcquireOutcome(
        kind: kind,
        candidates: [
          for (final ranked in rankTorrents(
            results,
            artist: release.artist,
            album: release.title,
            year: release.year,
          ))
            TorrentCandidate(ranked),
        ],
      );
    } on QbitException catch (e) {
      return AcquireOutcome.failed(kind, e.message);
    } on Object catch (e) {
      return AcquireOutcome.failed(kind, 'Could not reach qBittorrent: $e');
    }
  }

  /// Queues one specific result the user picked.
  @override
  Future<String?> add(AcquireCandidate candidate) async {
    if (candidate is! TorrentCandidate) {
      // A programming error rather than anything a user can cause: only one
      // source is ever active, so its own candidates are the only ones it can
      // be handed.
      return 'That result did not come from qBittorrent.';
    }

    try {
      await _client.addTorrent(candidate.torrent.result.fileUrl);
      return null;
    } on QbitException catch (e) {
      return e.message;
    } on Object catch (e) {
      return 'Could not reach qBittorrent: $e';
    }
  }
}
