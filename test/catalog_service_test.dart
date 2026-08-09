import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/catalog/catalog_models.dart';
import 'package:plexify/core/catalog/catalog_service.dart';
import 'package:plexify/core/catalog/catalog_store.dart';
import 'package:plexify/core/catalog/musicbrainz_client.dart';
import 'package:plexify/core/db/app_database.dart';

/// The catalog against a real in-memory database and a recorded web service.
///
/// Two rules are asserted here more than anything else. **A name is not a key**,
/// so resolving one to a MusicBrainz id has to be able to answer "I do not
/// know" — the alternative is attaching one artist's discography to another's
/// page and offering to download fifteen records they never made. And **stale
/// beats empty**: this is the lower tier of the app and must never be able to
/// make a page blank while a rate-limited request is paced.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  ({CatalogService service, List<Uri> calls}) build(
    Map<String, Object?> Function(Uri) respond, {
    int status = 200,
  }) {
    final calls = <Uri>[];
    final client = MusicBrainzClient(
      httpClient: MockClient((request) async {
        calls.add(request.url);
        return http.Response(jsonEncode(respond(request.url)), status);
      }),
      sleep: (_) async {},
    );
    return (
      service: CatalogService(client: client, store: CatalogStore(db)),
      calls: calls,
    );
  }

  Map<String, Object?> releaseGroup(
    String id,
    String title, {
    String artist = 'Radiohead',
    List<String> secondary = const [],
  }) => {
    'id': id,
    'title': title,
    'first-release-date': '1997',
    'primary-type': 'Album',
    'secondary-types': secondary,
    'artist-credit': [
      {
        'name': artist,
        'artist': {'id': 'artist-1', 'name': artist},
      },
    ],
  };

  test('signing out does not throw away what MusicBrainz told us', () async {
    final store = CatalogStore(db);
    await store.saveAnswer('artist:mb-artist', const [
      CatalogRelease(mbid: 'mb-1', title: 'OK Computer', artist: 'Radiohead'),
    ]);
    await store.saveArtist('Radiohead', mbid: 'mb-artist');
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            ratingKey: 'a1',
            title: 'In Rainbows',
            normalisedTitle: 'in rainbows',
            artistTitle: 'Radiohead',
            normalisedArtist: 'radiohead',
          ),
        );

    // What sign-out and a change of server both run.
    await db.clearLibrary();

    // **The deliberate exception to "signing out clears every cache".** Every
    // other table here is keyed on Plex ratingKeys, which are server-scoped, so
    // keeping them would blend two libraries. MBIDs are global — they name the
    // same record on any server and to any other tool — so there is nothing to
    // collide, and wiping them would cost a fresh round of rate-limited lookups
    // for discographies that have not changed.
    //
    // Guarded because it is one line to undo: adding the catalog tables to
    // `clearLibrary` looks tidy and nothing else would notice.
    expect(await db.countAlbums(), 0);
    expect(await db.countCatalogReleases(), 1);
    expect((await store.answerFor('artist:mb-artist'))?.releases, hasLength(1));
    expect((await store.artistFor('Radiohead'))?.mbid, 'mb-artist');
  });

  test('a repeated search is answered from the cache', () async {
    final fake = build(
      (_) => {
        'release-groups': [releaseGroup('mb-1', 'OK Computer')],
      },
    );

    await fake.service.search('ok computer');
    final second = await fake.service.search('ok computer');

    expect(second.single.title, 'OK Computer');
    // Every avoided request is a second nobody spends waiting, because the
    // client paces itself to stay inside MusicBrainz's limit.
    expect(fake.calls, hasLength(1));
  });

  test('the cache keeps the order MusicBrainz gave', () async {
    final store = CatalogStore(db);
    await store.saveAnswer('search:x', const [
      CatalogRelease(mbid: 'c', title: 'Third', artist: 'A'),
      CatalogRelease(mbid: 'a', title: 'First', artist: 'A'),
      CatalogRelease(mbid: 'b', title: 'Second', artist: 'A'),
    ]);

    // Search results are ranked by relevance, and the rows carry no ordering of
    // their own — restoring them in whatever order SQLite happened to return
    // would silently discard the ranking.
    final answer = await store.answerFor('search:x');
    expect(answer!.releases.map((r) => r.title), ['Third', 'First', 'Second']);
  });

  test('a failed refresh leaves the cached answer in place', () async {
    var failing = false;
    final calls = <Uri>[];
    final client = MusicBrainzClient(
      httpClient: MockClient((request) async {
        calls.add(request.url);
        if (failing) return http.Response('{}', 503);
        return http.Response(
          jsonEncode({
            'release-groups': [releaseGroup('mb-1', 'OK Computer')],
          }),
          200,
        );
      }),
      sleep: (_) async {},
    );
    final service = CatalogService(client: client, store: CatalogStore(db));

    await service.search('ok computer');
    // Force a refresh by aging the stored answer past its window.
    await db.customStatement('UPDATE catalog_queries SET fetched_at = 0');
    failing = true;

    final result = await service.search('ok computer');

    // A single 503 must not poison the cache for a week, and it must not blank
    // a page that had a perfectly good answer a moment ago.
    expect(result.single.title, 'OK Computer');
  });

  test('an exact name beats a higher-scored near miss', () async {
    final fake = build(
      (uri) => uri.path.endsWith('/artist')
          ? {
              'artists': [
                {'id': 'wrong', 'name': 'Genesis P-Orridge', 'score': 100},
                {'id': 'right', 'name': 'Genesis', 'score': 92},
              ],
            }
          : {'release-groups': <Object>[]},
    );

    final resolved = await fake.service.resolveArtist('Genesis');

    // Taking the top hit is the obvious implementation and a real bug: it
    // attaches the wrong discography to an artist page and offers to download
    // it.
    expect(resolved?.mbid, 'right');
  });

  test('a low-confidence match resolves to nobody', () async {
    final fake = build(
      (uri) => uri.path.endsWith('/artist')
          ? {
              'artists': [
                {'id': 'maybe', 'name': 'The Bandd', 'score': 55},
              ],
            }
          : {'release-groups': <Object>[]},
    );

    // "We do not know who this is" costs an empty section. Guessing costs a
    // page of albums attributed to the wrong person.
    expect(await fake.service.resolveArtist('The Band'), isNull);
  });

  test('an artist nobody has heard of is only asked about once', () async {
    final fake = build((_) => {'artists': <Object>[]});

    await fake.service.resolveArtist('James Home Recordings 2004');
    await fake.service.resolveArtist('James Home Recordings 2004');

    // Plenty of artists in a personal library are not in MusicBrainz. Without a
    // negative cache each of them re-queries on every visit, holding up the
    // paced queue behind an answer already known to be nothing.
    expect(fake.calls, hasLength(1));
  });

  test('an unresolved artist yields an unresolved discography', () async {
    final fake = build((_) => {'artists': <Object>[]});

    final discography = await fake.service.discographyFor('Nobody At All');

    // Distinct from "no albums missing", which is good news. Collapsing the two
    // makes a failed lookup look like a complete collection.
    expect(discography.resolved, isFalse);
    expect(discography.releases, isEmpty);
  });

  test('a resolved artist gets their discography, paged and cached', () async {
    final fake = build(
      (uri) => uri.path.endsWith('/artist')
          ? {
              'artists': [
                {'id': 'artist-1', 'name': 'Radiohead', 'score': 100},
              ],
            }
          : {
              'release-group-count': 2,
              'release-groups': [
                releaseGroup('mb-1', 'OK Computer'),
                releaseGroup('mb-2', 'The Best Of', secondary: ['Compilation']),
              ],
            },
    );

    final first = await fake.service.discographyFor('Radiohead');
    expect(first.artistMbid, 'artist-1');
    expect(first.releases, hasLength(2));

    final again = await fake.service.discographyFor('Radiohead');
    expect(again.releases, hasLength(2));
    // Two requests total — one to resolve the artist, one for the discography.
    // The second visit adds none.
    expect(fake.calls, hasLength(2));

    // The compilation is stored but not a primary work: the filter belongs to
    // the caller, so search can still find it while the artist page does not
    // drown in it.
    expect(again.releases.where((r) => r.isPrimaryWork), hasLength(1));
  });
}
