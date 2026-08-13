import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/catalog/catalog_models.dart';
import 'package:plexify/core/catalog/musicbrainz_client.dart';
import 'package:plexify/core/db/app_database.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/core/settings/app_settings.dart';
import 'package:plexify/core/sync/library_writer.dart';
import 'package:plexify/features/acquire/catalog_artist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finding an artist the library has never heard of.
///
/// Everything below the search box already answered "which *records* do I not
/// have". None of it could answer "who is this band and what did they make",
/// because the only artist page took a `PlexArtist` and therefore required the
/// artist to be in the library already.
///
/// The two things worth guarding are the ones that would quietly make this
/// worse than useless: offering an artist you already own, which invites
/// downloading records that are already on the shelf, and offering albums you
/// already own on a page reached precisely *because* the artist name did not
/// match.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SettingsStore settings;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // The release cards render artwork, which reaches the artwork cache, which
    // reads a budget out of settings. Nothing here is about settings; this just
    // stops that chain throwing.
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());
  });
  tearDown(() => db.close());

  Map<String, Object?> artist(
    String id,
    String name, {
    int score = 80,
    String? disambiguation,
  }) => {
    'id': id,
    'name': name,
    'score': score,
    'disambiguation': ?disambiguation,
  };

  Map<String, Object?> releaseGroup(
    String id,
    String title, {
    String artistName = 'Boards of Canada',
    String type = 'Album',
    List<String> secondary = const [],
  }) => {
    'id': id,
    'title': title,
    'first-release-date': '1998',
    'primary-type': type,
    'secondary-types': secondary,
    'artist-credit': [
      {
        'name': artistName,
        'artist': {'id': 'a1', 'name': artistName},
      },
    ],
  };

  /// A container wired to the in-memory database and a recorded MusicBrainz.
  ProviderContainer container(Map<String, Object?> Function(Uri) respond) {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(settings),
        catalogEnabledProvider.overrideWithValue(true),
        musicBrainzClientProvider.overrideWithValue(
          MusicBrainzClient(
            httpClient: MockClient(
              (request) async =>
                  http.Response(jsonEncode(respond(request.url)), 200),
            ),
            sleep: (_) async {},
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('who turns up in the search tier', () {
    test('an artist already in the library is not offered again', () async {
      await LibraryWriter(db).writeArtists([
        const PlexArtist(ratingKey: 'ar1', title: 'The Beatles'),
      ]);

      final c = container(
        (_) => {
          'artists': [
            // Differently cased and punctuated on purpose. The library spells
            // performers however the file tags did and MusicBrainz spells them
            // canonically, so an exact string compare would let this through.
            artist('mb-beatles', 'the beatles'),
            artist('mb-other', 'Boards of Canada'),
          ],
        },
      );

      final found = await c.read(catalogArtistSearchProvider('beat').future);

      // Listing them twice invites downloading a discography already on the
      // shelf, and the local tier above already has them.
      expect(found.map((a) => a.mbid), ['mb-other']);
    });

    test('a differently punctuated library name still matches', () async {
      await LibraryWriter(db).writeArtists([
        const PlexArtist(ratingKey: 'ar1', title: 'Beatles, The'),
      ]);

      final c = container(
        (_) => {
          'artists': [artist('mb-beatles', 'Beatles The')],
        },
      );

      expect(await c.read(catalogArtistSearchProvider('beat').future), isEmpty);
    });

    test('the same artist listed twice appears once', () async {
      final c = container(
        (_) => {
          'artists': [
            artist('mb-1', 'Boards of Canada'),
            artist('mb-1', 'Boards of Canada'),
          ],
        },
      );

      expect(
        await c.read(catalogArtistSearchProvider('boards').future),
        hasLength(1),
      );
    });

    test('nothing is asked when the catalog is switched off', () async {
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          settingsStoreProvider.overrideWithValue(settings),
          catalogEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(c.dispose);

      // Off has to mean off rather than hidden, which is the rule the whole
      // catalog tier is built under.
      expect(await c.read(catalogArtistSearchProvider('boards').future), isEmpty);
    });
  });

  group('the discography screen', () {
    Widget host(ProviderContainer c, CatalogArtist who) =>
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: CatalogArtistScreen(artist: who),
          ),
        );

    testWidgets('lists albums and EPs, not the compilations', (tester) async {
      final c = container(
        (_) => {
          'release-group-count': 4,
          'release-groups': [
            releaseGroup('r1', 'Music Has the Right to Children'),
            releaseGroup('r2', 'Twoism', type: 'EP'),
            releaseGroup('r3', 'The Best Of', secondary: ['Compilation']),
            releaseGroup('r4', 'Live in Concert', secondary: ['Live']),
          ],
        },
      );

      await tester.pumpWidget(
        host(
          c,
          const CatalogArtist(mbid: 'a1', name: 'Boards of Canada', score: 90),
        ),
      );
      await tester.pumpAndSettle();

      // An artist with fifteen albums routinely has sixty compilations, which
      // turns a discography into a wall nobody reads.
      expect(find.text('Music Has the Right to Children'), findsOneWidget);
      expect(find.text('Twoism'), findsOneWidget);
      expect(find.text('The Best Of'), findsNothing);
      expect(find.text('Live in Concert'), findsNothing);
    });

    testWidgets('a record you already own is marked, not offered', (
      tester,
    ) async {
      await LibraryWriter(db).writeAlbums([
        const PlexAlbum(
          ratingKey: 'al1',
          title: 'Twoism',
          artist: 'Boards of Canada',
        ),
      ]);

      final c = container(
        (_) => {
          'release-group-count': 2,
          'release-groups': [
            releaseGroup('r1', 'Music Has the Right to Children'),
            releaseGroup('r2', 'Twoism', type: 'EP'),
          ],
        },
      );

      await tester.pumpWidget(
        host(
          c,
          const CatalogArtist(mbid: 'a1', name: 'Boards of Canada', score: 90),
        ),
      );
      await tester.pumpAndSettle();

      // **This is why the check exists at all.** The artist reached this page
      // precisely by *not* matching a library name, so owning some of their
      // records anyway is the normal case rather than an edge one, and without
      // it the page offers to download what is already there.
      //
      // Asserted on the card itself and not only on the summary line. The
      // summary counts owned records independently, so checking it alone
      // passes with the card's own `owned` flag forced to false, which is a
      // guard that survives the bug it guards against.
      expect(find.textContaining('in your library'), findsOneWidget);
      expect(find.textContaining('1 already yours'), findsOneWidget);

      // And exactly one of the two is still offered.
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('an artist with no albums says so rather than showing nothing', (
      tester,
    ) async {
      final c = container(
        (_) => {'release-group-count': 0, 'release-groups': <Object>[]},
      );

      await tester.pumpWidget(
        host(c, const CatalogArtist(mbid: 'a1', name: 'Nobody', score: 90)),
      );
      await tester.pumpAndSettle();

      // "This artist released no albums" and "MusicBrainz has them under a
      // different entry" look identical from a blank page, and only one is
      // worth acting on.
      expect(find.textContaining('Nothing listed for Nobody'), findsOneWidget);
    });
  });
}
