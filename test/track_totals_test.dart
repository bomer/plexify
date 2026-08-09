import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/features/library/track_totals.dart';
import 'package:plexify/features/player/seek_control.dart';

/// Two different ways of saying how long something is, which is the point.
void main() {
  group('running time', () {
    test('reads the way a person would say it', () {
      expect(formatRunningTime(const Duration(minutes: 48, seconds: 33)),
          '48 min 33 sec');
      expect(formatRunningTime(const Duration(hours: 1, minutes: 12)),
          '1 hr 12 min');
      expect(formatRunningTime(const Duration(seconds: 42)), '42 sec');
    });

    test('drops the unit that would be zero', () {
      // "48 min 0 sec" and "1 hr 0 min" are both things no one says.
      expect(formatRunningTime(const Duration(minutes: 48)), '48 min');
      expect(formatRunningTime(const Duration(hours: 2)), '2 hr');
    });

    test('drops seconds once there are hours', () {
      // Four numbers in a row on a subtitle, for a precision nobody wanted.
      expect(
        formatRunningTime(const Duration(hours: 1, minutes: 12, seconds: 44)),
        '1 hr 12 min',
      );
    });

    test('has something to say about nothing', () {
      expect(formatRunningTime(Duration.zero), '0 sec');
      expect(formatRunningTime(const Duration(seconds: -5)), '0 sec');
    });

    test('is not a clock reading', () {
      // The distinction this file exists for. `1:47:12` is right for a position
      // inside a track and wrong for a length, and the two formatters live one
      // import apart, so it is worth one assertion that they differ.
      const long = Duration(hours: 1, minutes: 47, seconds: 12);
      expect(formatClock(long), '1:47:12');
      expect(formatRunningTime(long), '1 hr 47 min');
    });
  });

  group('the line under a title', () {
    test('counts songs and adds the running time', () {
      expect(
        describeTracks(12, const Duration(minutes: 48, seconds: 33)),
        '12 songs · 48 min 33 sec',
      );
    });

    test('one song is not one songs', () {
      expect(describeTracks(1, const Duration(minutes: 3)), '1 song · 3 min');
    });

    test('an empty playlist still reads as a sentence', () {
      expect(describeTracks(0, Duration.zero), '0 songs · 0 sec');
    });
  });

  group('totalling a track list', () {
    PlexTrack track(int ms) => PlexTrack(
      ratingKey: '$ms',
      title: 't',
      index: 1,
      durationMs: ms,
      album: 'a',
      artist: 'b',
    );

    test('adds every track up', () {
      expect(
        totalDuration([track(60000), track(90000), track(30000)]),
        const Duration(minutes: 3),
      );
    });

    test('a track Plex gave no duration for counts as nothing, not as a gap', () {
      expect(totalDuration([track(60000), track(0)]), const Duration(minutes: 1));
    });

    test('nothing totals nothing', () {
      expect(totalDuration(const []), Duration.zero);
    });
  });
}
