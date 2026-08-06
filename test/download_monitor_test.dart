import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plexify/core/qbit/download_monitor.dart';
import 'package:plexify/core/qbit/qbit_client.dart';

/// The monitor turns a finished download into a Plex rescan.
///
/// Two mistakes are easy here and neither is visible on screen. Announcing
/// everything already complete on the first poll asks Plex to rescan the whole
/// library on every cold start; announcing a finished torrent on *every*
/// subsequent poll does the same thing continuously, because qBittorrent keeps
/// seeding it and it never leaves the list.
void main() {
  /// A qBittorrent whose Music category is whatever the last call to
  /// [setTorrents] said.
  ({QbitClient client, void Function(List<Map<String, Object?>>) setTorrents})
  server() {
    var torrents = <Map<String, Object?>>[];
    final client = QbitClient(
      baseUrl: 'https://box.local:8080',
      username: 'james',
      password: 'hunter2',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            'Ok.',
            200,
            headers: const {'set-cookie': 'SID=abc'},
          );
        }
        return http.Response(jsonEncode(torrents), 200);
      }),
    );
    return (client: client, setTorrents: (t) => torrents = t);
  }

  Map<String, Object?> torrent(
    String hash, {
    required double progress,
    required String state,
  }) => {
    'hash': hash,
    'name': 'Radiohead - OK Computer',
    'progress': progress,
    'state': state,
    'size': 400000000,
    'category': 'Music',
  };

  test('does not announce what was already finished at launch', () async {
    final fake = server();
    fake.setTorrents([
      torrent('h1', progress: 1, state: 'uploading'),
      torrent('h2', progress: 1, state: 'pausedUP'),
    ]);

    var rescans = 0;
    final monitor = DownloadMonitor(
      client: () => fake.client,
      onComplete: () async => rescans++,
    );
    addTearDown(monitor.stop);

    await monitor.pollNow();

    // Everything in the category is complete on a cold start, since qBittorrent
    // seeds afterwards. Treating that as news means a full Plex rescan every
    // time the app opens.
    expect(rescans, 0);
    expect(monitor.completions, 0);
  });

  test('announces a download that finishes, exactly once', () async {
    final fake = server();
    fake.setTorrents([torrent('h1', progress: 0.4, state: 'downloading')]);

    var rescans = 0;
    final monitor = DownloadMonitor(
      client: () => fake.client,
      onComplete: () async => rescans++,
    );
    addTearDown(monitor.stop);

    await monitor.pollNow();
    expect(rescans, 0);

    fake.setTorrents([torrent('h1', progress: 1, state: 'uploading')]);
    await monitor.pollNow();
    expect(rescans, 1);

    // Still in the list, still complete, still seeding. Without the reported
    // set this asks Plex to rescan every five seconds for the rest of the
    // session.
    await monitor.pollNow();
    await monitor.pollNow();
    expect(rescans, 1);
    expect(monitor.completions, 1);
  });

  test('keeps polling after qBittorrent stops answering', () async {
    var fail = true;
    final client = QbitClient(
      baseUrl: 'https://box.local:8080',
      username: 'james',
      password: 'hunter2',
      httpClient: MockClient((request) async {
        if (fail) return http.Response('nope', 500);
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            'Ok.',
            200,
            headers: const {'set-cookie': 'SID=abc'},
          );
        }
        return http.Response(jsonEncode(<Object>[]), 200);
      }),
    );

    final monitor = DownloadMonitor(
      client: () => client,
      onComplete: () async {},
    );
    addTearDown(monitor.stop);

    await monitor.pollNow();
    expect(monitor.lastError, isNotNull);

    // qBittorrent being asleep, restarting or briefly unreachable is ordinary.
    // A monitor that gave up on the first failure would only work when it was
    // never needed.
    fail = false;
    await monitor.pollNow();
    expect(monitor.lastError, isNull);
    expect(monitor.polls, 1);
  });
}
