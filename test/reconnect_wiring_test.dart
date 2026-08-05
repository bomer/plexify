import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';
import 'package:plexify/core/providers.dart';

/// The unit tests cover *when* to reconnect. This covers what reconnecting
/// actually does to the provider graph — which is where the user-visible
/// behaviour lives, and where a correct monitor can still produce a bad app.
void main() {
  late _ScriptedDiscovery discovery;
  late ProviderContainer container;

  setUp(() {
    discovery = _ScriptedDiscovery([_lan, _remote]);
    container = ProviderContainer(
      overrides: [
        plexIdentityProvider.overrideWithValue(PlexIdentity.forTesting()),
        plexDiscoveryProvider.overrideWithValue(discovery),
        // The real one opens a platform channel.
        networkChangesProvider.overrideWithValue(const Stream<void>.empty()),
      ],
    );
    container.read(authTokenProvider.notifier).state = 'token';
  });

  // Not `tearDown(container.dispose)` — that resolves the tear-off at
  // registration time, before setUp has assigned it.
  tearDown(() => container.dispose());

  test('reconnecting picks the connection again', () async {
    await container.read(connectServerProvider.future);
    expect(container.read(plexServerProvider)?.baseUrl, _lan.baseUrl);

    await container.read(connectionMonitorProvider).reconnectNow();

    expect(container.read(plexServerProvider)?.baseUrl, _remote.baseUrl);
    expect(discovery.connects, 2);
  });

  test('the client is rebuilt against the new address', () async {
    await container.read(connectServerProvider.future);
    final before = container.read(plexClientProvider);

    await container.read(connectionMonitorProvider).reconnectNow();
    final after = container.read(plexClientProvider);

    expect(before, isNotNull);
    expect(after, isNot(same(before)));
    expect(after!.server.baseUrl, _remote.baseUrl);
  });

  test('the server does not go null while re-racing', () async {
    await container.read(connectServerProvider.future);

    final seen = <String?>[];
    container.listen(
      plexServerProvider,
      (_, next) => seen.add(next?.baseUrl),
      fireImmediately: true,
    );

    await container.read(connectionMonitorProvider).reconnectNow();

    // Every screen reads the client downstream of this, and Artwork falls back
    // to a grey placeholder when it is null. A null in the middle here would
    // flash the entire grid to placeholders on every network change — which is
    // exactly when the app is already least pleasant to use.
    expect(seen, isNot(contains(null)));
  });

  test('a reconnect that reaches nothing leaves the old server in place',
      () async {
    await container.read(connectServerProvider.future);
    discovery.failNext = true;

    await container.read(connectionMonitorProvider).reconnectNow();

    // Being unreachable is normal — off the LAN with the server asleep. And
    // dropping it is a trap: no server means no client, no client means no
    // requests, and no requests means ConnectionHealth can never see another
    // failure to retry on. Keeping the stale address keeps the poll running,
    // and its failures are what drive the next attempt.
    expect(container.read(plexServerProvider), isNotNull);
  });

  test('signing out does clear the server', () async {
    await container.read(connectServerProvider.future);
    expect(container.read(plexServerProvider), isNotNull);

    container.read(authTokenProvider.notifier).state = null;
    // The provider re-resolves asynchronously, and serves the previous value
    // until it lands — which is what stops the UI flickering on a reconnect.
    await container.read(connectServerProvider.future);

    // The stickiness above must not outlive the session it belongs to, or
    // signing out would leave the app still pointed at the old server.
    expect(container.read(plexServerProvider), isNull);
  });
}

final _lan = PlexServer(
  name: 'tower',
  baseUrl: 'http://192-168-1-10.plex.direct:32400',
  token: 'server-token',
  isLocal: true,
  isRelay: false,
  clientIdentifier: 'server-1',
);

final _remote = PlexServer(
  name: 'tower',
  baseUrl: 'https://public.plex.direct:32400',
  token: 'server-token',
  isLocal: false,
  isRelay: false,
  clientIdentifier: 'server-1',
);

/// Returns the scripted servers in order, so a second connect models the phone
/// having moved off the LAN between the two.
class _ScriptedDiscovery implements PlexDiscovery {
  _ScriptedDiscovery(this._servers);

  final List<PlexServer> _servers;
  int connects = 0;
  bool failNext = false;

  @override
  Future<List<PlexResource>> listServers(String accountToken) async => [
    const PlexResource(
      name: 'tower',
      clientIdentifier: 'server-1',
      provides: 'server',
      owned: true,
      accessToken: 'server-token',
      connections: [],
    ),
  ];

  @override
  Future<PlexServer?> connect(
    PlexResource resource, {
    String? accountToken,
    Duration perWaveTimeout = const Duration(seconds: 5),
  }) async {
    if (failNext) return null;
    final server = _servers[connects.clamp(0, _servers.length - 1)];
    connects++;
    return server;
  }

  @override
  void close() {}
}
