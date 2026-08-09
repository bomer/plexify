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

    test('keeps reporting while it keeps failing, at a widening gap', () async {
      final health = ConnectionHealth(failureThreshold: 2);
      final lost = <void>[];
      health.lost.listen(lost.add);

      for (var i = 0; i < 10; i++) {
        health.recordUnreachable();
      }
      await pumpEventQueue();

      // **Once per streak was a dead end**, and it is the bug behind "walking
      // out of wifi range never recovered". `ConnectionMonitor` deliberately
      // stops calling `reset()` when a re-resolve lands on the same address, so
      // with a one-shot emitter the streak survived and the latch survived with
      // it: nothing was ever reported again and nothing tried a second time.
      //
      // Not every failure either. At 2, 4, 8, 16 a device that is genuinely
      // offline is not re-racing LAN, remote and relay on every poll for as
      // long as it stays that way.
      expect(lost, hasLength(3));

      for (var i = 0; i < 6; i++) {
        health.recordUnreachable();
      }
      await pumpEventQueue();
      expect(lost, hasLength(4), reason: 'the eighth doubling, at 16');
    });

    test('the gap stops widening rather than drifting towards never', () async {
      final health = ConnectionHealth(failureThreshold: 1);
      final lost = <void>[];
      health.lost.listen(lost.add);

      for (var i = 0; i < 200; i++) {
        health.recordUnreachable();
      }
      await pumpEventQueue();

      // Capped, so a phone left offline overnight still notices within a poll
      // or two of the network returning rather than hours later.
      expect(lost.length, greaterThan(5));
    });

    test('reaching the server re-arms the immediate report', () async {
      final health = ConnectionHealth(failureThreshold: 2);
      final lost = <void>[];
      health.lost.listen(lost.add);

      health.recordUnreachable();
      health.recordUnreachable();
      health.recordUnreachable();
      health.recordUnreachable();
      await pumpEventQueue();
      expect(lost, hasLength(2), reason: 'reported at 2 and 4');

      health.recordReachable();
      health.recordUnreachable();
      health.recordUnreachable();
      await pumpEventQueue();

      // Back to the short interval. A connection that worked a moment ago and
      // has just gone should be retried promptly, not on whatever schedule the
      // last outage had backed off to.
      expect(lost, hasLength(3));
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

    test('a request that hangs counts as unreachable', () async {
      final health = ConnectionHealth();
      final client = HealthReportingClient(
        MockClient((_) => Completer<http.Response>().future),
        health,
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        client.get(Uri.parse('http://server/library/sections')),
        throwsA(anything),
      );

      // **The difference between walking out of range and switching wifi off.**
      // A network you are leaving does not refuse connections, it accepts them
      // and then says nothing, and `package:http` waits indefinitely. Without a
      // bound the failure count that drives recovery barely moved, so the app
      // looked like it had given up — while dropping the wifi outright failed
      // fast and always worked.
      expect(health.consecutiveFailures, 1);
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
      Future<bool> Function()? reconnect,
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
              // The default fake moves to a new address, which is the ordinary
              // case. Tests that care about a re-resolve landing back on the
              // same one say so explicitly.
              return true;
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
          return true;
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
      expect(t.monitor.lastChangedAddress, isTrue);
    });

    test('a re-resolve that lands on the same address is not a success', () async {
      // Discovery is deliberately sticky: with nothing reachable it keeps the
      // last address that worked, so the future completes just as happily as a
      // real move. Resetting there throws away the only evidence that the
      // connection is still dead, and the cooldown then holds off the next
      // attempt.
      //
      // That is a wifi to cellular handover exactly: the re-resolve fires while
      // the OS still reports the old transport, finds nothing, keeps the dead
      // LAN address, and playback is left with nothing that can notice.
      final t = build(reconnect: () async => false);

      t.health.recordUnreachable();
      t.health.recordUnreachable();
      await pumpEventQueue();

      expect(t.monitor.attempts, 1);
      expect(t.monitor.lastChangedAddress, isFalse);
      expect(
        t.health.consecutiveFailures,
        2,
        reason: 'the streak must survive, or nothing triggers the next attempt',
      );
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

    group('never connected at all', () {
      /// A monitor whose "do we have a server?" answer the test controls.
      ({ConnectionMonitor monitor, List<int> reconnects}) buildDisconnected({
        required bool Function() needsConnection,
        // Long enough that the timer never fires on its own unless a test asks
        // for a short one. Counting attempts is meaningless if a background
        // timer is adding to the total mid-assertion.
        Duration retry = const Duration(seconds: 30),
      }) {
        final reconnects = <int>[];
        final monitor = ConnectionMonitor(
          health: ConnectionHealth(failureThreshold: 2),
          needsConnection: needsConnection,
          retryWhenDisconnected: retry,
          maxRetryDelay: const Duration(seconds: 60),
          cooldown: Duration.zero,
          reconnect: () async {
            reconnects.add(reconnects.length);
            return false;
          },
        );
        monitor.start();
        addTearDown(monitor.stop);
        return (monitor: monitor, reconnects: reconnects);
      }

      test('retries when a launch never resolved a server', () async {
        final t = buildDisconnected(needsConnection: () => true);

        await t.monitor.retryIfDisconnected();
        await t.monitor.retryIfDisconnected();

        // **The dead end this closes.** Both other triggers need something to
        // be happening: no server means no client, no client means no
        // requests, and no requests means nothing can ever fail. A cold start
        // that missed — the network still settling a second after wifi went
        // off — sat disconnected until the OS volunteered an event or the app
        // was killed and reopened.
        expect(t.reconnects, hasLength(2));
        expect(t.monitor.lastReason, ReconnectReason.neverConnected);
      });

      test('does nothing once something has answered', () async {
        final t = buildDisconnected(needsConnection: () => false);

        await t.monitor.retryIfDisconnected();
        await t.monitor.retryIfDisconnected();

        // Connected, or signed out. Either way there is nothing to resolve, and
        // re-racing connections that are working would tear down a client
        // mid-request for no reason.
        expect(t.reconnects, isEmpty);
      });

      test('keeps trying on its own until something answers', () async {
        var connected = false;
        final t = buildDisconnected(
          needsConnection: () => !connected,
          retry: const Duration(milliseconds: 5),
        );

        await Future<void>.delayed(const Duration(milliseconds: 60));
        final whileOffline = t.reconnects.length;
        expect(whileOffline, greaterThan(1), reason: 'it re-armed itself');

        connected = true;
        await Future<void>.delayed(const Duration(milliseconds: 60));

        // And stops. A loop that kept re-racing after something answered would
        // tear down a working client mid-request, forever.
        expect(t.reconnects, hasLength(whileOffline));
      });

      test('arms nothing at all when there is nothing to connect', () async {
        final t = buildDisconnected(
          needsConnection: () => false,
          retry: const Duration(milliseconds: 5),
        );

        await Future<void>.delayed(const Duration(milliseconds: 40));

        // A standing heartbeat on the login screen keeps a phone awake for a
        // question with no answer. It also leaked into every widget test that
        // built the shell, which is how it was noticed.
        expect(t.reconnects, isEmpty);
      });

      test('stops retrying once stopped', () async {
        final t = buildDisconnected(
          needsConnection: () => true,
          retry: const Duration(milliseconds: 5),
        );
        await t.monitor.stop();

        await Future<void>.delayed(const Duration(milliseconds: 40));

        // A timer that outlives the monitor would keep invalidating providers
        // after sign-out, which is the one moment the graph is being torn down.
        expect(t.reconnects, isEmpty);
      });
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
