import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../core/audio/playback_handler.dart';

/// The filled disc under a play or pause glyph.
///
/// Near-white on dark and near-black on light, rather than the accent. It is
/// the largest solid block of colour in the transport and sits inches from the
/// artwork, so leaving it on `primary` meant the chrome and the content were
/// arguing about which one you should be looking at.
ButtonStyle playButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return IconButton.styleFrom(
    backgroundColor: scheme.onSurface,
    foregroundColor: scheme.surface,
  );
}

/// Shuffle, reading its state from the session rather than holding its own.
///
/// The handler is the only place that knows whether shuffle is on, and it
/// publishes that in `playbackState` so the lock screen agrees. A button
/// holding its own boolean would disagree with the lock screen the first time
/// either one was used, and now that the control appears in two places at once
/// it would disagree with itself as well.
class ShuffleButton extends StatelessWidget {
  const ShuffleButton({
    required this.handler,
    required this.state,
    this.iconSize,
    super.key,
  });

  final PlexifyAudioHandler handler;
  final PlaybackState? state;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final on = state?.shuffleMode == AudioServiceShuffleMode.all;
    return IconButton(
      tooltip: on ? 'Shuffle on' : 'Shuffle off',
      isSelected: on,
      iconSize: iconSize,
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
/// Three states on one button because that is the order people expect, and two
/// controls for one idea would take room the transport needs.
class RepeatButton extends StatelessWidget {
  const RepeatButton({
    required this.handler,
    required this.state,
    this.iconSize,
    super.key,
  });

  final PlexifyAudioHandler handler;
  final PlaybackState? state;
  final double? iconSize;

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
      iconSize: iconSize,
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
