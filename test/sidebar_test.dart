import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/shell/sidebar.dart';

/// The second line under a playlist name in the sidebar.
///
/// Small, and worth pinning because every branch of it is a row that has to be
/// the same height as the others: an empty string here leaves one playlist
/// visibly shorter than the eleven around it.
void main() {
  PlexPlaylist playlist({int count = 0, bool smart = false}) =>
      PlexPlaylist(ratingKey: 'p', title: 'p', itemCount: count, smart: smart);

  test('counts what is in it', () {
    expect(playlistSubtitle(playlist(count: 148)), '148 tracks');
  });

  test('one track is not one tracks', () {
    expect(playlistSubtitle(playlist(count: 1)), '1 track');
  });

  test('smart comes first, because it changes what the row means', () {
    // Those contents are generated from rules, so what is in there today is
    // not what was in there last week. That is the reason to open one, and it
    // outranks the count.
    expect(
      playlistSubtitle(playlist(count: 30, smart: true)),
      'Smart · 30 tracks',
    );
  });

  test('a playlist with no count still fills the line', () {
    // Plex omits leafCount on some responses and the sidebar renders whatever
    // the last sync stored, so this is a real state rather than a defensive
    // one. An empty string here would make the row shorter than its neighbours.
    expect(playlistSubtitle(playlist()), 'Playlist');
    expect(playlistSubtitle(playlist(smart: true)), 'Smart');
  });
}
