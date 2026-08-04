import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/app_window.dart';
import '../features/library/album_list_screen.dart';
import '../features/player/mini_player.dart';
import '../features/player/now_playing_screen.dart';
import '../features/player/player_providers.dart';

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
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final expanded = ref.watch(nowPlayingExpandedProvider);

    // Back handling has three jobs, and the default gets them all wrong for a
    // music player: a nested Navigator receives no system back gestures at all;
    // back at the root route finishes the activity, tearing down the engine and
    // stopping playback mid-track; and the Now Playing layer is not a route at
    // all, so nothing would dismiss it.
    //
    // So: intercept everything. Collapse the player if it is open, else pop the
    // nested route, else minimise and leave the music playing.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (ref.read(nowPlayingExpandedProvider)) {
          ref.read(nowPlayingExpandedProvider.notifier).state = false;
          return;
        }
        final navigator = _navigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else {
          await AppWindow.moveToBackground();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            body: Navigator(
              key: _navigatorKey,
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const AlbumListScreen(),
              ),
            ),
            bottomNavigationBar: const MiniPlayer(),
          ),

          // Now Playing is a sibling layer, not a pushed route. That is the
          // whole point: the browsing screen underneath is never unmounted, so
          // collapsing returns you to the same scroll position and state rather
          // than a rebuilt page.
          AnimatedSlide(
            offset: expanded ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
              ignoring: !expanded,
              child: const NowPlayingScreen(),
            ),
          ),
        ],
      ),
    );
  }
}
