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
  ConnectionHealth({this.failureThreshold = 3})
    : _nextReportAt = failureThreshold;

  /// Consecutive transport failures before the connection is called lost.
  ///
  /// More than one, because a single failure is usually nothing — a server
  /// briefly asleep, a request racing a suspend. Few enough that a real change
  /// of network is noticed within one poll cycle rather than several.
  final int failureThreshold;

  /// How far the reporting interval may double before it stops growing.
  ///
  /// Sixteen threshold-fulls of failures — around fifty consecutive failed
  /// requests at the default — after which it keeps reporting at that spacing
  /// rather than drifting towards never. A phone left offline overnight should
  /// still notice within a poll or two of the network coming back, without
  /// having re-raced connections all night.
  static const _maxBackoffFactor = 16;

  final _lost = StreamController<void>.broadcast();

  int _consecutiveFailures = 0;

  /// The failure count at which the next report is due.
  ///
  /// **This is the whole of the retry story, and it used to be a one-shot.**
  /// The emitter fired once per streak and re-armed only on `reset()`, which
  /// [ConnectionMonitor] deliberately stopped calling when a re-resolve landed
  /// back on the same address — the right fix for one bug and the cause of
  /// another. With the streak preserved *and* the latch preserved, a connection
  /// that failed to recover on the first attempt was never reported again, so
  /// nothing ever tried a second time. Recovery depended entirely on the OS
  /// volunteering a connectivity event.
  ///
  /// That is exactly why turning wifi off recovered and walking out of range
  /// did not: switching it off fires an OS event, drifting out of range often
  /// fires nothing at all — Android keeps the interface associated long after
  /// the route has gone.
  int _nextReportAt;

  /// Fires when requests have been failing for long enough to act on, and again
  /// at a widening interval for as long as they keep failing.
  Stream<void> get lost => _lost.stream;

  int get consecutiveFailures => _consecutiveFailures;

  /// The server answered — whatever it said.
  void recordReachable() {
    _consecutiveFailures = 0;
    _nextReportAt = failureThreshold;
  }

  void recordUnreachable() {
    _consecutiveFailures++;
    if (_consecutiveFailures < _nextReportAt) return;

    _lost.add(null);
    // Doubling rather than repeating every [failureThreshold], because the two
    // situations this has to serve are opposite. A connection that has just
    // gone should be retried promptly; a device that is genuinely offline for
    // an hour should not re-race LAN, remote and relay every thirty seconds for
    // the whole hour. Backing off does both without a timer or a second clock
    // to keep in step.
    final next = _nextReportAt * 2;
    final ceiling = failureThreshold * _maxBackoffFactor;
    _nextReportAt = next > ceiling ? ceiling : next;
  }

  /// Forgets the current streak.
  ///
  /// Called after a reconnect so that failures belonging to the old, dead
  /// address are not counted against the new one — including the ones caused by
  /// tearing the old client down mid-request.
  void reset() {
    _consecutiveFailures = 0;
    _nextReportAt = failureThreshold;
  }

  void dispose() => _lost.close();
}

/// An [http.Client] that reports whether requests are reaching anything.
///
/// Wrapping the client rather than instrumenting call sites means every request
/// is covered, including ones added later — `PlexClient` alone has four, and
/// the one most likely to notice a dead connection first is whichever happens
/// to run at the moment the network changes.
class HealthReportingClient extends http.BaseClient {
  HealthReportingClient(
    this._inner,
    this._health, {
    this.timeout = const Duration(seconds: 6),
  });

  final http.Client _inner;
  final ConnectionHealth _health;

  /// How long a request may take to produce headers before it counts as having
  /// reached nothing.
  ///
  /// **Without this, a connection that degrades rather than drops is barely
  /// noticed.** `package:http` has no default timeout, and a wifi network you
  /// are walking out of does not refuse connections — it accepts them and then
  /// says nothing. Each poll would hang for whatever the OS eventually decides,
  /// often more than a minute, so the failure count that drives recovery
  /// crawled and the app appeared to give up. Dropping the wifi outright fails
  /// fast and always looked fine, which is precisely why the two behaved so
  /// differently.
  ///
  /// **Six seconds, and it is a backstop rather than the plan.** Every call
  /// through this client returns a small JSON body, which any working route
  /// answers in well under a second — a relay adds latency, not seconds. The
  /// number only decides how long a *dead* connection takes to look dead, so
  /// erring short costs a spurious re-resolve at worst and erring long costs
  /// the recovery itself.
  ///
  /// It should rarely be what recovers anything. A transport change is reported
  /// by the OS in milliseconds and [ConnectionMonitor] acts on it directly;
  /// this is for the case where nothing announces itself, which is a network
  /// that fades rather than one that is switched off.
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request).timeout(timeout);
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
