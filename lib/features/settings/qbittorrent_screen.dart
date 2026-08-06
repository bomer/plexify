import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/qbit/qbit_client.dart';
import '../../core/qbit/qbit_models.dart';
import '../../core/settings/app_settings.dart';

/// Where the qBittorrent WebUI is, and how to sign in to it.
///
/// A screen of its own rather than rows on the Settings list, because a
/// password field in a scrolling list of dropdowns is awkward to use and
/// impossible to lay out well — and because this is the one place in the app
/// with a Save button, since a half-typed address should not be written to disk
/// on every keystroke.
///
/// **The address and the credentials go to different places.** The address is a
/// preference and lands in `shared_preferences` with the rest; the username and
/// password go to the platform keystore, alongside the Plex token. That split is
/// not decoration — `shared_preferences` is a plaintext file on both platforms.
class QbittorrentScreen extends ConsumerStatefulWidget {
  const QbittorrentScreen({super.key});

  @override
  ConsumerState<QbittorrentScreen> createState() => _QbittorrentScreenState();
}

class _QbittorrentScreenState extends ConsumerState<QbittorrentScreen> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _result;
  bool _resultIsError = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _url.text = ref.read(settingsProvider).qbitUrl ?? '';
    unawaitedLoad();
  }

  /// Fills in the saved sign-in.
  ///
  /// The password is put back into the field rather than shown as a row of
  /// asterisks with no value behind it. Otherwise changing only the address
  /// would silently blank the password, which is the sort of thing you discover
  /// two days later when a download fails.
  Future<void> unawaitedLoad() async {
    final saved = await ref.read(qbitCredentialsProvider).read();
    if (!mounted) return;
    setState(() {
      _username.text = saved.username ?? '';
      _password.text = saved.password ?? '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save({bool thenTest = false}) async {
    setState(() {
      _busy = true;
      _result = null;
    });

    ref.read(settingsProvider.notifier).setQbitUrl(_url.text);
    if (_username.text.trim().isEmpty) {
      await ref.read(qbitCredentialsProvider).clear();
    } else {
      await ref
          .read(qbitCredentialsProvider)
          .save(username: _username.text.trim(), password: _password.text);
    }

    // Rebuilt rather than mutated: the client holds a session cookie and a
    // latched lock-out flag, and both belong to the credentials it was built
    // with. Pressing Save is also how someone clears a lock-out after fixing a
    // wrong password.
    ref.invalidate(qbitClientProvider);

    if (!thenTest) {
      if (mounted) {
        setState(() {
          _busy = false;
          _result = 'Saved';
          _resultIsError = false;
        });
      }
      return;
    }

    String message;
    var failed = true;
    try {
      final client = await ref.read(qbitClientProvider.future);
      if (client == null) {
        message = 'Fill in the address, username and password first.';
      } else {
        final version = await client.version();
        final plugins = await client.hasSearchPlugins();
        failed = false;
        message = plugins
            ? 'Connected to qBittorrent $version, search plugins enabled.'
            : 'Connected to qBittorrent $version, but no search plugin is '
                  'enabled — searching will find nothing until you add one.';
        // Not treated as a failure, because the connection genuinely works and
        // the monitor will too. It is a warning about the one thing that would
        // otherwise look like "nobody is seeding anything, ever".
        if (!plugins) failed = true;
      }
    } on QbitException catch (e) {
      message = e.message;
    } on Object catch (e) {
      message = 'Could not reach qBittorrent: $e';
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = message;
      _resultIsError = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('qBittorrent')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'WebUI address',
              hintText: 'https://box.local:8080',
              helperText:
                  'Scheme, host and port. Prefer https — the sign-in sends '
                  'the password in the request body.',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _username,
            autocorrect: false,
            enabled: _loaded,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: _obscure,
            enabled: _loaded,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _save(thenTest: true),
                child: const Text('Save and test'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _busy ? null : () => _save(),
                child: const Text('Save'),
              ),
              if (_busy) ...[
                const SizedBox(width: 16),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(
              _result!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _resultIsError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 32),
          Text('If it will not connect', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            // Both of these cost an afternoon each if you do not know them, and
            // both present as the same symptom: a 403 against a server that
            // works perfectly in a browser.
            'A 403 usually means one of two things. Either the address here '
            'does not exactly match how qBittorrent sees itself — the port '
            'matters, and a trailing slash breaks it — or the address has been '
            'temporarily banned for repeated failed sign-ins. Plexify makes '
            'one attempt and then stops rather than making a ban worse; fix '
            'the details and press Save and test again.\n\n'
            'Downloads are filed under the category "${QbitClient.category}", '
            'which is what routes them to the folder Plex watches. Nothing '
            'here renames or retags anything.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
