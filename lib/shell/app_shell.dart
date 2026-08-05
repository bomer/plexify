import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/app_window.dart';
import '../core/providers.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/mini_player.dart';
import '../features/player/now_playing_screen.dart';
import '../features/player/player_providers.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import 'layout.dart';
import 'shell_destination.dart';
import 'sidebar.dart';

/// The persistent frame around all browsing.
///
/// Two structural rules, both learned the hard way:
///
/// * Page content lives in **nested** [Navigator]s inside this scaffold, while
///   the mini player sits in the bottom slot outside them. Pushing routes onto
///   the root navigator covered the mini player and left no way to pause.
/// * Now Playing is a sibling [Stack] layer, not a route, so the browsing
///   screen underneath is never unmounted.
///
/// Each destination gets its own navigator, kept alive in an [IndexedStack], so
/// switching tabs preserves both the navigation stack and the scroll position
/// of the one you left.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _navigatorKeys = {
    for (final destination in ShellDestination.values)
      destination: GlobalKey<NavigatorState>(),
  };

  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back to the foreground is the moment the notification socket is
    // most likely to be dead — the OS reclaims idle connections — and also the
    // moment stale content is most likely to be noticed.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(plexNotificationSocketProvider)?.reconnectNow();
        // The socket cannot deliver what happened while the app was closed, so
        // coming back also asks the cheap question directly.
        unawaited(ref.read(syncSchedulerProvider)?.resume() ?? Future.value());
      },
      // Polling stops the moment the app is no longer on screen. Playback keeps
      // the isolate alive for hours on Android, and there is nothing to gain
      // from checking for library changes nobody can see.
      onInactive: () => ref.read(syncSchedulerProvider)?.pause(),
      // Closing the window is the last chance to tell Plex the session ended.
      // Without it the dashboard shows Plexify still playing for minutes after
      // it has gone, and a relaunch appears to be a second copy.
      onExitRequested: _sayGoodbye,
      // Android's equivalent, and best-effort by nature: the process is often
      // killed outright, which is why the session slot is reused across
      // launches rather than relying on a clean exit.
      onDetach: () => unawaited(_flushSession()),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// How long the app will wait on the goodbye before closing anyway.
  ///
  /// Quitting must never hang on a server that has stopped answering, which is
  /// the exact situation where the request is slowest.
  static const _goodbyeTimeout = Duration(seconds: 2);

  Future<AppExitResponse> _sayGoodbye() async {
    await _flushSession();
    return AppExitResponse.exit;
  }

  Future<void> _flushSession() async {
    try {
      await ref
          .read(timelineReporterProvider)
          ?.reportStopped()
          .timeout(_goodbyeTimeout);
    } on Object {
      // Nothing useful to do on the way out.
    }
  }

  NavigatorState? get _activeNavigator =>
      _navigatorKeys[ref.read(shellDestinationProvider)]?.currentState;

  Future<void> _handleBack() async {
    // Collapse the player before anything else — it is the topmost thing on
    // screen, so it is what "back" should dismiss first.
    if (ref.read(nowPlayingExpandedProvider)) {
      ref.read(nowPlayingExpandedProvider.notifier).state = false;
      return;
    }

    final navigator = _activeNavigator;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }

    // At the root of a secondary tab, back returns to Home rather than leaving
    // the app — the same expectation every tabbed app sets.
    if (ref.read(shellDestinationProvider) != ShellDestination.home) {
      ref.read(shellDestinationProvider.notifier).state = ShellDestination.home;
      return;
    }

    // Finishing the activity would tear down the engine and stop playback, so
    // minimise instead and leave the music running.
    await AppWindow.moveToBackground();
  }

  Widget _rootFor(ShellDestination destination) => switch (destination) {
    ShellDestination.home => const HomeScreen(),
    ShellDestination.search => const SearchScreen(),
    ShellDestination.library => const LibraryScreen(),
    ShellDestination.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(shellDestinationProvider);
    final expanded = ref.watch(nowPlayingExpandedProvider);

    // Watched purely to keep them alive: neither has any UI, but without a
    // listener the provider is never constructed — the socket never opens, and
    // nothing notices when the server address stops working.
    ref.watch(liveSyncProvider);
    ref.watch(connectionMonitorProvider);
    ref.watch(timelineReporterProvider);

    final content = IndexedStack(
      index: destination.index,
      children: [
        for (final d in ShellDestination.values)
          Navigator(
            key: _navigatorKeys[d],
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => _rootFor(d),
            ),
          ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= compactLayoutBreakpoint;

              return Scaffold(
                body: wide
                    ? Row(
                        children: [
                          Sidebar(
                            onOpenPlaylist: (playlist) {
                              final navigator = _activeNavigator;
                              if (navigator != null) {
                                openPlaylist(navigator, playlist);
                              }
                            },
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                          Expanded(child: content),
                        ],
                      )
                    : content,
                bottomNavigationBar: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MiniPlayer(),
                    // The sidebar carries navigation on wide layouts, so the
                    // bottom bar would be redundant there.
                    if (!wide)
                      NavigationBar(
                        selectedIndex: destination.index,
                        onDestinationSelected: (index) =>
                            ref.read(shellDestinationProvider.notifier).state =
                                ShellDestination.values[index],
                        destinations: [
                          for (final d in ShellDestination.values)
                            NavigationDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: d.label,
                            ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),

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
