import 'package:flutter/material.dart';

import '../core/platform/app_window.dart';
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
    // Back handling has two jobs, and the default gets both wrong for a music
    // player: a nested Navigator receives no system back gestures at all, and
    // back at the root route finishes the activity — tearing down the engine
    // and stopping playback mid-track.
    //
    // So: intercept everything. Pop the nested route if there is one, otherwise
    // minimise to the background and leave the music playing.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = _navigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else {
          await AppWindow.moveToBackground();
        }
      },
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
