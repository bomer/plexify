import '../../core/acquire/download_source.dart';
import '../../core/catalog/catalog_models.dart';
import '../../core/slskd/album_ranking.dart';
import '../../core/slskd/slskd_client.dart';
import '../../core/slskd/slskd_models.dart';

/// The Soulseek half of [DownloadSource].
///
/// Structurally the same three steps as the qBittorrent controller: query from
/// structured metadata, rank what comes back, add the obvious answer or hand
/// over the list. Two things differ, and both come from Soulseek being people
/// rather than a swarm.
///
/// The whole folder is queued at once, because that is what a record is here.
/// And the "cannot search at all" check is a different question: qBittorrent
/// with no plugins and slskd logged out of Soulseek both answer happily and
/// return nothing, which reads as "nobody has this album" for every album, but
/// only one of them is about plugins.
class SlskdAcquireController implements DownloadSource {
  const SlskdAcquireController(this._client);

  final SlskdClient _client;

  @override
  DownloadSourceKind get kind => DownloadSourceKind.soulseek;

  @override
  Future<AcquireOutcome> queueBest(CatalogRelease release) async {
    final found = await find(release);
    if (found.error != null || found.candidates.isEmpty) return found;

    final best = bestSlskdAlbum([
      for (final candidate in found.candidates)
        (candidate as SoulseekCandidate).album,
    ]);
    if (best == null) return found;

    final error = await _enqueue(best);
    if (error != null) {
      return AcquireOutcome(
        kind: kind,
        candidates: found.candidates,
        error: error,
      );
    }
    return AcquireOutcome(
      kind: kind,
      queued: SoulseekCandidate(best),
      candidates: found.candidates,
    );
  }

  @override
  Future<AcquireOutcome> find(CatalogRelease release) async {
    try {
      // Asked before searching rather than after. A logged-out slskd answers
      // every request perfectly and finds nothing at all, which is
      // indistinguishable from an album nobody happens to be sharing.
      if (!await _client.isConnectedToSoulseek()) {
        return AcquireOutcome(
          kind: kind,
          unusable: true,
          error:
              'slskd is running but is not logged in to Soulseek, so it can '
              'search nothing. Check its own web interface.',
        );
      }

      final responses = await _client.search(DownloadSource.queryFor(release));
      return AcquireOutcome(
        kind: kind,
        candidates: [
          for (final album in rankSlskdAlbums(
            responses,
            artist: release.artist,
            album: release.title,
            year: release.year,
          ))
            SoulseekCandidate(album),
        ],
      );
    } on SlskdException catch (e) {
      return AcquireOutcome.failed(kind, e.message);
    } on Object catch (e) {
      return AcquireOutcome.failed(kind, 'Could not reach slskd: $e');
    }
  }

  @override
  Future<String?> add(AcquireCandidate candidate) async {
    if (candidate is! SoulseekCandidate) {
      return 'That result did not come from Soulseek.';
    }
    return _enqueue(candidate.album);
  }

  /// Queues every audio file in the folder, from the one peer holding it.
  ///
  /// **All of it or none of it.** Half a record in the folder Plex watches is
  /// worse than nothing there: it gets scanned, appears in the library looking
  /// complete, and the missing tracks are only noticed on playing it.
  Future<String?> _enqueue(SlskdAlbum album) async {
    try {
      await _client.enqueue(album.username, album.files);
      return null;
    } on SlskdException catch (e) {
      return e.message;
    } on Object catch (e) {
      return 'Could not reach slskd: $e';
    }
  }
}
