import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/playback_source.dart';

import '../acquire/catalog_release_card.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../radio/radio_action.dart';
import '../../shell/layout.dart';
import '../player/playback_controller.dart';
import 'album_detail_screen.dart';
import 'artwork.dart';
import 'artwork_backdrop.dart';
import 'cover_frame.dart';
import '../player/playing_indicator.dart';
import 'rating_controller.dart';
import 'star_rating.dart';
import 'track_context_menu.dart';
import 'track_rating_sheet.dart';

/// An artist's discography, oldest first.
class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({required this.artist, super.key});

  final PlexArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final albums = ref.watch(artistAlbumsProvider(artist.ratingKey));

    return Scaffold(
      // Same trick as the album page, weaker still: an artist page is mostly
      // grid, and a grid needs its own contrast more than it needs a mood.
      body: ArtworkBackdrop(
        thumb: artist.thumb,
        strength: 0.26,
        stop: 0.4,
        child: albums.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('$error', textAlign: TextAlign.center),
            ),
          ),
          data: (items) => CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    artist.title,
                    style: const TextStyle(fontSize: 16),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Artwork(
                        thumb: artist.thumb,
                        size: 600,
                        icon: Icons.person,
                      ),
                      // Without a scrim the title is unreadable over light
                      // artwork, which most artist images are.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              theme.colorScheme.surface.withValues(alpha: 0.9),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        items.length == 1
                            ? '1 album'
                            : '${items.length} albums',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _ArtistStars(artist: artist),
                      const Spacer(),
                      if (items.isNotEmpty) ...[
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play'),
                          onPressed: () => _playEverything(ref, items),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Offered even with no albums cached, and that is not an
                      // oversight: a station is mostly *other* artists, so it
                      // is worth pressing on a page that has little of its own.
                      OutlinedButton.icon(
                        icon: const Icon(Icons.radio),
                        label: const Text('Radio'),
                        onPressed: () => startRadioForArtist(
                          context,
                          ref,
                          artist.ratingKey,
                          artistName: artist.title,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('No albums for this artist.')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _AlbumCard(album: items[i]),
                  ),
                ),

              // What they made and you do not have, between the albums and the
              // tracks. Above the flat track list because it is about the shape
              // of the discography, which is what the grid above is about too.
              _MissingAlbums(artist: artist),

              // Every track, flat, underneath the albums. For an artist you only
              // have a handful of songs by, scrolling to the track you want beats
              // guessing which album it was on.
              _TrackList(artistRatingKey: artist.ratingKey),
            ],
          ),
        ),
      ),
    );
  }

  /// Plays the discography in order, album by album.
  ///
  /// Tracks are gathered up front so the queue is complete before playback
  /// starts — appending as each album resolves would let the first album end
  /// before the second arrived.
  Future<void> _playEverything(WidgetRef ref, List<PlexAlbum> albums) async {
    final controller = ref.read(playbackControllerProvider);
    if (controller == null) return;

    final tracks = <PlexTrack>[];
    for (final album in albums) {
      tracks.addAll(await ref.read(tracksProvider(album.ratingKey).future));
    }
    if (tracks.isNotEmpty) {
      await controller.playTracks(
        tracks,
        source: PlaybackSource(PlaybackSourceKind.artist, artist.ratingKey),
      );
    }
  }
}

/// Records this artist made that the library does not hold.
///
/// **Renders nothing at all when the catalog setting is off**, which is the
/// whole point of that switch: on a phone this section is noise, and hiding it
/// behind a collapsed header would still mean the lookup ran. Off means no
/// request, no section, no gap on the page.
///
/// Studio albums and EPs only. A well-catalogued artist has three or four times
/// as many compilations, live records and singles as albums, and listing them
/// turns "what am I missing" into a wall nobody reads. They are still findable
/// through search.
class _MissingAlbums extends ConsumerWidget {
  const _MissingAlbums({required this.artist});

  final PlexArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (!ref.watch(catalogEnabledProvider)) return const SliverToBoxAdapter();

    final missing = ref.watch(
      missingAlbumsProvider((ratingKey: artist.ratingKey, name: artist.title)),
    );

    // A rate-limited lookup takes a second or two, and a spinner that pushes
    // the track list down and then lets it spring back is worse than the
    // section simply appearing when it has something to say.
    final data = missing.valueOrNull;
    if (data == null || data.state == MissingAlbumsState.disabled) {
      return const SliverToBoxAdapter();
    }

    if (data.state == MissingAlbumsState.unresolved) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            // Stated rather than left blank. "No missing albums" and "we could
            // not work out who this is" look identical otherwise, and only one
            // of them is good news.
            'MusicBrainz has no confident match for ${artist.title}, so '
            'missing albums cannot be listed here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    if (data.releases.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You have every album MusicBrainz lists for this artist.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Not in your library',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        _subtitle(data, artist.title),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.66,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: data.releases.length,
            itemBuilder: (context, i) =>
                CatalogReleaseCard(release: data.releases[i]),
          ),
        ),
      ],
    );
  }

  /// Names the artist MusicBrainz actually matched when it is not the one the
  /// library calls them, so a wrong match is visible rather than presenting as
  /// a page of albums this artist never made.
  static String _subtitle(MissingAlbums data, String libraryName) {
    final matched = data.matchedName;
    final counts = '${data.releases.length} of ${data.totalKnown}';
    if (matched == null || matched.toLowerCase() == libraryName.toLowerCase()) {
      return '$counts albums and EPs on MusicBrainz';
    }
    return '$counts albums and EPs, matched as "$matched"';
  }
}


/// All of an artist's tracks, in discography order.
class _TrackList extends ConsumerWidget {
  const _TrackList({required this.artistRatingKey});

  final String artistRatingKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final compact = isCompactLayout(context);
    final tracks =
        ref.watch(artistTracksProvider(artistRatingKey)).valueOrNull ??
        const <PlexTrack>[];

    if (tracks.isEmpty) return const SliverToBoxAdapter();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text('Tracks', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  '${tracks.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),

        SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final track = tracks[i];
            final playing = isNowPlaying(ref, track.ratingKey);
            return withTrackMenu(
              ref: ref,
              track: track,
              compact: compact,
              child: ListTile(
                dense: true,
                selected: playing,
                leading: playing ? const PlayingIndicator() : null,
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Stars are desktop-only here for the same reason as the album
                // screen: on a phone they crowd out the title and the album.
                trailing: compact
                    ? null
                    : StarRating(
                        rating: track.userRating,
                        size: 15,
                        onRate: (stars) async {
                          final ok = await ref
                              .read(ratingControllerProvider)
                              ?.rateTrack(track, stars);
                          if (ok == false && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not save rating to Plex'),
                              ),
                            );
                          }
                        },
                      ),
                enabled: track.isPlayable,
                // Queues the whole discography from here, so playing one track
                // keeps going through the rest rather than stopping dead.
                onTap: () => ref
                    .read(playbackControllerProvider)
                    ?.playTracks(
                      tracks,
                      startIndex: i,
                      source: PlaybackSource(
                        PlaybackSourceKind.artist,
                        artistRatingKey,
                      ),
                    ),
                onLongPress: compact
                    ? () => showTrackRatingSheet(context, ref, track)
                    : null,
              ),
            );
          },
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final PlexAlbum album;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlbumDetailScreen(album: album),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CoverFrame(child: Artwork(thumb: album.thumb)),
          ),
          const SizedBox(height: 8),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          if (album.year != null)
            Text(
              '${album.year}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// The artist's own star rating, written through to Plex.
///
/// Read from the cache rather than from the [PlexArtist] this screen was
/// pushed with, so the stars reflect the optimistic local write immediately
/// instead of the snapshot taken when the page opened.
///
/// Plex stores artist ratings on the same endpoint as albums and tracks, so
/// setting one here shows up in the Plex web UI, and a rating set there
/// arrives on the next sync that touches the row.
class _ArtistStars extends ConsumerWidget {
  const _ArtistStars({required this.artist});

  final PlexArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live =
        ref.watch(artistRatingProvider(artist.ratingKey)).valueOrNull ??
        artist.userRating;

    return StarRating(
      rating: live,
      size: 16,
      onRate: (stars) async {
        final ok = await ref
            .read(ratingControllerProvider)
            ?.rateArtist(
              PlexArtist(
                ratingKey: artist.ratingKey,
                title: artist.title,
                thumb: artist.thumb,
                updatedAt: artist.updatedAt,
                addedAt: artist.addedAt,
                userRating: live,
              ),
              stars,
            );
        if (ok == false && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save rating to Plex')),
          );
        }
      },
    );
  }
}
