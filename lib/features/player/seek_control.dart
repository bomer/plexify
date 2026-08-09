import 'package:flutter/material.dart';

import '../../core/audio/playback_handler.dart';

/// How a [SeekControl] arranges its slider and its two labels.
enum SeekLayout {
  /// Slider above, elapsed and remaining beneath it at either end. The
  /// expanded player, where there is room and remaining is the more useful of
  /// the two numbers mid-track.
  stacked,

  /// Elapsed, slider, total, all on one line. The desktop transport bar, which
  /// has one line to spend and is read at a glance rather than studied.
  inline,
}

/// A scrub bar over the current track.
///
/// **While dragging, the slider follows the pointer rather than the position
/// stream.** Without that, every incoming position tick yanks the thumb back to
/// where playback actually is and scrubbing is unusable. This is the reason the
/// widget is stateful at all.
///
/// Shared by the expanded player and the desktop transport bar. They differ
/// only in arrangement, and the drag behaviour above is the part that is easy
/// to get wrong, so there is one copy of it.
class SeekControl extends StatefulWidget {
  const SeekControl({
    required this.handler,
    required this.duration,
    this.layout = SeekLayout.stacked,
    super.key,
  });

  final PlexifyAudioHandler handler;
  final Duration? duration;
  final SeekLayout layout;

  @override
  State<SeekControl> createState() => _SeekControlState();
}

class _SeekControlState extends State<SeekControl> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.duration ?? Duration.zero;
    final totalMs = total.inMilliseconds.toDouble();
    final inline = widget.layout == SeekLayout.inline;

    return StreamBuilder<Duration>(
      stream: widget.handler.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final positionMs = position.inMilliseconds.toDouble().clamp(
          0.0,
          totalMs,
        );
        final value = _dragValue ?? positionMs;
        final elapsed = Duration(milliseconds: value.round());

        final slider = SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: inline ? 4 : 3,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: inline ? 5 : 6,
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius: inline ? 10 : 16,
            ),
          ),
          child: Slider(
            min: 0,
            // A zero max makes Slider assert; keep it valid until the duration
            // is known.
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
        );

        final label = inline
            ? theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )
            : theme.textTheme.bodySmall;

        if (inline) {
          return Row(
            children: [
              Text(formatClock(elapsed), style: label),
              Expanded(child: slider),
              // Total rather than remaining. On one line beside a bar that is
              // already showing progress, the length of the track is the thing
              // that is not otherwise on screen.
              Text(formatClock(total), style: label),
            ],
          );
        }

        return Column(
          children: [
            slider,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatClock(elapsed), style: label),
                  Text('-${formatClock(total - elapsed)}', style: label),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A duration as a clock reading: `4:07`, or `1:02:30` past an hour.
///
/// Negative rounds to zero rather than printing a minus, because the only way
/// to get one is remaining time arriving a tick late.
String formatClock(Duration d) {
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
