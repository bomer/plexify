import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/providers.dart';
import 'package:plexify/features/library/artist_index.dart';
import 'package:plexify/features/library/artist_list.dart';

/// An A–Z rail is only as useful as the letters it files things under, so the
/// bucketing rules carry most of the weight here.
void main() {
  group('artistSortKey', () {
    test('ignores a leading article', () {
      // Plex files "The Beatles" under B through titleSort. Disagreeing would
      // give the app a different alphabet from the server it browses.
      expect(artistSortKey('the beatles'), 'beatles');
      expect(artistSortKey('a tribe called quest'), 'tribe called quest');
      expect(artistSortKey('an emerald city'), 'emerald city');
    });

    test('only strips whole words', () {
      expect(artistSortKey('anathema'), 'anathema');
      expect(artistSortKey('theory of a deadman'), 'theory of a deadman');
      expect(artistSortKey('air'), 'air');
    });

    test('leaves an artist that is only an article alone', () {
      // "The The" must file somewhere rather than under nothing at all.
      expect(artistSortKey('the the'), 'the');
    });
  });

  group('artistBucket', () {
    test('files by first letter after the article', () {
      expect(artistBucket('the beatles'), 'B');
      expect(artistBucket('radiohead'), 'R');
    });

    test('sweeps anything not starting with a letter into #', () {
      // A rail with a bucket per symbol would be too long to hit with a thumb.
      expect(artistBucket('65daysofstatic'), '#');
      expect(artistBucket('1975'), '#');
      expect(artistBucket(''), '#');
    });
  });

  group('ArtistIndex', () {
    PlexArtist artist(String title) =>
        PlexArtist(ratingKey: title, title: title);

    test('orders by sort key, not raw title', () {
      final index = ArtistIndex.from([
        artist('Radiohead'),
        artist('The Beatles'),
        artist('Aphex Twin'),
      ]);

      expect(index.artists.map((a) => a.title), [
        'Aphex Twin',
        'The Beatles',
        'Radiohead',
      ]);
    });

    test('folds accents so Björk files under B', () {
      final index = ArtistIndex.from([artist('Björk'), artist('Beck')]);

      expect(index.buckets, ['B']);
      expect(index.artists.map((a) => a.title), ['Beck', 'Björk']);
    });

    test('lists only buckets that have artists, with # last', () {
      final index = ArtistIndex.from([
        artist('65daysofstatic'),
        artist('Radiohead'),
        artist('Aphex Twin'),
      ]);

      // Every rail target has to go somewhere; dead letters are worse than a
      // short rail.
      expect(index.buckets, ['A', 'R', '#']);

      // # is last in the list as well as on the rail. ASCII would sort digits
      // first, which would leave the rail pointing at the wrong end.
      expect(index.bucketStart['A'], 0);
      expect(index.bucketStart['R'], 1);
      expect(index.bucketStart['#'], 2);
      expect(index.artists.last.title, '65daysofstatic');
    });

    test('marks exactly the rows that begin a bucket', () {
      final index = ArtistIndex.from([
        artist('Aphex Twin'),
        artist('Autechre'),
        artist('Boards of Canada'),
      ]);

      expect(index.startsBucket(0), isTrue);
      expect(index.startsBucket(1), isFalse);
      expect(index.startsBucket(2), isTrue);
    });

    test('orders ties by title rather than by input order', () {
      final index = ArtistIndex.from([artist('The Cure'), artist('Cure')]);

      expect(index.artists.map((a) => a.title), ['Cure', 'The Cure']);
    });
  });

  testWidgets('the rail jumps the list to a letter', (tester) async {
    final artists = [
      for (final letter in ['A', 'B', 'C', 'D', 'E', 'F'])
        for (var i = 0; i < 20; i++)
          PlexArtist(ratingKey: '$letter$i', title: '$letter artist $i'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [plexClientProvider.overrideWithValue(null)],
        child: MaterialApp(
          home: Scaffold(
            body: ArtistList(artists: artists, onOpen: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('A artist 0'), findsOneWidget);
    expect(find.text('F artist 0'), findsNothing);

    // Tap the bottom of the rail, which is where F sits.
    final rail = find.byType(ArtistList);
    final box = tester.getRect(rail);
    await tester.tapAt(Offset(box.right - 14, box.bottom - 20));
    await tester.pumpAndSettle();

    expect(find.text('F artist 0'), findsOneWidget);
    expect(find.text('A artist 0'), findsNothing);
  });
}
