import '../plex/plex_models.dart';
import 'app_database.dart';

/// Converts cached rows back into the domain models the UI already speaks.
///
/// Keeping the widgets on [PlexAlbum] / [PlexTrack] rather than drift's
/// generated row classes means the storage layer can change without touching
/// the UI — and it is what let the switch from live Plex reads to cache reads
/// happen without rewriting a single screen.
extension AlbumRowMapper on Album {
  PlexAlbum toDomain() => PlexAlbum(
    ratingKey: ratingKey,
    title: title,
    artist: artistTitle,
    artistRatingKey: artistRatingKey,
    thumb: thumb,
    year: year,
    addedAt: addedAt,
    updatedAt: updatedAt,
    lastViewedAt: lastViewedAt,
    userRating: userRating,
  );
}

extension TrackRowMapper on Track {
  PlexTrack toDomain() => PlexTrack(
    ratingKey: ratingKey,
    title: title,
    index: trackIndex,
    durationMs: durationMs,
    album: albumTitle,
    artist: artistTitle,
    albumRatingKey: albumRatingKey,
    discIndex: discIndex,
    partKey: partKey,
    container: container,
    thumb: thumb,
    updatedAt: updatedAt,
    addedAt: addedAt,
    lastViewedAt: lastViewedAt,
    userRating: userRating,
  );
}

extension PlaylistRowMapper on Playlist {
  PlexPlaylist toDomain() => PlexPlaylist(
    ratingKey: ratingKey,
    title: title,
    thumb: thumb,
    itemCount: itemCount,
    durationMs: durationMs,
    updatedAt: updatedAt,
    lastViewedAt: lastViewedAt,
    smart: smart,
  );
}

extension ArtistRowMapper on Artist {
  PlexArtist toDomain() => PlexArtist(
    ratingKey: ratingKey,
    title: title,
    thumb: thumb,
    updatedAt: updatedAt,
    addedAt: addedAt,
  );
}
