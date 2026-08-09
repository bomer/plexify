import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/playback_source.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../shell/layout.dart';
import '../player/playback_controller.dart';
import 'artist_detail_screen.dart';
import 'rating_controller.dart';
import 'artwork.dart';
import 'artwork_backdrop.dart';
import 'cover_frame.dart';
import 'detail_back.dart';
import '../player/playing_indicator.dart';
import 'star_rating.dart';
import 'track_rating_sheet.dart';
import 'track_totals.dart';

/// Track list for one album. Tapping a track replaces the queue and plays from
/// that point — the flat replace semantics agreed for v1.
class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({required this.album, super.key});

  final PlexAlbum album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tracks = ref.watch(tracksProvider(album.ratingKey));
    final client = ref.watch(plexClientProvider);
    final art = client?.artworkUrl(album.thumb, width: 600, height: 600);
    final compact = isCompactLayout(context);

    // No app bar. It held one control and a copy of the title printed six
    // lines below it, and cost a band of chrome plus a hard line straight
    // across the gradient. See [DetailBack].
    return Scaffold(
      // The page takes its colour from the record it is showing. Shorter and
      // weaker than the expanded player's: that one is a single object on a
      // dark field, this one has a track list to keep legible.
      body: ArtworkBackdrop(
        thumb: album.thumb,
        strength: 0.30,
        stop: 0.45,
        child: SafeArea(
          child: Stack(
            children: [
              tracks.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('$error', textAlign: TextAlign.center),
                  ),
                ),
                data: (items) => ListView.builder(
                  itemCount: items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return _Header(
                        album: album,
                        artUrl: art,
                        theme: theme,
                        tracks: items,
                      );
                    }
                    final index = i - 1;
                    final track = items[index];

                    final playing = isNowPlaying(ref, track.ratingKey);

                    return ListTile(
                      // Selected rather than a hand-rolled colour, so the highlight
                      // follows the theme and stays legible in both.
                      selected: playing,
                      // The marker replaces the track number rather than crowding in
                      // beside it: in a numbered list the number is how you find your
                      // place, and the one row you do not need it for is the one you
                      // are listening to.
                      leading: SizedBox(
                        width: 28,
                        child: playing
                            ? const Align(
                                alignment: Alignment.centerRight,
                                child: PlayingIndicator(),
                              )
                            : Text(
                                '${track.index}',
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: track.isPlayable
                          ? null
                          : Text(
                              'Unavailable',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Five stars per row eats most of a phone's width and pushes
                          // the title — the thing being scanned for — into an ellipsis.
                          // Long press opens the same rating instead.
                          if (!compact)
                            StarRating(
                              rating: track.userRating,
                              size: 15,
                              onRate: (stars) async {
                                final ok = await ref
                                    .read(ratingControllerProvider)
                                    ?.rateTrack(track, stars);
                                if (ok == false && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not save rating to Plex',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          if (!compact) const SizedBox(width: 8),
                          Text(
                            formatClock(track.duration),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      enabled: track.isPlayable,
                      onTap: () {
                        final controller = ref.read(playbackControllerProvider);
                        controller?.playTracks(
                          items,
                          startIndex: index,
                          source: PlaybackSource(
                            PlaybackSourceKind.album,
                            album.ratingKey,
                          ),
                        );
                      },
                      onLongPress: compact
                          ? () => showTrackRatingSheet(context, ref, track)
                          : null,
                    );
                  },
                ),
              ),
              const DetailBack(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The album's artist, as a way to get to them.
///
/// It was plain text, which made the artist page reachable only by going back
/// out to Library and finding them again — and the artist page is now where
/// the missing albums live, so "what else did they make" was several taps from
/// the album you were already looking at.
///
/// Falls back to plain text when the cache has no artist row, following the
/// same rule as Now Playing: a link that opens an empty page is worse than a
/// label. That happens for an album reached before sync has walked the artists,
/// or one Plex filed without a parent.
class _ArtistLink extends ConsumerWidget {
  const _ArtistLink({required this.album, required this.theme});

  final PlexAlbum album;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final key = album.artistRatingKey;
    final artist = key == null
        ? null
        : ref.watch(artistByKeyProvider(key)).valueOrNull;

    if (artist == null) return Text(album.artist, style: muted);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArtistDetailScreen(artist: artist),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              artist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.album,
    required this.artUrl,
    required this.theme,
    required this.tracks,
  });

  final PlexAlbum album;
  final String? artUrl;
  final ThemeData theme;
  final List<PlexTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      // Clears the floating back button, which is pinned rather than scrolled
      // with this.
      padding: const EdgeInsets.fromLTRB(16, detailHeaderTop, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverFrame(
            radius: 8,
            child: SizedBox(
              width: 120,
              height: 120,
              // Through the cache like every other surface. `Image.network`
              // here meant the one image most likely to be looked at twice
              // was the one never stored, re-fetched on every open — and it
              // could not draw at all while disconnected.
              child: Artwork(thumb: album.thumb, size: 600),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(album.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                _ArtistLink(album: album, theme: theme),
                const SizedBox(height: 2),
                Text(
                  [
                    if (album.year != null) '${album.year}',
                    describeTracks(tracks.length, totalDuration(tracks)),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),

                // Reads the album back out of the cache so the stars reflect
                // the optimistic write immediately, rather than the snapshot
                // this screen was pushed with.
                Consumer(
                  builder: (context, ref, _) {
                    final live =
                        ref
                            .watch(albumsProvider)
                            .valueOrNull
                            ?.where((a) => a.ratingKey == album.ratingKey)
                            .firstOrNull ??
                        album;

                    return StarRating(
                      rating: live.userRating,
                      onRate: (stars) async {
                        final controller = ref.read(ratingControllerProvider);
                        final ok = await controller?.rateAlbum(live, stars);
                        if (ok == false && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not save rating to Plex'),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),

                const SizedBox(height: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                  onPressed: () async {
                    final items = await ref.read(
                      tracksProvider(album.ratingKey).future,
                    );
                    ref
                        .read(playbackControllerProvider)
                        ?.playTracks(
                          items,
                          source: PlaybackSource(
                            PlaybackSourceKind.album,
                            album.ratingKey,
                          ),
                        );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
