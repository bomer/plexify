import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../http/bounded_client.dart';
import 'slskd_models.dart';

/// slskd's REST API, v0.
///
/// **Markedly simpler than [QbitClient], and the reason is the auth.** slskd
/// takes a single `X-API-Key` header. There is no session to establish, no
/// cookie to keep, no CSRF check comparing `Referer` against `Host`, and no ban
/// for repeated failed sign-ins. Three quarters of the qBittorrent client is
/// machinery for those four things, and none of it is needed here, so none of
/// it has been copied across out of habit.
///
/// What *is* copied deliberately is the shape of [search]: start, poll, read,
/// and always delete in a `finally`. slskd keeps completed searches until they
/// are removed, exactly as qBittorrent does, and leaking them is the sort of
/// failure that shows up as searching mysteriously stopping working days later.
///
/// A note on where this sits in the flow: this client can tell you that
/// somebody is sharing files whose names match a string. It cannot tell you
/// that an album exists, who released it or when. That is MusicBrainz's job,
/// and it is why acquisition is always driven by a `CatalogRelease` and this is
/// only ever the last step.
class SlskdClient {
  SlskdClient({
    required String baseUrl,
    required this.apiKey,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 15),
  }) : baseUrl = _trim(baseUrl),
       _http = BoundedClient(httpClient ?? http.Client(), requestTimeout);

  /// Scheme, host and port, with no trailing slash.
  final String baseUrl;

  final String apiKey;

  final http.Client _http;

  static const _api = '/api/v0';

  /// How long slskd should keep asking the network, in milliseconds.
  ///
  /// A Soulseek search has no natural end: peers answer whenever they feel
  /// like it and many never do. The server stops waiting after this and keeps
  /// whatever arrived, which is why `Completed, TimedOut` is the ordinary
  /// successful ending rather than a failure.
  static const searchTimeoutMs = 15000;

  void close() => _http.close();

  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty;

  /// The running version, which doubles as a reachability check.
  ///
  /// Used by Save and test, because "it answered with a version" is a far
  /// better thing to show someone than "no error occurred".
  Future<String> version() async {
    final body = await _get('/application');
    if (body is Map<String, dynamic>) {
      final version = body['version'];
      if (version is Map<String, dynamic>) {
        final full = version['full'];
        if (full is String && full.isNotEmpty) return full;
      }
      if (version is String && version.isNotEmpty) return version;
    }
    // Reachable and authorised but shaped differently to expectation. Saying so
    // beats throwing, because the connection genuinely works.
    return 'unknown version';
  }

  /// Whether the Soulseek network itself is connected and logged in.
  ///
  /// Worth asking separately from [version]. slskd's own API answers perfectly
  /// while its connection to Soulseek is down, so a server that is reachable,
  /// authorised and completely unable to search looks identical to a healthy
  /// one until the first search returns nothing at all.
  Future<bool> isConnectedToSoulseek() async {
    try {
      final body = await _get('/application');
      if (body is! Map<String, dynamic>) return false;
      final server = body['server'];
      if (server is Map<String, dynamic>) {
        return server['isConnected'] == true && server['isLoggedIn'] == true;
      }
      return false;
    } on SlskdException {
      return false;
    }
  }

  /// Starts a search and returns its id.
  ///
  /// **The id must be a GUID.** slskd parses it into a `Nullable<Guid>` and
  /// rejects anything else with a 400 naming a .NET type, which is the first
  /// thing this client got wrong against a real server:
  ///
  /// ```
  /// The JSON value could not be converted to System.Nullable`1[System.Guid].
  /// Path: $.id
  /// ```
  ///
  /// Nothing in the API documentation says so, and an id is an id right up
  /// until it is not.
  ///
  /// The server's own id is preferred over the one sent, on the principle that
  /// the thing being polled should be named by whoever owns it. Ours is the
  /// fallback for a server that answers with no body.
  Future<String> startSearch(String text) async {
    final id = _uuid.v4();
    final body = await _post('/searches', body: {
      'id': id,
      'searchText': text,
      'searchTimeout': searchTimeoutMs,
      // Responses with nothing in them are noise, and every one of them costs
      // a group in the ranking that can never match anything.
      'minimumResponseFileCount': 1,
      'filterResponses': true,
    });

    if (body is Map<String, dynamic>) {
      final returned = body['id'];
      if (returned is String && returned.isNotEmpty) return returned;
    }
    return id;
  }

  Future<SlskdSearch> searchState(String id) async {
    final body = await _get('/searches/$id');
    if (body is! Map<String, dynamic>) {
      throw const SlskdException('slskd returned an unexpected search state');
    }
    return SlskdSearch.fromJson(body);
  }

  Future<List<SlskdResponse>> searchResponses(String id) async {
    final body = await _get('/searches/$id/responses');
    if (body is! List) return const [];
    return [
      for (final row in body.whereType<Map<String, dynamic>>())
        SlskdResponse.fromJson(row),
    ];
  }

  Future<void> deleteSearch(String id) => _delete('/searches/$id');

  /// Runs a search to completion, or until [timeout].
  ///
  /// Bounded on this side as well as the server's, because a server that stops
  /// answering mid-search would otherwise leave this polling forever. Whatever
  /// arrived by then is returned: partial results from the peers who answered
  /// beat an error caused by the ones who did not.
  ///
  /// **Always deletes the search.** Completed searches persist on the server
  /// until removed, so leaking them accumulates state on a machine the user
  /// runs and did not ask to have filled up.
  Future<List<SlskdResponse>> search(
    String text, {
    Duration timeout = const Duration(seconds: 25),
    Duration pollInterval = const Duration(milliseconds: 900),
  }) async {
    final id = await startSearch(text);
    final deadline = DateTime.now().add(timeout);

    try {
      while (DateTime.now().isBefore(deadline)) {
        final state = await searchState(id);
        if (state.isComplete) break;
        await Future<void>.delayed(pollInterval);
      }
      return await searchResponses(id);
    } finally {
      // Best effort. A search that produced results is still a success even if
      // tidying it away fails.
      try {
        await deleteSearch(id);
      } on Object {
        // Already gone, most likely.
      }
    }
  }

  /// Queues [files] from one peer.
  ///
  /// The whole folder goes in one request because that is what a record is
  /// here. Sent back with the peer's own `filename` and `size` verbatim: the
  /// path is theirs, and any normalising of separators on the way through
  /// would produce a path that peer cannot resolve.
  Future<void> enqueue(String username, List<SlskdFile> files) async {
    if (files.isEmpty) return;
    await _post(
      '/transfers/downloads/${Uri.encodeComponent(username)}',
      body: [
        for (final file in files) {'filename': file.filename, 'size': file.size},
      ],
    );
  }

  /// Everything being downloaded, a folder at a time.
  Future<List<SlskdDownload>> downloads() async {
    final body = await _get('/transfers/downloads');
    if (body is! List) return const [];

    return [
      for (final user in body.whereType<Map<String, dynamic>>())
        ...(() {
          final username = '${user['username'] ?? ''}';
          final directories = user['directories'];
          if (directories is! List) return const <SlskdDownload>[];
          return [
            for (final dir in directories.whereType<Map<String, dynamic>>())
              SlskdDownload.fromJson(username, dir),
          ];
        })(),
    ];
  }

  // -------------------------------------------------------------------------

  Future<Object?> _get(String path) async =>
      _decode(await _send(() => _http.get(_uri(path), headers: _headers())));

  Future<Object?> _post(String path, {Object? body}) async => _decode(
    await _send(
      () => _http.post(
        _uri(path),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    ),
  );

  Future<void> _delete(String path) async {
    await _send(() => _http.delete(_uri(path), headers: _headers()));
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$_api$path');

  Map<String, String> _headers() => {
    'X-API-Key': apiKey,
    'Accept': 'application/json',
  };

  /// Runs [send] and turns anything that is not a success into an exception
  /// that names the actual problem.
  ///
  /// There is no retry here and that is deliberate. Nothing about this API is
  /// stateful enough to need one: a failed request has no session to refresh,
  /// so retrying could only ever repeat the same failure with the same key.
  Future<http.Response> _send(Future<http.Response> Function() send) async {
    final http.Response response;
    try {
      response = await send();
    } on TimeoutException {
      throw SlskdException(
        'slskd did not answer within the timeout. Check that $baseUrl is '
        'reachable from this device.',
      );
    } on Object catch (e) {
      throw SlskdException('Could not reach slskd at $baseUrl: $e');
    }

    if (response.statusCode == 401) {
      // Names the *shape*, not just the file. api_keys is a map of named
      // entries, so a key pasted in as a bare string leaves the map empty and
      // slskd is answering perfectly correctly: it has no keys at all.
      throw const SlskdException(
        'slskd rejected the API key (401). It must be a named entry under '
        'web.authentication.api_keys in slskd.yml, not a bare value:\n\n'
        '  api_keys:\n'
        '    plexify:\n'
        '      key: <your key>\n'
        '      role: readwrite\n\n'
        'Restart slskd afterwards, since authentication is not reloaded on '
        'the fly.',
        statusCode: 401,
        unauthorized: true,
      );
    }
    if (response.statusCode == 403) {
      // Named rather than lumped in with 401, because the key is right and the
      // fix is somewhere else entirely. Two somewhere elses, in fact, and the
      // role one is nastier: **a readonly key searches perfectly and only
      // fails on the download**, so it presents an hour later as a completely
      // different bug. Keys configured in YAML default to readonly.
      throw const SlskdException(
        'slskd accepted the API key but refused the request (403). Either the '
        'key is readonly, which is the default for keys in slskd.yml and is '
        'enough to search but not to download, so it needs role: readwrite. '
        'Or its cidr does not cover this device: behind a reverse proxy slskd '
        "sees the proxy's address rather than this one's.",
        statusCode: 403,
        forbidden: true,
      );
    }
    if (response.statusCode == 404) {
      throw SlskdException(
        'slskd has no endpoint at that address (404). Check the URL points at '
        'slskd itself rather than at a path underneath it.',
        statusCode: 404,
      );
    }
    if (response.statusCode >= 400) {
      final detail = response.body.trim();
      throw SlskdException(
        detail.isEmpty
            ? 'slskd answered HTTP ${response.statusCode}'
            : 'slskd answered HTTP ${response.statusCode}: '
                  '${detail.length > 200 ? '${detail.substring(0, 200)}...' : detail}',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  /// Decodes a body, tolerating the empty ones.
  ///
  /// Several endpoints here answer 200 or 204 with nothing at all, and
  /// `jsonDecode('')` throws, which would turn every successful enqueue into
  /// an error.
  static Object? _decode(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const SlskdException('slskd returned something that is not JSON');
    }
  }

  static const _uuid = Uuid();

  /// Normalises the configured address.
  ///
  /// A trailing slash would make every path double-slashed. slskd itself is
  /// relaxed about that, but a reverse proxy in front of it very often is not,
  /// and the resulting 404 names nothing useful.
  static String _trim(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
