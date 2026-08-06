import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_handler.dart';
import '../../core/providers.dart';
import '../library/artist_detail_screen.dart';
import '../library/library_screen.dart' show openAlbum;
import '../library/artwork.dart';
import 'player_providers.dart';

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
      child: SafeArea(
        child: StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (context, snapshot) {
            final item = snapshot.data;
            if (item == null) return const SizedBox.shrink();

            return Column(
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
                        _SeekBar(handler: handler, duration: item.duration),
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
            );
          },
        ),
      ),
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

class _Artwork extends StatelessWidget {
  const _Artwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Artwork(thumb: item.extras?['thumb'] as String?, size: 600),
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

/// Scrub bar.
///
/// While dragging, the slider follows the finger rather than the position
/// stream — otherwise every incoming position tick would yank the thumb back
/// and scrubbing would be unusable.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.handler, required this.duration});

  final PlexifyAudioHandler handler;
  final Duration? duration;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.duration ?? Duration.zero;
    final totalMs = total.inMilliseconds.toDouble();

    return StreamBuilder<Duration>(
      stream: widget.handler.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final positionMs = position.inMilliseconds.toDouble().clamp(
          0.0,
          totalMs,
        );
        final value = _dragValue ?? positionMs;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                min: 0,
                // A zero max would make the Slider assert; keep it valid until
                // the duration is known.
                max: totalMs <= 0 ? 1 : totalMs,
                value: totalMs <= 0 ? 0 : value.clamp(0.0, totalMs),
                onChanged: totalMs <= 0
                    ? null
                    : (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  widget.handler.seek(Duration(milliseconds: v.round()));
                  setState(() => _dragValue = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _format(Duration(milliseconds: value.round())),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    // Remaining rather than total — more useful mid-track.
                    '-${_format(total - Duration(milliseconds: value.round()))}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _format(Duration d) {
    if (d.isNegative) return '0:00';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (minutes >= 60) {
      final hours = d.inHours;
      final mins = minutes.remainder(60).toString().padLeft(2, '0');
      return '$hours:$mins:$seconds';
    }
    return '$minutes:$seconds';
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
            _ShuffleButton(handler: handler, state: state),
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
            _RepeatButton(handler: handler, state: state),
          ],
        );
      },
    );
  }
}

/// Shuffle, reading its state from the session rather than holding its own.
///
/// The handler is the only place that knows whether shuffle is on, and it
/// publishes that in `playbackState` so the lock screen agrees. A button
/// holding its own boolean would disagree with the lock screen the first time
/// either one was used.
class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton({required this.handler, required this.state});

  final PlexifyAudioHandler handler;
  final PlaybackState? state;

  @override
  Widget build(BuildContext context) {
    final on = state?.shuffleMode == AudioServiceShuffleMode.all;
    return IconButton(
      tooltip: on ? 'Shuffle on' : 'Shuffle off',
      isSelected: on,
      color: on ? Theme.of(context).colorScheme.primary : null,
      icon: const Icon(Icons.shuffle),
      onPressed: () => handler.setShuffleMode(
        on ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
      ),
    );
  }
}

/// Repeat, cycling off, all, one.
///
/// Three states on one button because that is the order people expect, and
/// two controls for one idea would take room the transport needs.
class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.handler, required this.state});

  final PlexifyAudioHandler handler;
  final PlaybackState? state;

  @override
  Widget build(BuildContext context) {
    final mode = state?.repeatMode ?? AudioServiceRepeatMode.none;
    final primary = Theme.of(context).colorScheme.primary;

    return IconButton(
      tooltip: switch (mode) {
        AudioServiceRepeatMode.one => 'Repeat this track',
        AudioServiceRepeatMode.none => 'Repeat off',
        _ => 'Repeat all',
      },
      isSelected: mode != AudioServiceRepeatMode.none,
      color: mode == AudioServiceRepeatMode.none ? null : primary,
      icon: Icon(
        mode == AudioServiceRepeatMode.one ? Icons.repeat_one : Icons.repeat,
      ),
      onPressed: () => handler.setRepeatMode(switch (mode) {
        AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group => AudioServiceRepeatMode.one,
        AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
      }),
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

        return StreamBuilder<List<MediaItem>>(
          stream: handler.queue,
          builder: (context, queueSnapshot) {
            final queue = queueSnapshot.data ?? const <MediaItem>[];
            if (currentIndex == null || currentIndex + 1 >= queue.length) {
              return const SizedBox.shrink();
            }

            final upcoming = queue.sublist(currentIndex + 1);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Up next', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  // `onReorderItem` rather than the deprecated `onReorder`,
                  // which reported the destination as an index in the list
                  // *before* the dragged item was taken out and left every
                  // caller to correct for it. This one is already adjusted.
                  onReorderItem: (oldOffset, newOffset) =>
                      handler.moveQueueItem(
                        currentIndex + 1 + oldOffset,
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
                          trailing: ReorderableDragStartListener(
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
