import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/settings/app_settings.dart';
import '../features/auth/login_screen.dart';
import 'app_shell.dart';

class PlexifyApp extends ConsumerWidget {
  const PlexifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Plexify',
      debugShowCheckedModeBanner: false,
      // Read synchronously, so the first frame is already in the chosen theme.
      themeMode: ref.watch(settingsProvider.select((s) => s.themeMode)),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const _Root(),
    );
  }

  /// Dark-first and restrained — content should carry the colour, not the
  /// chrome. The accent is deliberately not Spotify green.
  ///
  /// **The surface family is overridden to true neutral, and that is the whole
  /// point of this method.** Material 3 tints greys with the seed twice over,
  /// and neither is obvious from reading a colour scheme:
  ///
  /// - `ColorScheme.fromSeed` derives the surface roles from the seed's tonal
  ///   palette with a little chroma deliberately left in, so the "greys" are
  ///   already blue before anything is drawn.
  /// - `surfaceTint` — which defaults to `primary` — is then blended into every
  ///   surface in proportion to its elevation, so the app bar, cards and player
  ///   bar each get a further wash of it.
  ///
  /// Together they gave a window with a blue cast nobody chose, competing with
  /// the one thing on screen that is supposed to carry colour: the album art.
  /// Overriding the surfaces costs nine lines and is the single change that
  /// made the app stop looking like a default Flutter project.
  ///
  /// The values are also *spread out* rather than merely neutral. The generated
  /// ones sat within a few percent of each other, so the sidebar, the content
  /// and the transport bar read as one continuous sheet with no hierarchy at
  /// all. These are far enough apart to see.
  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4C8DFF),
      brightness: brightness,
    );

    final scheme = base.copyWith(
      surface: dark ? const Color(0xFF0E0E10) : const Color(0xFFFAFAFA),
      surfaceContainerLowest: dark
          ? const Color(0xFF09090B)
          : const Color(0xFFFFFFFF),
      surfaceContainerLow: dark
          ? const Color(0xFF131316)
          : const Color(0xFFF4F4F5),
      surfaceContainer: dark
          ? const Color(0xFF171719)
          : const Color(0xFFEFEFF1),
      surfaceContainerHigh: dark
          ? const Color(0xFF1D1D20)
          : const Color(0xFFE8E8EA),
      surfaceContainerHighest: dark
          ? const Color(0xFF242427)
          : const Color(0xFFE1E1E4),
      // Kept a touch cool rather than pure grey. Perfectly neutral secondary
      // text on a near-black background reads as slightly dirty, and this is
      // the most-used colour in the app by a distance.
      onSurfaceVariant: dark
          ? const Color(0xFFA1A1AA)
          : const Color(0xFF52525B),
      outlineVariant: dark ? const Color(0xFF2A2A2E) : const Color(0xFFD4D4D8),
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      // Elevation stops meaning "add primary". Without this every override
      // above is undone the moment a surface is raised, which is most of them.
      applyElevationOverlayColor: false,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
      dialogTheme: const DialogThemeData(surfaceTintColor: Colors.transparent),
      drawerTheme: const DrawerThemeData(surfaceTintColor: Colors.transparent),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        // Fixed rather than floating: a snackbar that floats sits over the
        // transport bar, which is the one thing that must never be covered.
        behavior: SnackBarBehavior.fixed,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      textTheme: _textTheme(brightness),
    );
  }

  /// Typography adjustments, all of them small and none of them a new font.
  ///
  /// Section headers were `titleMedium` at default tracking, which is the same
  /// visual weight as the album titles underneath them — so a row of covers had
  /// no heading so much as a caption floating above it. Slightly larger,
  /// heavier and tighter is enough to bind a header to its row.
  static TextTheme _textTheme(Brightness brightness) {
    final base = ThemeData(brightness: brightness).textTheme;
    return base.copyWith(
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
    );
  }
}

/// Decides what the user sees: sign-in, a connection attempt, or the library.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(authTokenProvider);
    if (token == null) return const LoginScreen();

    final connection = ref.watch(connectServerProvider);

    return connection.when(
      loading: () =>
          const _Status(message: 'Finding your Plex server…', busy: true),
      error: (error, _) => _Status(
        message: '$error',
        onRetry: () => ref.invalidate(connectServerProvider),
      ),
      data: (server) {
        if (server == null) {
          // Being unreachable is normal (off the LAN, server asleep), so this
          // is a retry prompt rather than an error state.
          return _Status(
            message:
                'No reachable Plex server found.\n'
                'Check that it is switched on and that you are on the '
                'same network.',
            onRetry: () => ref.invalidate(connectServerProvider),
          );
        }
        return const AppShell();
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.message, this.busy = false, this.onRetry});

  final String message;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
              ],
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
