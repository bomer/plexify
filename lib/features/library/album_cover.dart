import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/audio/playback_source.dart';
import '../../core/providers.dart';
import '../../shell/layout.dart';
import '../player/playback_controller.dart';
import 'artwork.dart';

/// Album artwork with a play button that appears on hover.
///
/// Spotify's affordance, and it earns its place for the same reason there:
/// tapping a cover opens the album, so on a desktop there is otherwise no way
/// to *play* one without a round trip through its page and back. The button
/// makes the common case one click.
///
/// **Hover only, and desktop only.** A phone has no hover state, so the button
/// would have to be permanently visible — which is a control sitting on top of
/// every cover in a grid, on the platform with the least room for it. Long
/// press is the phone's answer, and tapping through to the album page is
/// already two taps.
class AlbumCover extends ConsumerStatefulWidget {
  const AlbumCover({required this.album, required this.size, super.key});

  final PlexAlbum album;

  /// Side length of the square. The button is scaled from it rather than
  /// fixed, so a shelf tile and a grid cell look like the same control.
  final double size;

  @override
  ConsumerState<AlbumCover> createState() => _AlbumCoverState();
}

class _AlbumCoverState extends ConsumerState<AlbumCover> {
  bool _hovering = false;

  /// Roughly a fifth of the cover, which is what reads as "part of the
  /// artwork" rather than "a button placed on it".
  static const _buttonFraction = 0.2;

  /// Below this the button is more obstruction than affordance — it would
  /// cover most of a small cover.
  static const _minCoverSize = 96.0;

  Future<void> _play() async {
    final tracks = await ref.read(
      tracksProvider(widget.album.ratingKey).future,
    );
    if (!mounted) return;
    await ref
        .read(playbackControllerProvider)
        ?.playTracks(
          tracks,
          source: PlaybackSource(
            PlaybackSourceKind.album,
            widget.album.ratingKey,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offer = !isCompactLayout(context) && widget.size >= _minCoverSize;

    final cover = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Artwork(thumb: widget.album.thumb, size: 600),
    );

    if (!offer) return cover;

    final diameter = widget.size * _buttonFraction;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          cover,
          Positioned(
            right: diameter * 0.35,
            bottom: diameter * 0.35,
            child: AnimatedSlide(
              // Rises into place rather than appearing, which reads as the
              // cover responding rather than something being drawn over it.
              offset: _hovering ? Offset.zero : const Offset(0, 0.35),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _hovering ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: IgnorePointer(
                  ignoring: !_hovering,
                  child: Material(
                    shape: const CircleBorder(),
                    color: theme.colorScheme.primary,
                    elevation: 6,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _play,
                      child: SizedBox(
                        width: diameter,
                        height: diameter,
                        child: Icon(
                          Icons.play_arrow,
                          size: diameter * 0.6,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
