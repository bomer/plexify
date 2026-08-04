import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'plex_identity.dart';
import 'plex_models.dart';

/// A server we have successfully reached, and the connection that worked.
class PlexServer {
  const PlexServer({
    required this.name,
    required this.baseUrl,
    required this.token,
    required this.isLocal,
    required this.isRelay,
  });

  final String name;

  /// Origin only, no trailing slash — e.g. `https://192-168-1-10.abc.plex.direct:32400`.
  final String baseUrl;

  /// The per-server token, which is not necessarily the account token.
  final String token;

  final bool isLocal;
  final bool isRelay;

  /// Relay connections are bandwidth-limited by Plex and unsuitable for
  /// direct-playing lossless files. The quality policy uses this to decide
  /// whether to transcode.
  bool get preferTranscode => isRelay;
}

/// Discovers Plex servers and works out the best way to reach each one.
///
/// A server typically advertises several connections — LAN, public, and a
/// plex.tv relay — and they are emphatically not equivalent. We probe them in
/// waves rather than all at once so that a fast LAN address always wins over a
/// remote one that happens to answer a few milliseconds sooner.
class PlexDiscovery {
  PlexDiscovery({required PlexIdentity identity, http.Client? httpClient})
    : _identity = identity,
      _http = httpClient ?? http.Client();

  final PlexIdentity _identity;
  final http.Client _http;

  static const _resourcesUrl =
      'https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1';

  /// Releases the underlying HTTP connections.
  void close() => _http.close();

  /// Lists servers on the account. Does not probe connectivity.
  Future<List<PlexResource>> listServers(String accountToken) async {
    final response = await _http.get(
      Uri.parse(_resourcesUrl),
      headers: _identity.headers(token: accountToken),
    );

    if (response.statusCode != 200) {
      throw PlexDiscoveryException(
        'Could not list your Plex servers (HTTP ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const PlexDiscoveryException(
        'Unexpected response listing Plex servers',
      );
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(PlexResource.fromJson)
        .where((r) => r.isServer)
        .toList();
  }

  /// Finds the best working connection to [resource].
  ///
  /// Probes in three waves — local, then remote, then relay — returning as soon
  /// as any connection in a wave answers. Within a wave the first responder
  /// wins, which is a reasonable proxy for lowest latency.
  ///
  /// Returns null if nothing answers.
  Future<PlexServer?> connect(
    PlexResource resource, {
    String? accountToken,
    Duration perWaveTimeout = const Duration(seconds: 5),
  }) async {
    final token = resource.accessToken ?? accountToken;
    if (token == null || token.isEmpty) return null;

    final local = resource.connections.where((c) => c.local && !c.relay);
    final remote = resource.connections.where((c) => !c.local && !c.relay);
    final relay = resource.connections.where((c) => c.relay);

    for (final wave in [local, remote, relay]) {
      if (wave.isEmpty) continue;
      final winner = await _raceWave(wave.toList(), token, perWaveTimeout);
      if (winner != null) {
        return PlexServer(
          name: resource.name,
          baseUrl: _trimTrailingSlash(winner.uri),
          token: token,
          isLocal: winner.local,
          isRelay: winner.relay,
        );
      }
    }

    return null;
  }

  /// Probes every connection in [wave] concurrently, completing with the first
  /// that responds. Failures are swallowed — one refused connection shouldn't
  /// abort the others.
  Future<PlexConnection?> _raceWave(
    List<PlexConnection> wave,
    String token,
    Duration timeout,
  ) async {
    final completer = Completer<PlexConnection?>();
    var outstanding = wave.length;

    for (final connection in wave) {
      unawaited(
        _probe(connection, token, timeout)
            .then((ok) {
              if (ok && !completer.isCompleted) {
                completer.complete(connection);
              }
            })
            .catchError((_) {
              // Unreachable connection; ignore and let the others race.
            })
            .whenComplete(() {
              outstanding--;
              if (outstanding == 0 && !completer.isCompleted) {
                completer.complete(null);
              }
            }),
      );
    }

    return completer.future.timeout(
      timeout + const Duration(seconds: 1),
      onTimeout: () => null,
    );
  }

  /// `/identity` is unauthenticated, tiny and always present — the cheapest
  /// way to ask "is there a Plex server at this address that I can reach?".
  Future<bool> _probe(
    PlexConnection connection,
    String token,
    Duration timeout,
  ) async {
    final uri = Uri.parse('${_trimTrailingSlash(connection.uri)}/identity');
    final response = await _http
        .get(uri, headers: _identity.headers(token: token))
        .timeout(timeout);
    return response.statusCode == 200;
  }

  static String _trimTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

class PlexDiscoveryException implements Exception {
  const PlexDiscoveryException(this.message);
  final String message;

  @override
  String toString() => message;
}
