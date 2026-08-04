import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_identity.dart';
import 'package:plexify/core/plex/plex_notifications.dart';
import 'package:plexify/core/plex/plex_server.dart';

/// Frames arrive from a long-lived connection carrying several unrelated kinds
/// of notification, so parsing has to be both selective and total.
void main() {
  group('parsePlexNotifications', () {
    String timeline(String entries) =>
        '{"NotificationContainer":{"type":"timeline","TimelineEntry":[$entries]}}';

    test('a completed scan is an upsert', () {
      final changes = parsePlexNotifications(
        timeline(
          '{"identifier":"com.plexapp.plugins.library","itemID":"1234",'
          '"type":10,"state":5,"sectionID":"3"}',
        ),
      );

      expect(changes, [
        const PlexLibraryChange(
          kind: PlexChangeKind.upserted,
          ratingKey: '1234',
          metadataType: 10,
          sectionKey: '3',
        ),
      ]);
    });

    test('ignores items Plex is still scanning', () {
      // Fetching at state 2 stores half-written metadata — a track with no part
      // key — which then looks like a permanent cache bug rather than a
      // transient one.
      for (final state in [0, 1, 2, 3, 4]) {
        expect(
          parsePlexNotifications(timeline('{"itemID":"1","state":$state}')),
          isEmpty,
          reason: 'state $state should not be acted on',
        );
      }
    });

    test('recognises both forms of deletion', () {
      expect(
        parsePlexNotifications(
          timeline('{"itemID":"1","state":9}'),
        ).single.kind,
        PlexChangeKind.deleted,
      );
      expect(
        parsePlexNotifications(
          timeline('{"itemID":"1","state":5,"metadataState":"deleted"}'),
        ).single.kind,
        PlexChangeKind.deleted,
      );
    });

    test('skips notifications from other Plex plugins', () {
      expect(
        parsePlexNotifications(
          timeline(
            '{"identifier":"com.plexapp.plugins.dvr","itemID":"1",'
            '"state":5}',
          ),
        ),
        isEmpty,
      );
    });

    test('ignores notification types that are not library changes', () {
      expect(
        parsePlexNotifications(
          '{"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[{}]}}',
        ),
        isEmpty,
      );
      expect(
        parsePlexNotifications(
          '{"NotificationContainer":{"type":"progress","size":1}}',
        ),
        isEmpty,
      );
    });

    test('survives anything unparseable', () {
      // One bad frame must never take the connection down.
      for (final frame in ['', 'not json', '[]', '{}', '{"a":1}']) {
        expect(parsePlexNotifications(frame), isEmpty);
      }
    });

    test('accepts a payload sent without the container wrapper', () {
      expect(
        parsePlexNotifications(
          '{"type":"timeline","TimelineEntry":[{"itemID":"7","state":5}]}',
        ).single.ratingKey,
        '7',
      );
    });

    test('drops entries with no usable item id', () {
      expect(
        parsePlexNotifications(timeline('{"itemID":"0","state":5}')),
        isEmpty,
      );
      expect(parsePlexNotifications(timeline('{"state":5}')), isEmpty);
    });

    test('coerces the string types some servers send', () {
      final change = parsePlexNotifications(
        timeline('{"itemID":9,"state":"5","type":"9"}'),
      ).single;

      expect(change.ratingKey, '9');
      expect(change.metadataType, 9);
    });
  });

  group('PlexNotificationSocket', () {
    const server = PlexServer(
      name: 'Tower',
      baseUrl: 'https://tower.plex.direct:32400',
      token: 'tok',
      isLocal: true,
      isRelay: false,
    );

    late List<_FakeSocket> opened;
    late List<Uri> requested;

    PlexNotificationSocket build({
      Duration backoff = Duration.zero,
      bool failFirst = false,
    }) {
      opened = [];
      requested = [];
      return PlexNotificationSocket(
        server: server,
        identity: PlexIdentity.forTesting(),
        backoff: (_) => backoff,
        connector: (uri, headers) async {
          requested.add(uri);
          if (failFirst && requested.length == 1) {
            throw const SocketFailure();
          }
          final socket = _FakeSocket();
          opened.add(socket);
          return socket;
        },
      );
    }

    test('connects over wss with the token in the query', () async {
      final socket = build();
      socket.start();
      await pumpEventQueue();

      expect(requested.single.scheme, 'wss');
      expect(requested.single.host, 'tower.plex.direct');
      expect(requested.single.port, 32400);
      expect(requested.single.path, '/:/websockets/notifications');
      expect(requested.single.queryParameters['X-Plex-Token'], 'tok');

      await socket.stop();
    });

    test('publishes changes parsed from frames', () async {
      final socket = build();
      final received = <PlexLibraryChange>[];
      socket.changes.listen(received.add);
      socket.start();
      await pumpEventQueue();

      opened.single.send(
        '{"NotificationContainer":{"type":"timeline","TimelineEntry":'
        '[{"itemID":"42","state":5,"type":10}]}}',
      );
      await pumpEventQueue();

      expect(received.single.ratingKey, '42');
      await socket.stop();
    });

    test('reconnects when the connection drops', () async {
      final socket = build();
      socket.start();
      await pumpEventQueue();
      expect(opened, hasLength(1));

      await opened.first.drop();
      await pumpEventQueue();

      expect(opened, hasLength(2));
      await socket.stop();
    });

    test('keeps retrying when the server refuses', () async {
      final socket = build(failFirst: true);
      socket.start();
      await pumpEventQueue();

      // A refused connection is normal — the server sleeps, the phone changes
      // network — so it must be retried rather than reported.
      expect(requested, hasLength(greaterThan(1)));
      expect(opened, hasLength(1));
      await socket.stop();
    });

    test('reconnectNow skips the remaining backoff', () async {
      final socket = build(backoff: const Duration(hours: 1));
      socket.start();
      await pumpEventQueue();

      await opened.first.drop();
      await pumpEventQueue();
      expect(opened, hasLength(1), reason: 'should still be waiting');

      socket.reconnectNow();
      await pumpEventQueue();

      expect(opened, hasLength(2));
      await socket.stop();
    });

    test('stop ends the retry loop', () async {
      final socket = build();
      socket.start();
      await pumpEventQueue();
      await socket.stop();

      final afterStop = requested.length;
      await pumpEventQueue();

      expect(requested, hasLength(afterStop));
      expect(socket.isConnected, isFalse);
    });

    test('backoff grows but stays bounded', () {
      // Unbounded backoff would mean a client that lost the server overnight
      // takes hours to notice it came back.
      expect(PlexNotificationSocket.defaultBackoff(1).inSeconds, 1);
      expect(PlexNotificationSocket.defaultBackoff(3).inSeconds, 4);
      expect(PlexNotificationSocket.defaultBackoff(20).inSeconds, 60);
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}

class _FakeSocket implements PlexSocket {
  final _controller = StreamController<String>();

  @override
  Stream<String> get frames => _controller.stream;

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }

  void send(String frame) => _controller.add(frame);

  Future<void> drop() => close();
}
