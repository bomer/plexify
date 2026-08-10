import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/app_window.dart';
import '../core/providers.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/mini_player.dart';
import '../features/player/now_playing_screen.dart';
import '../features/player/playback_controller.dart';
import '../features/radio/autoplay.dart';
import '../features/player/player_providers.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import 'layout.dart';
import 'shell_destination.dart';
import 'sidebar.dart';
import 'typing.dart';

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
      onInactive: () {
        ref.read(syncSchedulerProvider)?.pause();
        // Android routinely kills the process without ever calling onDetach,
        // so leaving the screen is the last moment guaranteed to happen.
        unawaited(
          ref.read(playbackControllerProvider)?.save() ?? Future.value(),
        );
      },
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
    // Written before the goodbye, not after: the goodbye talks to a server
    // that may have stopped answering and is capped at two seconds, and
    // losing the resume position to a slow network would be the wrong thing
    // to sacrifice. The periodic save only runs every ten seconds, so without
    // this, quitting three seconds into a track resumes from the start of it.
    try {
      await ref.read(playbackControllerProvider)?.save();
    } on Object {
      // Nothing useful to do on the way out.
    }

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

  /// Handles a tap on a destination, whether or not it is the current one.
  ///
  /// **Tapping the destination you are already on pops that tab back to its
  /// root**, which is the missing half of this and the reason "Home does not
  /// take me home" was a real complaint. Each tab keeps its own navigator, so
  /// opening an album from a Home shelf pushes it onto Home's stack — and then
  /// pressing Home did nothing at all, because the destination had not changed.
  /// Every tabbed app sets this expectation; without it the only way back is
  /// the app bar's arrow.
  ///
  /// Switching to a *different* destination deliberately leaves its stack
  /// alone. Coming back to a half-read album page is the point of per-tab
  /// navigators, and resetting on the way in would throw that away.
  void _selectDestination(ShellDestination destination) {
    if (destination == ref.read(shellDestinationProvider)) {
      final navigator = _navigatorKeys[destination]?.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
      return;
    }
    ref.read(shellDestinationProvider.notifier).state = destination;
  }

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
    // Same reasoning, and it resolves to null unless qBittorrent is configured
    // *and* the catalog switch is on — so a phone with the feature off never
    // constructs it and never makes a request.
    ref.watch(downloadMonitorProvider);
    // The scheduler is kept alive here for a second reason: signing out has to
    // be able to *stop* it before wiping the cache, and reading a provider that
    // is not yet alive would construct one — which starts a sync at the exact
    // moment we are trying to end them.
    ref.watch(syncSchedulerProvider);
    // Without this the queue keeps pointing at the address it was built
    // against, so walking out of the house breaks not just the track playing
    // but every one after it.
    ref.watch(playbackRecoveryProvider);
    // Installs the refill hook on the handler. Without it the queue simply
    // ends, which is the behaviour the setting turns off.
    ref.watch(autoplayProvider);

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

    return Listener(
      onPointerDown: _onPointerDown,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: _shell(destination, expanded, content),
      ),
    );
  }

  /// The mouse's back button, which every browser and file manager binds to
  /// exactly this.
  ///
  /// Routed through the same [_handleBack] as the Android back gesture and the
  /// app bar's arrow, so there is one definition of what "back" means: collapse
  /// Now Playing first, then pop the tab's own stack, then fall back to Home.
  /// The last step minimises on Android and does nothing on the desktop, which
  /// is the right answer for a mouse button — nobody expects button four to
  /// hide the window.
  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kBackMouseButton != 0) unawaited(_handleBack());
  }

  /// Space toggles playback, which is the one control worth reaching for
  /// without looking.
  ///
  /// **Deliberately not `CallbackShortcuts`, and that is the whole of the
  /// fix.** That widget consumes any key matching a binding before deciding
  /// what to do with it, so space was swallowed here and never reached the
  /// search field — you could not type a space in a search box. Returning early
  /// from the callback could not have helped: by then the key was already
  /// marked handled, and a handled key is never forwarded to the text input
  /// system at all.
  ///
  /// Reporting [KeyEventResult.ignored] is what lets it through. The engine
  /// only turns a key into a character once the framework says nobody wanted
  /// it.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    if (isTypingSomewhere()) return KeyEventResult.ignored;
    final handler = ref.read(audioHandlerProvider);
    // Nothing loaded: leave the key alone rather than claiming it to do
    // nothing, so a space still reaches whatever else might want it.
    if (handler.mediaItem.value == null) return KeyEventResult.ignored;

    unawaited(
      handler.playbackState.value.playing ? handler.pause() : handler.play(),
    );
    return KeyEventResult.handled;
  }

  Widget _shell(ShellDestination destination, bool expanded, Widget content) {
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
                            onSelectDestination: _selectDestination,
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
                    MiniPlayer(aboveNavigationBar: !wide),
                    // The sidebar carries navigation on wide layouts, so the
                    // bottom bar would be redundant there.
                    if (!wide)
                      NavigationBar(
                        selectedIndex: destination.index,
                        onDestinationSelected: (index) =>
                            _selectDestination(ShellDestination.values[index]),
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
