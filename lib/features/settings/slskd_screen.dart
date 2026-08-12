import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings/app_settings.dart';
import '../../core/slskd/slskd_models.dart';

/// Where slskd is, and the key that gets in.
///
/// A screen of its own for the same reasons the qBittorrent one is: a secret
/// field in a scrolling list of dropdowns is awkward to lay out and worse to
/// use, and this is somewhere a Save button belongs, since a half-typed address
/// should not be written to disk on every keystroke.
///
/// **The address and the key go to different places.** The address is a
/// preference and lands in `shared_preferences`; the API key goes to the
/// platform keystore alongside the Plex token. `shared_preferences` is a
/// plaintext file on both platforms.
///
/// The prose at the bottom is doing real work and is not filler. Two of the
/// three things that stop this working are invisible from inside the app: where
/// slskd puts finished downloads, and whether it shares anything.
class SlskdScreen extends ConsumerStatefulWidget {
  const SlskdScreen({super.key});

  @override
  ConsumerState<SlskdScreen> createState() => _SlskdScreenState();
}

class _SlskdScreenState extends ConsumerState<SlskdScreen> {
  final _url = TextEditingController();
  final _apiKey = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _result;
  bool _resultIsError = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _url.text = ref.read(settingsProvider).slskdUrl ?? '';
    unawaitedLoad();
  }

  /// Fills in the saved key.
  ///
  /// Put back into the field rather than shown as a row of asterisks with
  /// nothing behind it, so that changing only the address does not silently
  /// blank the key. That is the sort of thing discovered two days later when a
  /// download fails.
  Future<void> unawaitedLoad() async {
    final saved = await ref.read(slskdCredentialsProvider).read();
    if (!mounted) return;
    setState(() {
      _apiKey.text = saved ?? '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save({bool thenTest = false}) async {
    setState(() {
      _busy = true;
      _result = null;
    });

    ref.read(settingsProvider.notifier).setSlskdUrl(_url.text);
    if (_apiKey.text.trim().isEmpty) {
      await ref.read(slskdCredentialsProvider).clear();
    } else {
      await ref.read(slskdCredentialsProvider).save(_apiKey.text.trim());
    }

    // Rebuilt rather than mutated: the client holds the key it was built with.
    ref.invalidate(slskdClientProvider);

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
      final client = await ref.read(slskdClientProvider.future);
      if (client == null) {
        message = 'Fill in the address and API key first.';
      } else {
        final version = await client.version();
        // Asked separately, and this is the point of the test button. slskd
        // answers every request perfectly while logged out of Soulseek, so a
        // server that can find nothing at all looks identical to a healthy one
        // until the first search comes back empty.
        final connected = await client.isConnectedToSoulseek();
        failed = !connected;
        message = connected
            ? 'Connected to slskd $version, and it is logged in to Soulseek.'
            : 'Reached slskd $version, but it is not logged in to Soulseek, '
                  'so it can search nothing. Check its own web interface.';
      }
    } on SlskdException catch (e) {
      message = e.message;
    } on Object catch (e) {
      message = 'Could not reach slskd: $e';
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
      appBar: AppBar(title: const Text('Soulseek')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'slskd address',
              hintText: 'https://nas.local:5031',
              helperText:
                  'Scheme, host and port. slskd serves HTTP on 5030 and '
                  'HTTPS on 5031 by default.',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKey,
            obscureText: _obscure,
            autocorrect: false,
            enabled: _loaded,
            decoration: InputDecoration(
              labelText: 'API key',
              helperText:
                  'From web.authentication.api_keys in slskd.yml. Generate '
                  'one with: openssl rand -base64 48',
              helperMaxLines: 3,
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
          Text(
            'Two things Plexify cannot do for you',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            // Both of these are invisible from in here and both present as
            // "downloads work but nothing ever appears in Plex" or "nothing is
            // ever available", which are miserable things to debug from the
            // wrong end.
            'slskd has one downloads folder and no per-download category, so '
            'the trick that routes qBittorrent downloads to Plex does not '
            'exist here. Point its downloads directory at the folder Plex '
            'watches, or use its own script hook to move finished folders '
            'there. Nothing in this app can check that, and until it is done '
            'the downloads will simply land somewhere Plex never looks.\n\n'
            'Soulseek expects you to share. Many people configure their '
            'queues to refuse anyone sharing nothing, so if slskd has no '
            'shared folders your availability quietly collapses to worse than '
            'torrents, with no error anywhere to say why. Pointing it at your '
            'music library, read only, is the usual answer.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text('If it will not connect', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'A 401 means the key is wrong or missing. A 403 means the key is '
            'right and your address is not: keys can be restricted to a list '
            'of networks, and behind a reverse proxy slskd may see the '
            "proxy's address rather than this device's.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
