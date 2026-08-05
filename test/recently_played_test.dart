import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/db/recently_played.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/sync/library_writer.dart';

/// "Jump back in" reads from two tables that have no sensible join, so the
/// merge happens in Dart. The failure it guards against is quiet: a shelf
/// that shows only albums looks perfectly fine, and simply never mentions the
/// playlist you spent the evening listening to.
void main() {
  late AppDatabase db;
  late LibraryWriter writer;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    writer = LibraryWriter(db);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Plex stores these as epoch seconds.
  int at(int day) => DateTime.utc(2026, 8, day).millisecondsSinceEpoch ~/ 1000;

  Future<void> seed({
    List<(String, int?)> albums = const [],
    List<(String, int?)> playlists = const [],
  }) async {
    await writer.writeAlbums([
      for (final (key, viewed) in albums)
        PlexAlbum(
          ratingKey: key,
          title: 'Album $key',
          artist: 'Artist',
          lastViewedAt: viewed,
        ),
    ]);
    await writer.writePlaylists([
      for (final (key, viewed) in playlists)
        PlexPlaylist(
          ratingKey: key,
          title: 'Playlist $key',
          itemCount: 12,
          lastViewedAt: viewed,
        ),
    ]);
  }

  Future<List<RecentlyPlayed>> recent() async {
    // Both underlying streams must deliver before the merge is meaningful.
    await container.read(recentlyPlayedAlbumsProvider.future);
    await container.read(recentlyPlayedPlaylistsProvider.future);
    return container.read(recentlyPlayedProvider).valueOrNull ?? const [];
  }

  test('a played playlist appears alongside albums', () async {
    await seed(albums: [('a1', at(1))], playlists: [('p1', at(2))]);

    final items = await recent();

    expect(items.map((i) => i.ratingKey), ['p1', 'a1']);
    expect(items.first.isPlaylist, isTrue);
  });

  test('newest first, whichever kind it is', () async {
    await seed(
      albums: [('a1', at(1)), ('a2', at(4))],
      playlists: [('p1', at(3)), ('p2', at(2))],
    );

    expect((await recent()).map((i) => i.ratingKey), ['a2', 'p1', 'p2', 'a1']);
  });

  test('things never played stay off the shelf', () async {
    await seed(
      albums: [('a1', at(1)), ('a2', null)],
      playlists: [('p1', null)],
    );

    // The sidebar lists every playlist; this shelf is about what you did, not
    // what exists. An unplayed one here would be a recommendation pretending
    // to be a memory.
    expect((await recent()).map((i) => i.ratingKey), ['a1']);
  });

  test('a playlist says what it is, since it has no artist', () async {
    await seed(playlists: [('p1', at(1))]);

    // Also what tells the two kinds apart at a glance in a mixed row.
    expect((await recent()).single.subtitle, 'Playlist · 12 tracks');
  });

  test('an album still names its artist', () async {
    await seed(albums: [('a1', at(1))]);

    expect((await recent()).single.subtitle, 'Artist');
  });

  test('nothing played yet is empty, not an error', () async {
    await seed(albums: [('a1', null)]);

    expect(await recent(), isEmpty);
  });
}
