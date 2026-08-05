import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/plex/connection_health.dart';
import 'package:plexify/core/plex/connection_monitor.dart';

/// The connection is chosen once, at startup, by racing LAN against remote
/// against relay. These are the rules for noticing that the winner has stopped
/// being reachable — which is what carrying a phone out of the house does.
void main() {
  group('ConnectionHealth', () {
    test('a run of failures reports the connection lost', () async {
      final health = ConnectionHealth(failureThreshold: 3);
      final lost = <void>[];
      health.lost.listen(lost.add);

      health.recordUnreachable();
      health.recordUnreachable();
      await pumpEventQueue();
      expect(lost, isEmpty, reason: 'below the threshold');

      health.recordUnreachable();
      await pumpEventQueue();
      expect(lost, hasLength(1));
    });

    test('one success wipes the streak', () async {
      final health = ConnectionHealth(failureThreshold: 3);
      final lost = <void>[];
      health.lost.listen(lost.add);

      health.recordUnreachable();
      health.recordUnreachable();
      health.recordReachable();
      health.recordUnreachable();
      health.recordUnreachable();
      await pumpEventQueue();

      // Two failures either side of a success are not three failures in a row.
      // Without this an intermittent connection would be declared dead.
      expect(lost, isEmpty);
    });

    test('reports once per streak, not once per failure', () async {
      final health = ConnectionHealth(failureThreshold: 2);
      final lost = <void>[];
      health.lost.listen(lost.add);

      for (var i = 0; i < 10; i++) {
        health.recordUnreachable();
      }
      await pumpEventQueue();

      // A genuinely offline device fails every poll forever. Emitting each time
      // would have the monitor re-racing connections that cannot answer.
      expect(lost, hasLength(1));
    });

    test('reset forgets the streak without reporting', () async {
      final health = ConnectionHealth(failureThreshold: 2);
      final lost = <void>[];
      health.lost.listen(lost.add);

      health.recordUnreachable();
      health.reset();
      health.recordUnreachable();
      await pumpEventQueue();

      expect(lost, isEmpty);
      expect(health.consecutiveFailures, 1);
    });
  });

  group('HealthReportingClient', () {
    test('an error response still counts as reaching the server', () async {
      final health = ConnectionHealth();
      final client = HealthReportingClient(
        MockClient((_) async => http.Response('nope', 404)),
        health,
      );

      health.recordUnreachable();
      await client.get(Uri.parse('http://server/library/sections'));

      // 404 means the server answered. Treating it as unreachable would have
      // the app re-racing connections over a missing item.
      expect(health.consecutiveFailures, 0);
    });

    test('a transport failure counts as unreachable', () async {
      final health = ConnectionHealth();
      final client = HealthReportingClient(
        MockClient((_) async => throw const SocketExceptionStub()),
        health,
      );

      await expectLater(
        client.get(Uri.parse('http://server/library/sections')),
        throwsA(isA<SocketExceptionStub>()),
      );

      expect(health.consecutiveFailures, 1);
    });

    test('the failure is still thrown to the caller', () async {
      // Observing must not swallow: callers decide what a failure means.
      final client = HealthReportingClient(
        MockClient((_) async => throw const SocketExceptionStub()),
        ConnectionHealth(),
      );

      await expectLater(
        client.get(Uri.parse('http://server/x')),
        throwsA(isA<SocketExceptionStub>()),
      );
    });
  });

  group('ConnectionMonitor', () {
    /// Builds a monitor with controllable time and triggers.
    ({
      ConnectionMonitor monitor,
      ConnectionHealth health,
      StreamController<void> network,
      List<int> reconnects,
      void Function(Duration) advance,
    })
    build({
      Future<void> Function()? reconnect,
      Duration cooldown = const Duration(seconds: 10),
    }) {
      final health = ConnectionHealth(failureThreshold: 2);
      final network = StreamController<void>.broadcast();
      final reconnects = <int>[];
      var clock = DateTime(2026, 8, 5, 12);

      final monitor = ConnectionMonitor(
        health: health,
        networkChanges: network.stream,
        cooldown: cooldown,
        now: () => clock,
        reconnect:
            reconnect ??
            () async {
              reconnects.add(reconnects.length);
            },
      );
      monitor.start();

      return (
        monitor: monitor,
        health: health,
        network: network,
        reconnects: reconnects,
        advance: (d) => clock = clock.add(d),
      );
    }

    test('reconnects when the connection is lost', () async {
      final t = build();

      t.health.recordUnreachable();
      t.health.recordUnreachable();
      await pumpEventQueue();

      expect(t.reconnects, hasLength(1));
      expect(t.monitor.lastReason, ReconnectReason.connectionLost);
    });

    test('reconnects when the network changes', () async {
      final t = build();

      t.network.add(null);
      await pumpEventQueue();

      expect(t.reconnects, hasLength(1));
      expect(t.monitor.lastReason, ReconnectReason.networkChanged);
    });

    test('a network change and a run of failures are one event', () async {
      final t = build();

      // Walking out of the house produces both, near-simultaneously. They are
      // two symptoms of one change, and must not race two reconnects.
      t.network.add(null);
      t.health.recordUnreachable();
      t.health.recordUnreachable();
      await pumpEventQueue();

      expect(t.reconnects, hasLength(1));
    });

    test('a second reconnect will not start while one is running', () async {
      // The test above passes on the cooldown alone — the clock does not move,
      // so the second trigger is refused either way. This one forces both
      // attempts past the cooldown, so only the in-flight guard can refuse it.
      var running = 0;
      var overlapped = false;
      final gate = Completer<void>();

      final t = build(
        reconnect: () async {
          running++;
          if (running > 1) overlapped = true;
          await gate.future;
          running--;
        },
      );

      final first = t.monitor.reconnectNow();
      final second = t.monitor.reconnectNow();
      gate.complete();
      await Future.wait([first, second]);

      expect(overlapped, isFalse);
      // Re-racing connections concurrently would let a slow LAN probe finish
      // after a fast relay one and overwrite the better choice with the worse.
      expect(t.monitor.attempts, 1);
    });

    test('the cooldown stops a reconnect feeding itself', () async {
      final t = build();

      t.network.add(null);
      await pumpEventQueue();

      // Tearing down the old client fails its in-flight requests, which looks
      // exactly like the connection dropping again.
      t.health.recordUnreachable();
      t.health.recordUnreachable();
      await pumpEventQueue();

      expect(t.reconnects, hasLength(1));
    });

    test('reconnects again once the cooldown has passed', () async {
      final t = build();

      t.network.add(null);
      await pumpEventQueue();

      t.advance(const Duration(seconds: 11));
      t.network.add(null);
      await pumpEventQueue();

      expect(t.reconnects, hasLength(2));
    });

    test('a manual reconnect ignores the cooldown', () async {
      final t = build();

      t.network.add(null);
      await pumpEventQueue();
      await t.monitor.reconnectNow();

      // Someone pressing the button has already decided to wait.
      expect(t.reconnects, hasLength(2));
      expect(t.monitor.lastReason, ReconnectReason.manual);
    });

    test('a successful reconnect clears the failure count', () async {
      final t = build();

      t.health.recordUnreachable();
      t.health.recordUnreachable();
      await pumpEventQueue();

      // Otherwise failures belonging to the address we just abandoned are
      // counted against its replacement, and the next single failure trips it.
      expect(t.health.consecutiveFailures, 0);
    });

    test('a failed reconnect does not throw out of the listener', () async {
      final t = build(reconnect: () async => throw StateError('nothing there'));

      t.network.add(null);
      await pumpEventQueue();

      // Being unreachable is normal — off the LAN, server asleep. This runs
      // from a stream listener with nobody to catch it.
      expect(t.monitor.isReconnecting, isFalse);
      expect(t.monitor.attempts, 1);
    });

    test('stop unsubscribes from both triggers', () async {
      final t = build();
      await t.monitor.stop();

      t.network.add(null);
      t.health.recordUnreachable();
      t.health.recordUnreachable();
      await pumpEventQueue();

      expect(t.reconnects, isEmpty);
    });
  });
}

/// Stands in for a real transport failure without importing `dart:io`, so the
/// test stays usable wherever the suite runs.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
