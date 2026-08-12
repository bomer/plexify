import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/features/library/track_context_menu.dart';

/// The desktop half of the phone's long press.
///
/// Track rows put their extra actions in a bottom sheet, and every call site
/// guards it with `compact ? … : null` — right, because a sheet is a phone
/// gesture and the desktop shows its stars inline instead. The cost was that
/// anything added to that sheet existed on one platform only, which is how
/// "Start radio" ended up unreachable on Windows for a whole release cycle.
///
/// So both halves are pinned: a right-click offers the menu where there is no
/// long press, and offers nothing where there already is one.
void main() {
  const track = PlexTrack(
    ratingKey: 't1',
    title: 'Idioteque',
    index: 1,
    durationMs: 200000,
    album: 'Kid A',
    artist: 'Radiohead',
    albumRatingKey: 'b1',
    partKey: '/library/parts/1/file.flac',
  );

  Future<void> pumpRow(WidgetTester tester, {required bool compact}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => withTrackMenu(
                ref: ref,
                track: track,
                compact: compact,
                child: const ListTile(title: Text('Idioteque')),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A right-click, which Flutter models as a secondary tap.
  Future<void> rightClick(WidgetTester tester, Finder target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a right-click offers radio on the desktop', (tester) async {
    await pumpRow(tester, compact: false);

    await rightClick(tester, find.text('Idioteque'));

    expect(find.text('Start radio'), findsOneWidget);
    // Names the artist, because a station is built from them rather than from
    // the song that was clicked.
    expect(find.text('Music like Radiohead'), findsOneWidget);
  });

  testWidgets('a phone gets nothing extra, having the long press already', (
    tester,
  ) async {
    // Two gestures for one menu is a way for them to disagree, and the sheet
    // is the better one on a touch screen.
    await pumpRow(tester, compact: true);

    await rightClick(tester, find.text('Idioteque'));

    expect(find.text('Start radio'), findsNothing);
  });
}
