import 'package:flutter/material.dart';

import '../features/library/album_list_screen.dart';
import '../features/player/mini_player.dart';

/// The persistent frame around all browsing.
///
/// The important structural detail: page content is pushed into a **nested**
/// [Navigator] that lives *inside* this scaffold, while the mini player sits in
/// the scaffold's bottom slot, outside it.
///
/// Previously screens were pushed onto the root navigator, which stacks routes
/// above the entire widget tree — so opening an album covered the mini player
/// and left no way to pause without navigating back. Anything that should
/// persist across navigation has to live outside the Navigator that navigation
/// happens in.
///
/// This is also what the Now Playing overlay will build on: it needs to slide
/// over the current screen *without unmounting it*, so dismissing returns you
/// exactly where you were mid-browse.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // A nested Navigator does not receive system back gestures on its own —
    // without this, Android's back button would exit the app instead of popping
    // the album screen.
    return NavigatorPopHandler(
      onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
      child: Scaffold(
        body: Navigator(
          key: _navigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const AlbumListScreen(),
          ),
        ),
        bottomNavigationBar: const MiniPlayer(),
      ),
    );
  }
}
