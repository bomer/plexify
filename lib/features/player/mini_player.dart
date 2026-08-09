import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_handler.dart';
import '../../core/providers.dart';
import '../../core/settings/app_settings.dart';
import '../../shell/layout.dart';
import '../library/artwork.dart';
import 'player_providers.dart';
import 'seek_control.dart';
import 'transport_buttons.dart';

/// Height of the desktop transport bar's content, above any system inset.
///
/// Two rows of controls need the room, and the bar being the one thing on
/// screen at all times is an argument for giving it presence rather than
/// against it.
const double desktopPlayerHeight = 92;

/// Height of the phone bar's row, unchanged.
const double compactPlayerHeight = 64;

/// Artwork edge on the desktop bar.
const double _desktopArtwork = 64;

/// Widest the centre transport column is allowed to get.
///
/// Without a cap the seek bar spans a 34-inch monitor, which makes a minute of
/// music several hundred pixels wide and every scrub a mouse journey.
const double _transportMaxWidth = 620;

/// Persistent transport bar.
///
/// Two shapes rather than one that stretches. On a phone it is a single 64px
/// row: artwork, what is playing, three buttons, and a hairline of progress,
/// with scrubbing left to the expanded player where the target is big enough
/// to hit. On the desktop it is the full transport, because the pointer makes
/// a thin scrub bar usable and the width is there to spend.
///
/// Tapping the artwork and title expands the full Now Playing view, which is a
/// sibling layer in the shell's [Stack] rather than a pushed route, so the
/// screen underneath is never unmounted. **Only that block is the tap target on
/// desktop**, not the whole bar: a slider inside a tappable surface is a
/// scrub that sometimes opens a window instead.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.aboveNavigationBar = false});

  /// Whether a [NavigationBar] sits directly below this.
  ///
  /// When one does it owns the bottom system inset, and reserving it here as
  /// well pads for a screen edge that is two widgets away — roughly doubling
  /// the bar's height for no visible reason.
  final bool aboveNavigationBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final theme = Theme.of(context);
    final reconnecting = ref.watch(reconnectingProvider).valueOrNull ?? false;
    final compact = isCompactLayout(context);

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, itemSnapshot) {
        final item = itemSnapshot.data;
        // Nothing loaded yet — take up no space at all rather than showing an
        // empty bar.
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data;

            void expand() =>
                ref.read(nowPlayingExpandedProvider.notifier).state = true;

            return Material(
              color: theme.colorScheme.surfaceContainerHigh,
              child: SafeArea(
                top: false,
                bottom: !aboveNavigationBar,
                child: compact
                    ? _CompactBar(
                        handler: handler,
                        item: item,
                        state: state,
                        reconnecting: reconnecting,
                        onExpand: expand,
                      )
                    : _DesktopBar(
                        handler: handler,
                        item: item,
                        state: state,
                        reconnecting: reconnecting,
                        onExpand: expand,
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Whether the engine is between tracks and has nothing to play yet.
bool _busy(PlaybackState? state) =>
    state?.processingState == AudioProcessingState.loading ||
    state?.processingState == AudioProcessingState.buffering;

/// The phone bar. Unchanged in shape: one row, one hairline.
class _CompactBar extends StatelessWidget {
  const _CompactBar({
    required this.handler,
    required this.item,
    required this.state,
    required this.reconnecting,
    required this.onExpand,
  });

  final PlexifyAudioHandler handler;
  final MediaItem item;
  final PlaybackState? state;
  final bool reconnecting;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final playing = state?.playing ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniProgress(handler: handler, duration: item.duration),
        InkWell(
          onTap: onExpand,
          child: SizedBox(
            height: compactPlayerHeight,
            child: Row(
              children: [
                const SizedBox(width: 12),
                _Cover(item: item, edge: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: _NowPlayingText(
                    item: item,
                    reconnecting: reconnecting,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: handler.skipToPrevious,
                ),
                if (_busy(state))
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: playing ? handler.pause : handler.play,
                  ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: handler.skipToNext,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The desktop bar: three columns, transport centred.
///
/// Left and right carry equal flex so the centre column is centred against the
/// *window*, not against whatever is left over once the track title has taken
/// what it wants. A long title on one side and a single button on the other
/// would otherwise push the play button visibly off-centre, and it would move
/// every time the track changed.
class _DesktopBar extends StatelessWidget {
  const _DesktopBar({
    required this.handler,
    required this.item,
    required this.state,
    required this.reconnecting,
    required this.onExpand,
  });

  final PlexifyAudioHandler handler;
  final MediaItem item;
  final PlaybackState? state;
  final bool reconnecting;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: desktopPlayerHeight,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onExpand,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _Cover(item: item, edge: _desktopArtwork),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _NowPlayingText(
                        item: item,
                        reconnecting: reconnecting,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _transportMaxWidth,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DesktopTransport(handler: handler, state: state),
                    SeekControl(
                      handler: handler,
                      duration: item.duration,
                      layout: SeekLayout.inline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Queue',
                    icon: const Icon(Icons.queue_music),
                    // The same place the queue has always lived: Up Next inside
                    // the expanded player. This is a way in that says so,
                    // rather than a second copy of the list to keep in step.
                    onPressed: onExpand,
                  ),
                  // **Flexible, or the slider inside it cannot shrink.** A Row
                  // gives its non-flex children unbounded main-axis
                  // constraints, so a nested `Flexible` resolves against
                  // infinity, takes its full width, and overflows the parent
                  // instead. Caught at 801px, which is the narrowest this
                  // layout is ever built at.
                  Flexible(child: _Volume(handler: handler)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shuffle, previous, play, next, repeat, on one centred line.
class _DesktopTransport extends StatelessWidget {
  const _DesktopTransport({required this.handler, required this.state});

  final PlexifyAudioHandler handler;
  final PlaybackState? state;

  @override
  Widget build(BuildContext context) {
    final playing = state?.playing ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShuffleButton(handler: handler, state: state, iconSize: 18),
        IconButton(
          iconSize: 22,
          icon: const Icon(Icons.skip_previous),
          onPressed: handler.skipToPrevious,
        ),
        // A fixed box so the spinner and the button occupy the same space.
        // Without it the row reflows on every track change and the two
        // controls either side of it jump.
        SizedBox(
          width: 40,
          height: 40,
          child: _busy(state)
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton.filled(
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: playing ? handler.pause : handler.play,
                ),
        ),
        IconButton(
          iconSize: 22,
          icon: const Icon(Icons.skip_next),
          onPressed: handler.skipToNext,
        ),
        RepeatButton(handler: handler, state: state, iconSize: 18),
      ],
    );
  }
}

/// Speaker and slider, desktop only.
///
/// **Not offered on a phone at all, deliberately.** There the hardware keys and
/// the OS mixer already own the level, and every competent player leaves them
/// to it; an app-local level alongside them is a second number to get out of
/// step, and the symptom is volume being wrong in a place nobody thinks to
/// look. On a desktop there are no volume keys to speak of and the system mixer
/// is several clicks away, which is the whole reason this earns its place.
///
/// Follows the engine rather than the setting. The two are kept in step by
/// writing both, and reading the one that actually makes the sound means the
/// control cannot lie about what is happening.
class _Volume extends ConsumerStatefulWidget {
  const _Volume({required this.handler});

  final PlexifyAudioHandler handler;

  @override
  ConsumerState<_Volume> createState() => _VolumeState();
}

class _VolumeState extends ConsumerState<_Volume> {
  /// Where to go back to when unmuting.
  ///
  /// Muting by dragging to zero and muting by pressing the speaker are the same
  /// state to the engine, so the level to restore has to be remembered here.
  /// Kept for the life of the bar, which is the life of the app.
  double _beforeMute = 1;

  void _set(double volume) {
    unawaited(widget.handler.setVolume(volume));
    ref.read(settingsProvider.notifier).setVolume(volume);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: widget.handler.volumeStream,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1).clamp(0.0, 1.0);
        final muted = volume <= 0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: muted ? 'Unmute' : 'Mute',
              icon: Icon(switch (volume) {
                <= 0 => Icons.volume_off,
                < 0.5 => Icons.volume_down,
                _ => Icons.volume_up,
              }),
              onPressed: () {
                if (muted) {
                  // A restore to zero would be a button that does nothing,
                  // which is what happens when the app starts up muted.
                  _set(_beforeMute <= 0 ? 1 : _beforeMute);
                } else {
                  _beforeMute = volume;
                  _set(0);
                }
              },
            ),
            // Loose rather than fixed so a narrow window shortens the slider
            // instead of overflowing the bar. Everything to the left of it has
            // a floor; this is the one thing here that can give.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(value: volume, onChanged: _set),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Album art, keyed on the thumb so this is the *same* cache entry the grid
/// already fetched rather than a second download of the same picture.
class _Cover extends StatelessWidget {
  const _Cover({required this.item, required this.edge});

  final MediaItem item;
  final double edge;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: edge,
        height: edge,
        child: Artwork(
          thumb: item.extras?['thumb'] as String?,
          size: 300,
          icon: Icons.music_note,
        ),
      ),
    );
  }
}

/// Title over artist, where the artist line doubles as the status line.
///
/// A reconnect takes seconds and playback has usually just stopped, so without
/// it the player sits silent and looks broken — and the artist is the one thing
/// on this bar nobody is reading at that moment. Sharing the line rather than
/// adding one keeps the bar's height fixed as the connection comes and goes.
class _NowPlayingText extends StatelessWidget {
  const _NowPlayingText({required this.item, required this.reconnecting});

  final MediaItem item;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        if (reconnecting)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Reconnecting…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          )
        else
          Text(
            item.artist ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Hairline progress line across the top of the phone bar.
///
/// Deliberately not interactive — scrubbing belongs in the expanded player,
/// where the target is big enough to hit accurately. This is an at-a-glance
/// indicator of how far through the track you are. The desktop bar has a real
/// scrub bar instead, which is what a pointer makes possible.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.handler, required this.duration});

  final PlexifyAudioHandler handler;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration?.inMilliseconds ?? 0;
    if (totalMs <= 0) return const SizedBox(height: 2);

    return StreamBuilder<Duration>(
      stream: handler.player.positionStream,
      builder: (context, snapshot) {
        final positionMs = snapshot.data?.inMilliseconds ?? 0;
        return LinearProgressIndicator(
          value: (positionMs / totalMs).clamp(0.0, 1.0),
          minHeight: 2,
          backgroundColor: Colors.transparent,
        );
      },
    );
  }
}
