import 'dart:async';

import 'package:http/http.dart' as http;

/// Whether the server we picked at startup can still be reached.
///
/// A Plex server usually advertises several addresses — LAN, public, relay —
/// and discovery picks one at startup. That choice then never changes on its
/// own, so a phone that connects on the LAN and walks out of the house keeps
/// asking an address that no longer resolves. This is what notices.
///
/// Only the **transport** is judged here. A 404 or a 500 means the server
/// answered, which is exactly what we want to know; those count as reachable
/// even though the caller will treat them as errors.
class ConnectionHealth {
  ConnectionHealth({this.failureThreshold = 3});

  /// Consecutive transport failures before the connection is called lost.
  ///
  /// More than one, because a single failure is usually nothing — a server
  /// briefly asleep, a request racing a suspend. Few enough that a real change
  /// of network is noticed within one poll cycle rather than several.
  final int failureThreshold;

  final _lost = StreamController<void>.broadcast();

  int _consecutiveFailures = 0;

  /// Fires when [failureThreshold] requests in a row failed to reach anything.
  Stream<void> get lost => _lost.stream;

  int get consecutiveFailures => _consecutiveFailures;

  /// The server answered — whatever it said.
  void recordReachable() => _consecutiveFailures = 0;

  void recordUnreachable() {
    _consecutiveFailures++;
    // Deliberately `==` rather than `>=`: one event per streak. With `>=` a
    // genuinely offline device would emit on every failed poll forever, and
    // whatever listens would spend its life re-racing connections that cannot
    // possibly answer.
    if (_consecutiveFailures == failureThreshold) _lost.add(null);
  }

  /// Forgets the current streak.
  ///
  /// Called after a reconnect so that failures belonging to the old, dead
  /// address are not counted against the new one — including the ones caused by
  /// tearing the old client down mid-request.
  void reset() => _consecutiveFailures = 0;

  void dispose() => _lost.close();
}

/// An [http.Client] that reports whether requests are reaching anything.
///
/// Wrapping the client rather than instrumenting call sites means every request
/// is covered, including ones added later — `PlexClient` alone has four, and
/// the one most likely to notice a dead connection first is whichever happens
/// to run at the moment the network changes.
class HealthReportingClient extends http.BaseClient {
  HealthReportingClient(this._inner, this._health);

  final http.Client _inner;
  final ConnectionHealth _health;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
      _health.recordReachable();
      return response;
    } catch (_) {
      // No response at all: DNS failure, connection refused, timeout, or a
      // client closed underneath an in-flight request during a reconnect.
      _health.recordUnreachable();
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
