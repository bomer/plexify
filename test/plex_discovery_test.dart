import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_models.dart';
import 'package:plexify/core/plex/plex_server.dart';

/// Connection selection is the difference between the app feeling instant at
/// home and feeling broken. A server advertises several routes and they are not
/// interchangeable — a relay connection is bandwidth-limited by Plex and cannot
/// carry a lossless stream, so picking one when the LAN was available would
/// quietly degrade every playback decision downstream.
void main() {
  const localUri = 'https://192-168-1-10.abc.plex.direct:32400';
  const remoteUri = 'https://82-1-2-3.abc.plex.direct:32400';
  const relayUri = 'https://relay.plex.direct:443';

  PlexResource resourceWith(List<Map<String, dynamic>> connections) {
    return PlexResource.fromJson({
      'name': 'Tower',
      'clientIdentifier': 'abc123',
      'provides': 'server',
      'owned': true,
      'accessToken': 'servertoken',
      'connections': connections,
    });
  }

  final allThree = [
    {'uri': localUri, 'local': true, 'relay': false},
    {'uri': remoteUri, 'local': false, 'relay': false},
    {'uri': relayUri, 'local': false, 'relay': true},
  ];

  /// Normalises a URL to host:port for comparison.
  ///
  /// Necessary because `Uri` drops the port when it matches the scheme default,
  /// so the relay's `:443` disappears from `request.url.authority` and a naive
  /// string comparison silently never matches.
  String hostKey(String url) {
    final uri = Uri.parse(url);
    return '${uri.host}:${uri.port}';
  }

  /// Builds a discovery whose probes succeed only for [reachable].
  PlexDiscovery discoveryReaching(
    Set<String> reachable, {
    List<String>? probeLog,
  }) {
    final reachableKeys = reachable.map(hostKey).toSet();
    return PlexDiscovery(
      identity: PlexIdentity.forTesting(),
      httpClient: MockClient((request) async {
        final key = '${request.url.host}:${request.url.port}';
        probeLog?.add(key);
        return reachableKeys.contains(key)
            ? http.Response('{}', 200)
            : http.Response('', 500);
      }),
    );
  }

  group('connect', () {
    test('prefers the LAN connection when it is reachable', () async {
      final discovery = discoveryReaching({localUri, remoteUri, relayUri});

      final server = await discovery.connect(resourceWith(allThree));

      expect(server, isNotNull);
      expect(server!.baseUrl, localUri);
      expect(server.isLocal, isTrue);
      expect(server.isRelay, isFalse);
    });

    test('never probes remote or relay while the LAN answers', () async {
      final log = <String>[];
      final discovery = discoveryReaching({
        localUri,
        remoteUri,
        relayUri,
      }, probeLog: log);

      await discovery.connect(resourceWith(allThree));

      // Waves are sequential, so a working LAN short-circuits the rest.
      expect(log, contains(hostKey(localUri)));
      expect(log, isNot(contains(hostKey(remoteUri))));
      expect(log, isNot(contains(hostKey(relayUri))));
    });

    test('falls back to remote when the LAN is unreachable', () async {
      final discovery = discoveryReaching({remoteUri, relayUri});

      final server = await discovery.connect(resourceWith(allThree));

      expect(server!.baseUrl, remoteUri);
      expect(server.isLocal, isFalse);
      expect(server.isRelay, isFalse);
      // Direct remote is still good enough to attempt direct play.
      expect(server.preferTranscode, isFalse);
    });

    test('uses relay only as a last resort, and flags it', () async {
      final discovery = discoveryReaching({relayUri});

      final server = await discovery.connect(resourceWith(allThree));

      expect(server!.baseUrl, relayUri);
      expect(server.isRelay, isTrue);
      // Relay is bandwidth-limited, so the quality policy must transcode.
      expect(server.preferTranscode, isTrue);
    });

    test('returns null when nothing answers', () async {
      final discovery = discoveryReaching({});

      expect(await discovery.connect(resourceWith(allThree)), isNull);
    });

    test('prefers the per-server token over the account token', () async {
      final discovery = discoveryReaching({localUri});

      final server = await discovery.connect(
        resourceWith(allThree),
        accountToken: 'accounttoken',
      );

      expect(server!.token, 'servertoken');
    });

    test('falls back to the account token when the server has none', () async {
      final discovery = discoveryReaching({localUri});
      final resource = PlexResource.fromJson({
        'name': 'Tower',
        'clientIdentifier': 'abc',
        'provides': 'server',
        'connections': allThree,
      });

      final server = await discovery.connect(
        resource,
        accountToken: 'accounttoken',
      );

      expect(server!.token, 'accounttoken');
    });

    test('strips a trailing slash so paths concatenate cleanly', () async {
      final discovery = discoveryReaching({localUri});
      final resource = resourceWith([
        {'uri': '$localUri/', 'local': true, 'relay': false},
      ]);

      final server = await discovery.connect(resource);

      expect(server!.baseUrl, localUri);
    });
  });

  group('listServers', () {
    test('excludes resources that are not servers', () async {
      final discovery = PlexDiscovery(
        identity: PlexIdentity.forTesting(),
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode([
              {
                'name': 'Tower',
                'clientIdentifier': 'a',
                'provides': 'server',
                'connections': <dynamic>[],
              },
              {
                'name': 'Phone',
                'clientIdentifier': 'b',
                'provides': 'player,controller',
                'connections': <dynamic>[],
              },
            ]),
            200,
          );
        }),
      );

      final servers = await discovery.listServers('token');

      expect(servers, hasLength(1));
      expect(servers.single.name, 'Tower');
    });

    test('reports a useful error when plex.tv rejects the token', () async {
      final discovery = PlexDiscovery(
        identity: PlexIdentity.forTesting(),
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      expect(
        () => discovery.listServers('bad'),
        throwsA(isA<PlexDiscoveryException>()),
      );
    });
  });
}
