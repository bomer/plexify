import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_handler.dart';
import '../../core/providers.dart';
import '../../shell/layout.dart';
import '../library/artist_detail_screen.dart';
import '../library/library_screen.dart' show openAlbum;
import '../library/artwork.dart';
import 'player_providers.dart';
import 'seek_control.dart';
import 'transport_buttons.dart';

/// The expanded player.
///
/// Rendered as a layer in the shell's [Stack] rather than a pushed route, so
/// the screen underneath stays mounted and dismissing returns you to exactly
/// the scroll position and view you left.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: StreamBuilder<MediaItem?>(
        stream: handler.mediaItem,
        builder: (context, snapshot) {
          final item = snapshot.data;
          if (item == null) return const SizedBox.shrink();

          return _Backdrop(
            thumb: item.extras?['thumb'] as String?,
            child: SafeArea(
              child: Column(
                children: [
                  _DragHandle(
                    onCollapse: () =>
                        ref.read(nowPlayingExpandedProvider.notifier).state =
                            false,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          _Artwork(item: item),
                          const SizedBox(height: 32),
                          _TrackInfo(item: item),
                          const SizedBox(height: 24),
                          SeekControl(
                            handler: handler,
                            duration: item.duration,
                          ),
                          const SizedBox(height: 8),
                          _TransportControls(handler: handler),
                          const SizedBox(height: 24),
                          _UpNext(handler: handler),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A wash of colour taken from the sleeve, behind everything else.
///
/// The colour is asked for asynchronously and is null until it arrives, and
/// null again for a cover that is genuinely monochrome, so this has to look
/// deliberate with no colour at all rather than merely unfinished. It fades in
/// over a third of a second: appearing instantly on every track change reads as
/// a flicker, and the eye notices a hard cut in a large flat area far more than
/// it notices a slow one.
///
/// Stops well short of the bottom. A full-height tint is a coloured screen
/// rather than a lit one, and the queue at the bottom needs ordinary contrast
/// to stay readable.
class _Backdrop extends ConsumerWidget {
  const _Backdrop({required this.thumb, required this.child});

  final String? thumb;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final path = thumb;
    final colour = path == null
        ? null
        : ref.watch(artworkColourProvider(path)).valueOrNull;

    // Kept well under half opacity: the sleeve's own colour at full strength
    // fights the artwork it came from, and light covers would leave white text
    // on a pale wash.
    final tint = colour == null
        ? theme.colorScheme.surface
        : Color.alphaBlend(
            colour.withValues(alpha: 0.38),
            theme.colorScheme.surface,
          );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, theme.colorScheme.surface],
          stops: const [0, 0.65],
        ),
      ),
      child: child,
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      // Swiping down anywhere on the header dismisses, matching the gesture
      // people already expect from every other player.
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 200) onCollapse();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Collapse',
              onPressed: onCollapse,
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Balances the leading icon so the grab handle sits centred.
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

/// The sleeve.
///
/// **Smaller on the desktop than the space allows, deliberately.** It used to
/// fill 420 logical pixels, which on any modern display is 840 physical, and
/// Plex is asked for 600 — so the picture was upscaled by a third and looked
/// soft in exactly the place it is being looked at hardest. Plenty of covers on
/// the server are not much above 600 to begin with, so asking for more would
/// often be asking Plex to upscale instead, which is worse. 300 logical against
/// a 600px source is crisp at 2x and merely correct at 1x.
///
/// A phone has no such choice: 300 in the middle of a 400-wide screen is a
/// stamp, so it keeps the full width it always had.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final maxWidth = isCompactLayout(context) ? 420.0 : 300.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Artwork(
                thumb: item.extras?['thumb'] as String?,
                size: 600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          item.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        _Subtitle(item: item),
      ],
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.handler});

  final PlexifyAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state?.playing ?? false;
        final busy =
            state?.processingState == AudioProcessingState.loading ||
            state?.processingState == AudioProcessingState.buffering;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShuffleButton(handler: handler, state: state),
            const SizedBox(width: 8),
            IconButton(
              iconSize: 40,
              icon: const Icon(Icons.skip_previous),
              onPressed: handler.skipToPrevious,
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 72,
              height: 72,
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    )
                  : IconButton.filled(
                      iconSize: 40,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: playing ? handler.pause : handler.play,
                    ),
            ),
            const SizedBox(width: 16),
            IconButton(
              iconSize: 40,
              icon: const Icon(Icons.skip_next),
              onPressed: handler.skipToNext,
            ),
            const SizedBox(width: 8),
            RepeatButton(handler: handler, state: state),
          ],
        );
      },
    );
  }
}

/// What is coming, reorderable and removable.
///
/// Only the tracks *after* the current one. Reordering something into the past
/// has no meaning, and dragging away the track you are listening to would stop
/// it, which is never what dragging a row further down the list should do.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.handler});

  final PlexifyAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (context, stateSnapshot) {
        final currentIndex = stateSnapshot.data?.queueIndex;
        final shuffled =
            stateSnapshot.data?.shuffleMode == AudioServiceShuffleMode.all;

        return StreamBuilder<List<MediaItem>>(
          stream: handler.queue,
          builder: (context, queueSnapshot) {
            final queue = queueSnapshot.data ?? const <MediaItem>[];
            if (currentIndex == null || currentIndex >= queue.length) {
              return const SizedBox.shrink();
            }

            // Shuffled, "what follows this track" is not a thing: the next one
            // is picked at random, and slicing the list at the current index
            // made the shelf shrink and jump about after every track, which
            // read as the queue reordering itself. So the whole queue is shown
            // in its own order, minus what is playing, and the heading stops
            // claiming to be a running order.
            final upcoming = shuffled
                ? [
                    for (final (i, item) in queue.indexed)
                      if (i != currentIndex) item,
                  ]
                : queue.sublist(currentIndex + 1);
            if (upcoming.isEmpty) return const SizedBox.shrink();

            // Offsets into `queue`, since a shuffled list is no longer a
            // contiguous slice and the handler works in queue indices.
            final indices = shuffled
                ? [
                    for (final (i, _) in queue.indexed)
                      if (i != currentIndex) i,
                  ]
                : [for (var i = currentIndex + 1; i < queue.length; i++) i];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shuffled ? 'In this queue' : 'Up next',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  // `onReorderItem` rather than the deprecated `onReorder`,
                  // which reported the destination as an index in the list
                  // *before* the dragged item was taken out and left every
                  // caller to correct for it. This one is already adjusted.
                  // Reordering a shuffled queue would be rearranging a list
                  // whose order does not decide anything, so it is only
                  // offered when the order is the running order.
                  onReorderItem: shuffled
                      ? (_, _) {}
                      : (oldOffset, newOffset) => handler.moveQueueItem(
                          indices[oldOffset],
                          currentIndex + 1 + newOffset,
                        ),
                  children: [
                    for (final (offset, item) in upcoming.take(20).indexed)
                      Dismissible(
                        key: ValueKey('up-next-$offset-${item.id}'),
                        direction: DismissDirection.endToStart,
                        background: ColoredBox(
                          color: theme.colorScheme.errorContainer,
                          child: const Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(right: 16),
                              child: Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                        onDismissed: (_) => handler.removeQueueItemAt(
                          currentIndex + 1 + offset,
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // An explicit handle rather than long-press-to-drag:
                          // these rows are tappable too, and a long press that
                          // sometimes plays and sometimes lifts is worse than
                          // a grip you can see.
                          trailing: shuffled
                              ? null
                              : ReorderableDragStartListener(
                                  index: offset,
                                  child: const Icon(Icons.drag_handle),
                                ),
                          onTap: () => handler.skipToQueueItem(
                            currentIndex + 1 + offset,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Artist and album under the title, tappable when they lead somewhere.
///
/// The names were already on screen and were the obvious thing to press,
/// which made not being able to press them feel like a dead end. Rendered as
/// plain text when the cache does not have the album, because a link that
/// opens an empty page is worse than no link.
class _Subtitle extends ConsumerWidget {
  const _Subtitle({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final linked = muted?.copyWith(color: theme.colorScheme.primary);

    final key = item.extras?['albumRatingKey'] as String?;
    final album = key == null
        ? null
        : ref.watch(albumByKeyProvider(key)).valueOrNull;

    final artistKey = album?.artistRatingKey;
    final artist = artistKey == null
        ? null
        : ref.watch(artistByKeyProvider(artistKey)).valueOrNull;

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (item.artist case final name? when name.isNotEmpty)
          artist == null
              ? Text(name, style: muted)
              : InkWell(
                  onTap: () {
                    ref.read(nowPlayingExpandedProvider.notifier).state = false;
                    Navigator.of(context, rootNavigator: false).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistDetailScreen(artist: artist),
                      ),
                    );
                  },
                  child: Text(name, style: linked),
                ),
        if (item.artist != null && item.album != null)
          Text('  ·  ', style: muted),
        if (item.album case final name? when name.isNotEmpty)
          album == null
              ? Text(name, style: muted)
              : InkWell(
                  onTap: () {
                    // Collapsed first: pushing a route underneath an overlay
                    // that is still up would land you on a page you cannot
                    // see.
                    ref.read(nowPlayingExpandedProvider.notifier).state = false;
                    openAlbum(context, album);
                  },
                  child: Text(name, style: linked),
                ),
      ],
    );
  }
}
