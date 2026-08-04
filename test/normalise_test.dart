import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/db/normalise.dart';

/// Normalisation decides two things: whether typing "dont look back" finds
/// "Don't Look Back", and whether a MusicBrainz release is recognised as one
/// you already own. Both fail quietly and confusingly when it is wrong, so the
/// behaviour is pinned here.
void main() {
  group('normalise', () {
    test('lowercases', () {
      expect(normalise('Kid A'), 'kid a');
      expect(normalise('RADIOHEAD'), 'radiohead');
    });

    test('drops apostrophes rather than splitting the word', () {
      // "don t" would not match a search for "dont".
      expect(normalise("Don't Look Back"), 'dont look back');
      expect(normalise("Ain't No Sunshine"), 'aint no sunshine');
    });

    test('drops bracketing and punctuation', () {
      expect(normalise('Kid A (Remastered)'), 'kid a remastered');
      expect(normalise('Album [Deluxe Edition]'), 'album deluxe edition');
      expect(normalise('Song - Live!'), 'song live');
    });

    test('collapses runs of whitespace', () {
      expect(normalise('Kid    A'), 'kid a');
      expect(normalise('  Kid A  '), 'kid a');
      expect(normalise('Kid\tA'), 'kid a');
    });

    test('folds accents so ascii typing still matches', () {
      expect(normalise('Björk'), 'bjork');
      expect(normalise('Sigur Rós'), 'sigur ros');
      expect(normalise('Beyoncé'), 'beyonce');
      expect(normalise('Motörhead'), 'motorhead');
    });

    test('expands ligatures and eszett', () {
      expect(normalise('Encyclopædia'), 'encyclopaedia');
      expect(normalise('Straße'), 'strasse');
    });

    test('keeps digits', () {
      expect(normalise('1999'), '1999');
      expect(normalise('Blink-182'), 'blink182');
    });

    test('handles empty and punctuation-only input', () {
      expect(normalise(''), '');
      expect(normalise('   '), '');
      expect(normalise('!!!'), '');
    });

    test('is idempotent', () {
      // Normalising already-normalised text must not change it, or repeated
      // sync passes would churn the stored column.
      const inputs = ["Don't Look Back", 'Sigur Rós', 'Kid A (Remastered)'];
      for (final input in inputs) {
        expect(normalise(normalise(input)), normalise(input));
      }
    });
  });
}
