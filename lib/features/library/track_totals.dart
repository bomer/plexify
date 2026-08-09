import '../../core/plex/plex_models.dart';

/// "12 songs · 48 min 33 sec", the line under an album or playlist title.
///
/// Worth having in one place because the two screens that show it disagreed
/// about everything: one said "tracks" and the other said nothing at all, and
/// neither gave a running time, which is the thing you actually want to know
/// before putting a playlist on.
String describeTracks(int count, Duration total) =>
    '${_songs(count)} · ${formatRunningTime(total)}';

String _songs(int count) => count == 1 ? '1 song' : '$count songs';

/// A running time in the units a person would say it in.
///
/// Not a clock reading. `1:47:12` is right for a position within a track and
/// wrong for a length: nobody describes an album as one forty-seven twelve.
/// Seconds are dropped once there are hours, because at that scale they are
/// noise, and the whole string is otherwise four numbers long.
String formatRunningTime(Duration total) {
  if (total.inSeconds <= 0) return '0 sec';

  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);

  if (hours > 0) {
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
  if (minutes > 0) {
    return seconds == 0 ? '$minutes min' : '$minutes min $seconds sec';
  }
  return '$seconds sec';
}

/// Total playing time of a track list.
///
/// Tracks Plex has no duration for count as zero rather than being skipped,
/// which is the same thing arithmetically and saves every caller a filter.
Duration totalDuration(Iterable<PlexTrack> tracks) => Duration(
  milliseconds: tracks.fold(0, (sum, track) => sum + track.durationMs),
);

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
