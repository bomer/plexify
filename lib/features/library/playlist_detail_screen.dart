import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/playback_source.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../../shell/layout.dart';
import '../player/playing_indicator.dart';
import '../player/playback_controller.dart';
import 'artwork.dart';
import 'artwork_backdrop.dart';
import 'cover_frame.dart';
import 'rating_controller.dart';
import 'star_rating.dart';
import 'track_rating_sheet.dart';
import 'track_totals.dart';

/// A playlist's tracks, in playlist order.
///
/// Read-only in v1 — no reordering or editing. Items are fetched on first open
/// and cached, so returning is instant.
///
/// **Built to match the album page rather than to be its own thing.** The
/// sidebar shows a playlist's mosaic, so opening one and landing on a bare list
/// with no artwork at all read as the wrong page having loaded. The two screens
/// answer the same question — here is a group of tracks, here is what it looks
/// like, play it — and the only real differences are that a playlist has no
/// artist and that its position numbers are an arrangement rather than a
/// pressing order.
class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({required this.playlist, super.key});

  final PlexPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tracks = ref.watch(playlistTracksProvider(playlist.ratingKey));
    final compact = isCompactLayout(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.title),
        backgroundColor: Colors.transparent,
      ),
      // Plex generates a mosaic for every playlist, so this has a colour to
      // take even though there is no single sleeve behind it.
      body: ArtworkBackdrop(
        thumb: playlist.thumb,
        strength: 0.30,
        stop: 0.45,
        child: tracks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('$error', textAlign: TextAlign.center),
            ),
          ),
          data: (items) {
            // The header stays even when there is nothing under it. An empty
            // playlist is a real thing to be looking at, and a bare sentence in
            // the middle of the screen gives no clue which one you opened.
            if (items.isEmpty) {
              return ListView(
                children: [
                  _Header(playlist: playlist, tracks: items, theme: theme),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: Text(
                      'This playlist is empty.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              itemCount: items.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _Header(
                    playlist: playlist,
                    tracks: items,
                    theme: theme,
                  );
                }

                final index = i - 1;
                final track = items[index];
                final playing = isNowPlaying(ref, track.ratingKey);

                return ListTile(
                  selected: playing,
                  // Position in the playlist, replaced by the marker on the row
                  // that is playing — the same trade the album page makes. The
                  // number is how you find your place in a list of a hundred
                  // and forty, and the one row you do not need it for is the
                  // one you are listening to.
                  leading: SizedBox(
                    width: 28,
                    child: playing
                        ? const Align(
                            alignment: Alignment.centerRight,
                            child: PlayingIndicator(),
                          )
                        : Text(
                            '${index + 1}',
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
                  // A playlist's rows come from everywhere, so unlike an album's
                  // the artist and record are the useful part rather than
                  // repetition of the header.
                  subtitle: Text(
                    [
                      track.artist,
                      track.album,
                    ].where((s) => s.isNotEmpty).join(' — '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Same rule as the album page: five stars per row eats
                      // most of a phone's width and pushes the title into an
                      // ellipsis, so a long press opens the same rating there.
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
                  onTap: () => ref
                      .read(playbackControllerProvider)
                      ?.playTracks(
                        items,
                        startIndex: index,
                        source: PlaybackSource(
                          PlaybackSourceKind.playlist,
                          playlist.ratingKey,
                        ),
                      ),
                  onLongPress: compact
                      ? () => showTrackRatingSheet(context, ref, track)
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Mosaic, title, what it is, how much of it, and a way to start.
///
/// Deliberately the same shape as the album page's header, down to the cover
/// size, so moving between the two does not feel like moving between two apps.
class _Header extends ConsumerWidget {
  const _Header({
    required this.playlist,
    required this.tracks,
    required this.theme,
  });

  final PlexPlaylist playlist;
  final List<PlexTrack> tracks;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverFrame(
            radius: 8,
            child: SizedBox(
              width: 120,
              height: 120,
              // Plex exposes playlist art as `composite`, a generated mosaic,
              // which `PlexPlaylist` already maps onto `thumb`. Asking for
              // `thumb` on the wire yields nothing at all.
              child: Artwork(
                thumb: playlist.thumb,
                size: 600,
                icon: Icons.queue_music,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(playlist.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                _Kind(playlist: playlist, theme: theme),
                const SizedBox(height: 2),
                Text(
                  describeTracks(tracks.length, totalDuration(tracks)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                  onPressed: tracks.isEmpty
                      ? null
                      : () => ref
                            .read(playbackControllerProvider)
                            ?.playTracks(
                              tracks,
                              source: PlaybackSource(
                                PlaybackSourceKind.playlist,
                                playlist.ratingKey,
                              ),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The line where an album page names the artist.
///
/// A playlist has no artist, and leaving the line out would make the two
/// headers different heights for no reason a reader could name. Saying what
/// kind of playlist it is fills it with the one fact that actually changes how
/// to read the page: a smart playlist's contents are rules, so what is here
/// today is not necessarily what was here last week.
class _Kind extends StatelessWidget {
  const _Kind({required this.playlist, required this.theme});

  final PlexPlaylist playlist;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (!playlist.smart) {
      return Text(
        'Playlist',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 5),
        Text(
          'Smart playlist',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
