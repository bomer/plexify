import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/plex/plex_client.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';

/// Applies star ratings to Plex, optimistically.
///
/// The local write happens first so the stars fill on the same frame as the
/// tap. If Plex rejects it the local value is put back — a rating that silently
/// disagreed with the server would be worse than one that visibly failed,
/// because ratings are the thing you later browse by.
class RatingController {
  const RatingController({required AppDatabase db, required PlexClient client})
    : _db = db,
      _client = client;

  final AppDatabase _db;
  final PlexClient _client;

  /// Sets an album's rating in stars. Zero clears it.
  Future<bool> rateAlbum(PlexAlbum album, int stars) =>
      _rate(album.ratingKey, album.userRating, stars, _db.setAlbumRating);

  /// Sets a track's rating in stars. Zero clears it.
  Future<bool> rateTrack(PlexTrack track, int stars) =>
      _rate(track.ratingKey, track.userRating, stars, _db.setTrackRating);

  Future<bool> _rate(
    String ratingKey,
    int? previous,
    int stars,
    Future<void> Function(String, int?) writeLocal,
  ) async {
    final clearing = stars <= 0;
    final rating = clearing ? null : PlexRating.fromStars(stars);

    await writeLocal(ratingKey, rating);

    try {
      await _client.rate(ratingKey, rating ?? PlexRating.clear);
      return true;
    } on Object {
      // Put the previous value back rather than leaving the UI showing a
      // rating the server does not have.
      await writeLocal(ratingKey, previous);
      return false;
    }
  }
}

final ratingControllerProvider = Provider<RatingController?>((ref) {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;
  return RatingController(db: ref.watch(databaseProvider), client: client);
});
