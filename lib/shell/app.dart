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
  static ThemeData _theme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4C8DFF),
        brightness: brightness,
      ),
      useMaterial3: true,
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
