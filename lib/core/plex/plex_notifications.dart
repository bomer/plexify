import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'plex_identity.dart';
import 'plex_server.dart';

/// What happened to an item in the library.
enum PlexChangeKind {
  /// Added or edited. The item must be re-fetched — the notification carries a
  /// key and a type, never the metadata itself.
  upserted,

  /// Removed from the server.
  deleted,
}

/// One library change, as pushed by Plex.
@immutable
class PlexLibraryChange {
  const PlexLibraryChange({
    required this.kind,
    required this.ratingKey,
    this.metadataType,
    this.sectionKey,
  });

  final PlexChangeKind kind;
  final String ratingKey;

  /// Plex's numeric metadata type — 8 artist, 9 album, 10 track, 15 playlist.
  /// Null when the server omitted it, in which case the type has to come from
  /// the metadata fetch instead.
  final int? metadataType;

  final String? sectionKey;

  @override
  bool operator ==(Object other) =>
      other is PlexLibraryChange &&
      other.kind == kind &&
      other.ratingKey == ratingKey &&
      other.metadataType == metadataType &&
      other.sectionKey == sectionKey;

  @override
  int get hashCode => Object.hash(kind, ratingKey, metadataType, sectionKey);

  @override
  String toString() => 'PlexLibraryChange(${kind.name}, $ratingKey)';
}

/// Plex metadata type numbers seen on the notification socket.
abstract final class PlexMetadataType {
  static const artist = 8;
  static const album = 9;
  static const track = 10;
  static const playlist = 15;
}

/// Timeline states Plex reports while it works through an item.
///
/// Only [complete] is safe to act on: below it the server is still writing the
/// item, and fetching then would store half-scanned metadata — a track with no
/// part key, or an album with no artist — which then looks like a permanent
/// cache bug rather than a transient one.
abstract final class _TimelineState {
  static const complete = 5;
  static const deleted = 9;
}

/// Turns one raw socket frame into the changes it describes.
///
/// Pure and total: anything unrecognised yields an empty list rather than
/// throwing. The socket is a long-lived connection carrying several unrelated
/// notification types (playback status, activities, transcode progress), so
/// most frames are legitimately of no interest, and one malformed frame must
/// never take the connection down.
List<PlexLibraryChange> parsePlexNotifications(String frame) {
  final Object? decoded;
  try {
    decoded = jsonDecode(frame);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];

  // Modern servers wrap everything in NotificationContainer. Older ones send
  // the payload bare, so fall back to the root rather than dropping the frame.
  final container = decoded['NotificationContainer'] is Map<String, dynamic>
      ? decoded['NotificationContainer'] as Map<String, dynamic>
      : decoded;

  if (container['type'] != 'timeline') return const [];

  final entries = container['TimelineEntry'];
  if (entries is! List) return const [];

  final changes = <PlexLibraryChange>[];
  for (final entry in entries.whereType<Map<String, dynamic>>()) {
    // Other plugins share this socket; only library items concern us.
    final identifier = entry['identifier'];
    if (identifier is String && identifier != 'com.plexapp.plugins.library') {
      continue;
    }

    final ratingKey = _str(entry['itemID']);
    if (ratingKey == null || ratingKey.isEmpty || ratingKey == '0') continue;

    final state = _int(entry['state']);
    final metadataState = entry['metadataState'];

    final PlexChangeKind kind;
    if (state == _TimelineState.deleted || metadataState == 'deleted') {
      kind = PlexChangeKind.deleted;
    } else if (state == _TimelineState.complete) {
      kind = PlexChangeKind.upserted;
    } else {
      continue;
    }

    changes.add(
      PlexLibraryChange(
        kind: kind,
        ratingKey: ratingKey,
        metadataType: _int(entry['type']),
        sectionKey: _str(entry['sectionID']),
      ),
    );
  }
  return changes;
}

/// An open notification connection: a stream of text frames and a way to hang
/// up.
///
/// Abstracted so the reconnection logic can be tested without a socket. The
/// alternative — a real server in tests — would make the retry behaviour, which
/// is the part most likely to be wrong, effectively untestable.
abstract class PlexSocket {
  Stream<String> get frames;
  Future<void> close();
}

/// Opens a connection to [uri]. Throws if it cannot.
typedef PlexSocketConnector =
    Future<PlexSocket> Function(Uri uri, Map<String, String> headers);

/// Plex's push notification channel.
///
/// This is the primary sync mechanism. Plex emits a timeline entry the moment
/// it finishes scanning an item, so a track added to the server appears here in
/// under a second — faster than polling could ever be, and faster than Plexamp
/// reflects the same change.
///
/// Keeps itself connected: any drop is retried with exponential backoff, and
/// [reconnectNow] short-circuits the wait when there is reason to believe the
/// network just came back.
class PlexNotificationSocket {
  PlexNotificationSocket({
    required PlexServer server,
    required PlexIdentity identity,
    PlexSocketConnector? connector,
    Duration Function(int attempt)? backoff,
  }) : _server = server,
       _identity = identity,
       _connect = connector ?? _connectViaDartIo,
       _backoff = backoff ?? defaultBackoff;

  final PlexServer _server;
  final PlexIdentity _identity;
  final PlexSocketConnector _connect;
  final Duration Function(int) _backoff;

  final _changes = StreamController<PlexLibraryChange>.broadcast();

  PlexSocket? _current;
  Completer<void>? _waking;
  bool _running = false;
  bool _stopped = false;

  /// Library changes, as they arrive. Broadcast — several listeners may care.
  Stream<PlexLibraryChange> get changes => _changes.stream;

  /// True while a connection is open.
  bool get isConnected => _current != null;

  /// Doubling backoff, capped at a minute.
  ///
  /// Capped rather than unbounded because the common cause of a drop is the
  /// server or the network being briefly away, and a client that has backed off
  /// to hours would then take hours to notice it came back.
  static Duration defaultBackoff(int attempt) {
    const capSeconds = 60;
    final seconds = 1 << (attempt - 1).clamp(0, 6);
    return Duration(seconds: seconds > capSeconds ? capSeconds : seconds);
  }

  /// Begins connecting, and keeps reconnecting until [stop].
  void start() {
    if (_running || _stopped) return;
    _running = true;
    unawaited(_loop());
  }

  /// Stops reconnecting and closes any open connection.
  Future<void> stop() async {
    _stopped = true;
    _running = false;
    _wake();
    final socket = _current;
    _current = null;
    try {
      await socket?.close();
    } on Object {
      // Already gone; nothing to release.
    }
    await _changes.close();
  }

  /// Retries immediately instead of waiting out the current backoff.
  ///
  /// Called when the app returns to the foreground: the OS may have quietly
  /// killed the socket while backgrounded, and waiting up to a minute to
  /// discover that is exactly the "I added it, why isn't it here" lag this
  /// whole mechanism exists to remove.
  void reconnectNow() {
    if (_stopped || isConnected) return;
    _attempt = 0;
    _wake();
  }

  int _attempt = 0;

  Uri get _uri {
    final base = Uri.parse(_server.baseUrl);
    return base.replace(
      // The token goes in the query string as well as the headers: websocket
      // handshake headers are not carried reliably on every platform, and this
      // is what Plex's own clients do.
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/:/websockets/notifications',
      queryParameters: {'X-Plex-Token': _server.token},
    );
  }

  Future<void> _loop() async {
    while (!_stopped) {
      final openedAt = DateTime.now();
      try {
        final socket = await _connect(
          _uri,
          _identity.headers(token: _server.token),
        );
        _current = socket;

        await for (final frame in socket.frames) {
          for (final change in parsePlexNotifications(frame)) {
            if (!_changes.isClosed) _changes.add(change);
          }
        }
      } on Object {
        // Every failure mode here — refused, timed out, dropped mid-stream — is
        // handled the same way, by retrying. Surfacing it would only produce an
        // error banner for something that fixes itself.
      } finally {
        _current = null;
      }

      if (_stopped) break;

      // A connection that lived a while and then dropped is a blip; retry
      // quickly. One that dies immediately is a real problem — a bad token, a
      // server that has gone away — and hammering it would help nobody.
      final lived = DateTime.now().difference(openedAt);
      _attempt = lived >= const Duration(seconds: 30) ? 1 : _attempt + 1;

      await _sleep(_backoff(_attempt));
    }
    _running = false;
  }

  /// Waits, but wakes early if [stop] or [reconnectNow] says so.
  Future<void> _sleep(Duration duration) async {
    final waking = Completer<void>();
    _waking = waking;
    final timer = Timer(duration, () {
      if (!waking.isCompleted) waking.complete();
    });
    await waking.future;
    timer.cancel();
    _waking = null;
  }

  void _wake() {
    final waking = _waking;
    if (waking != null && !waking.isCompleted) waking.complete();
  }
}

Future<PlexSocket> _connectViaDartIo(
  Uri uri,
  Map<String, String> headers,
) async {
  final socket = await WebSocket.connect(uri.toString(), headers: headers);
  return _IoPlexSocket(socket);
}

class _IoPlexSocket implements PlexSocket {
  _IoPlexSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get frames => _socket.map(
    (event) => event is String ? event : utf8.decode(event as List<int>),
  );

  @override
  Future<void> close() => _socket.close();
}

String? _str(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  return v.toString();
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
