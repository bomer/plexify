import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/shell/horizontal_scroll.dart';

/// Home's shelves are horizontal, which is fine on a phone and close to
/// unusable on a desktop: the wheel scrolls the page instead, dragging is
/// disabled for mice by default, and nothing on screen says the row moves at
/// all. None of that shows up as an error — the shelf simply sits there.
void main() {
  late ScrollController controller;

  Future<void> pump(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // A vertical list around the shelf, as on Home. This is what a
          // stolen wheel event scrolls instead.
          body: ListView(
            children: [
              SizedBox(
                height: 200,
                child: HorizontalScroll(
                  builder: (context, c) {
                    controller = c;
                    return ListView.builder(
                      controller: c,
                      scrollDirection: Axis.horizontal,
                      itemCount: 40,
                      itemBuilder: (_, i) =>
                          SizedBox(width: 160, child: Text('Tile $i')),
                    );
                  },
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a mouse wheel moves the shelf, not the page', (tester) async {
    await pump(tester, size: const Size(1200, 800));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final where = tester.getCenter(find.text('Tile 0'));
    tester.binding.handlePointerEvent(pointer.hover(where));
    tester.binding.handlePointerEvent(pointer.scroll(const Offset(0, 300)));
    await tester.pump();

    // A wheel produces a vertical delta and `Scrollable` only applies deltas
    // along its own axis, so without translating it the event falls through
    // and the page scrolls under a shelf that never moves.
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('a mouse can drag the shelf', (tester) async {
    await pump(tester, size: const Size(1200, 800));

    await tester.dragFrom(
      tester.getCenter(find.text('Tile 0')),
      const Offset(-300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    // Flutter leaves mice out of `dragDevices` by default, so this does
    // nothing at all unless the behaviour is overridden.
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('desktop shows a scrollbar, so it looks scrollable', (
    tester,
  ) async {
    await pump(tester, size: const Size(1200, 800));

    // Touch platforms teach you a row scrolls by letting you overscroll it.
    // A desktop has to be told.
    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('a phone gets no scrollbar', (tester) async {
    await pump(tester, size: const Size(400, 800));

    // It would sit under your thumb and say nothing swiping has not already.
    expect(find.byType(Scrollbar), findsNothing);
  });
}
