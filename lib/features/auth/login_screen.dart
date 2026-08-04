import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/plex/plex_auth.dart';
import '../../core/providers.dart';

/// Plex sign-in via the PIN link flow.
///
/// We deliberately never ask for a Plex password — the user approves this
/// device in their own browser, and we receive only a token. That also means
/// two-factor accounts work with no extra handling.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _code;
  String? _error;

  /// Set when the widget is disposed mid-poll, so the polling loop can bail out
  /// instead of resolving into a dead widget.
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
      _code = null;
    });

    final auth = ref.read(plexAuthProvider);

    try {
      final pin = await auth.createPin();
      if (!mounted) return;
      setState(() => _code = pin.code);

      final url = auth.authorizationUrl(pin);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const PlexAuthException(
          'Could not open your browser. Visit plex.tv/link and enter the code.',
        );
      }

      final token = await auth.waitForToken(pin, isCancelled: () => _cancelled);
      if (!mounted) return;

      // Publishing the token cascades through the provider graph: discovery
      // runs, a server is chosen, and the shell swaps to the library.
      ref.read(authTokenProvider.notifier).state = token;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
        _code = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.graphic_eq,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Plexify',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in with your Plex account',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                if (_code != null) ...[
                  Text(
                    'Approve this code in your browser',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _code!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      letterSpacing: 6,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for approval…',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ] else
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in with Plex'),
                    ),
                  ),

                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
