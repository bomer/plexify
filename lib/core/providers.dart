import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/playback_handler.dart';
import 'plex/plex_auth.dart';
import 'plex/plex_client.dart';
import 'plex/plex_identity.dart';
import 'plex/plex_models.dart';
import 'plex/plex_server.dart';

/// The application's provider graph.
///
/// Declared explicitly rather than generated, so the dependencies between these
/// are readable top to bottom without needing to understand build_runner.
///
/// Two providers ([plexIdentityProvider] and [audioHandlerProvider]) are only
/// available asynchronously at startup, so they throw here and are replaced with
/// real values via `overrides` in `main.dart`. Reading one before that override
/// is a programming error, and failing loudly is better than handing back a
/// half-initialised audio engine.

final plexIdentityProvider = Provider<PlexIdentity>(
  (ref) => throw StateError('plexIdentityProvider must be overridden in main()'),
);

final audioHandlerProvider = Provider<PlexifyAudioHandler>(
  (ref) => throw StateError('audioHandlerProvider must be overridden in main()'),
);

final plexAuthProvider = Provider<PlexAuth>(
  (ref) => PlexAuth(identity: ref.watch(plexIdentityProvider)),
);

final plexDiscoveryProvider = Provider<PlexDiscovery>((ref) {
  final discovery = PlexDiscovery(identity: ref.watch(plexIdentityProvider));
  ref.onDispose(discovery.close);
  return discovery;
});

/// The stored Plex account token, or null when signed out.
///
/// Seeded at startup from secure storage so a returning user skips the link
/// flow entirely.
final authTokenProvider = StateProvider<String?>((ref) => null);

/// Connects to the first reachable server on the account.
///
/// v1 assumes a single server; a picker comes later if that turns out to be
/// wrong. Returns null when nothing could be reached, which the UI surfaces as
/// a retry rather than an error — being off the LAN is normal, not exceptional.
final connectServerProvider = FutureProvider<PlexServer?>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) return null;

  final discovery = ref.watch(plexDiscoveryProvider);
  final servers = await discovery.listServers(token);

  for (final resource in servers) {
    final connected = await discovery.connect(resource, accountToken: token);
    if (connected != null) return connected;
  }
  return null;
});

/// The connected server, or null while connecting or if nothing was reachable.
final plexServerProvider = Provider<PlexServer?>(
  (ref) => ref.watch(connectServerProvider).valueOrNull,
);

/// Null until both a token and a reachable server exist.
///
/// Derived straight from [connectServerProvider] rather than mirrored into
/// mutable state. An earlier version published the server via a microtask,
/// which let the album list build one frame early with a null client and flash
/// "No albums found" before correcting itself.
final plexClientProvider = Provider<PlexClient?>((ref) {
  final server = ref.watch(plexServerProvider);
  if (server == null) return null;
  final client = PlexClient(
    server: server,
    identity: ref.watch(plexIdentityProvider),
  );
  ref.onDispose(client.close);
  return client;
});

/// The music library section on the connected server.
final musicSectionProvider = FutureProvider<PlexSection?>((ref) async {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;
  return client.musicSection();
});

/// Albums, newest first.
///
/// Phase 1 reads straight from Plex on every view. Phase 2 replaces this with a
/// drift-backed provider so browsing stops being network-bound — the widgets
/// consuming it shouldn't need to change.
final albumsProvider = FutureProvider<List<PlexAlbum>>((ref) async {
  final client = ref.watch(plexClientProvider);
  final section = await ref.watch(musicSectionProvider.future);
  if (client == null || section == null) return const [];
  return client.albums(section.key);
});

/// Tracks for one album, keyed by its ratingKey.
final tracksProvider = FutureProvider.family<List<PlexTrack>, String>((
  ref,
  albumRatingKey,
) async {
  final client = ref.watch(plexClientProvider);
  if (client == null) return const [];
  return client.tracks(albumRatingKey);
});
