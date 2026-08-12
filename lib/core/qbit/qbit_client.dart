import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http/bounded_client.dart';
import 'qbit_models.dart';

/// qBittorrent WebUI API v2.
///
/// One authentication layer, not two. The WebUI's own login form *is* the API's
/// `/auth/login`, so there is no HTTP Basic wrapper to get through and no API
/// key mechanism to prefer — 5.x documents cookie/SID auth only. That is why
/// the username and password are stored rather than a token: there is nothing
/// else to store.
///
/// **Two traps, both answering 403, both paid for in advance.**
///
/// `Referer` (and `Origin`) must match the `Host` header exactly, *including the
/// port*. This is qBittorrent's CSRF protection and it is the single most common
/// cause of an unexplained 403 against a server that is working perfectly from a
/// browser. [_formHeaders] derives them from the configured base URL so they
/// cannot drift apart.
///
/// A 403 **also** means "this IP is banned for too many failed logins". The
/// obvious response to a 403 is to log in again, and doing that automatically
/// is precisely what extends the ban — on a server the user runs themselves,
/// from a phone they are holding. So: one login attempt, then an explicit error
/// state, and never a retry loop. [QbitException.banned] carries that decision
/// to the UI.
class QbitClient {
  QbitClient({
    required String baseUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : baseUrl = _trim(baseUrl),
       _http = BoundedClient(httpClient ?? http.Client(), requestTimeout);

  /// Scheme, host and port, with no trailing slash.
  final String baseUrl;
  final String username;
  final String password;

  final http.Client _http;

  /// The session cookie. Held in memory only — it is short-lived and a stale
  /// one costs a single re-login, whereas persisting it would mean another
  /// secret on disk for no gain.
  String? _sid;

  /// Set once a 403 has been seen on the login path.
  ///
  /// Latched deliberately: nothing in this client clears it, because the client
  /// cannot tell a ban from a wrong password and guessing again is the one
  /// action that makes either worse. The user clears it by pressing the button
  /// in Settings again, which builds a new client.
  bool get lockedOut => _lockedOut;
  bool _lockedOut = false;

  static const category = 'Music';

  /// Where the search endpoints live. Separated because they are the one part
  /// of the API that needs plugins installed server-side, and a server without
  /// them answers 409 rather than saying so.
  static const _searchPath = '/api/v2/search';

  void close() => _http.close();

  bool get isConfigured => baseUrl.isNotEmpty && username.isNotEmpty;

  /// Establishes a session, or throws.
  ///
  /// qBittorrent answers **200 with the body `Fails.`** for a wrong password
  /// rather than 401, so the status code alone says nothing. Reading the body
  /// is the only way to tell a rejected login from a successful one.
  Future<void> login() async {
    if (_lockedOut) {
      throw const QbitException(
        'Refusing to sign in again: qBittorrent answered 403, which also '
        'means this address is temporarily banned for failed logins. Check '
        'the username and password, then try again.',
        statusCode: 403,
        banned: true,
      );
    }

    final response = await _http.post(
      Uri.parse('$baseUrl/api/v2/auth/login'),
      headers: _formHeaders(),
      body: {'username': username, 'password': password},
    );

    if (response.statusCode == 403) {
      _lockedOut = true;
      throw const QbitException(
        'qBittorrent refused the sign-in (403). That is either the CSRF check '
        'or a temporary ban from repeated failed logins — no automatic retry '
        'will be made.',
        statusCode: 403,
        banned: true,
      );
    }
    if (response.statusCode != 200) {
      throw QbitException(
        'qBittorrent answered HTTP ${response.statusCode} to the sign-in',
        statusCode: response.statusCode,
      );
    }
    if (response.body.trim() != 'Ok.') {
      throw const QbitException(
        'qBittorrent rejected the username or password',
      );
    }

    _sid = _sessionCookie(response.headers['set-cookie']);
    if (_sid == null) {
      throw const QbitException(
        'qBittorrent accepted the sign-in but sent no session cookie',
      );
    }
  }

  /// The server version, which doubles as a reachability check.
  ///
  /// Used by the Test connection button, because "it answered with a version"
  /// is a far better thing to show than "no error occurred".
  Future<String> version() async {
    final response = await _authorised(
      () => _http.get(
        Uri.parse('$baseUrl/api/v2/app/version'),
        headers: _authHeaders(),
      ),
    );
    return response.body.trim();
  }

  /// Whether any search plugin is installed and enabled.
  ///
  /// Worth asking before searching rather than after: with no plugins the
  /// search endpoints answer perfectly happily and return nothing at all, which
  /// is indistinguishable from an album nobody is seeding.
  Future<bool> hasSearchPlugins() async {
    try {
      final response = await _authorised(
        () => _http.get(
          Uri.parse('$_searchPathAbsolute/plugins'),
          headers: _authHeaders(),
        ),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return false;
      return decoded.whereType<Map<String, dynamic>>().any(
        (p) => p['enabled'] == true,
      );
    } on Object {
      return false;
    }
  }

  String get _searchPathAbsolute => '$baseUrl$_searchPath';

  /// Starts a search and returns its id.
  Future<int> startSearch(String pattern) async {
    final response = await _authorised(
      () => _http.post(
        Uri.parse('$_searchPathAbsolute/start'),
        headers: _formHeaders(withAuth: true),
        body: {'pattern': pattern, 'plugins': 'enabled', 'category': 'all'},
      ),
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['id'] == null) {
      throw const QbitException('qBittorrent did not return a search id');
    }
    final id = decoded['id'];
    return id is int ? id : int.parse('$id');
  }

  /// One poll of a running search.
  ///
  /// Returns whatever has accumulated so far along with the job's status. The
  /// plugins answer at wildly different speeds, so the first poll of a live
  /// search routinely returns two results and the fourth returns eighty.
  Future<(QbitSearchJob, List<QbitSearchResult>)> searchResults(
    int id, {
    int limit = 100,
  }) async {
    final response = await _authorised(
      () => _http.get(
        Uri.parse(
          '$_searchPathAbsolute/results',
        ).replace(queryParameters: {'id': '$id', 'limit': '$limit'}),
        headers: _authHeaders(),
      ),
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const QbitException('Unexpected shape from the search results');
    }

    final raw = decoded['results'];
    final results = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(QbitSearchResult.fromJson)
              .where((r) => r.fileUrl.isNotEmpty)
              .toList()
        : <QbitSearchResult>[];

    return (
      QbitSearchJob(id: id, status: '${decoded['status'] ?? 'Stopped'}'),
      results,
    );
  }

  /// Runs a search to completion, or until [timeout].
  ///
  /// Bounded because a plugin pointed at a dead tracker never finishes and the
  /// job would sit `Running` indefinitely. Whatever arrived by then is returned:
  /// partial results from three working plugins beat an error caused by a
  /// fourth.
  ///
  /// Always deletes the job. qBittorrent keeps completed searches until they
  /// are removed and caps how many may exist, so leaking them means searching
  /// stops working after a few dozen attempts with an error that names nothing
  /// relevant.
  Future<List<QbitSearchResult>> search(
    String pattern, {
    Duration timeout = const Duration(seconds: 25),
    Duration pollInterval = const Duration(milliseconds: 900),
  }) async {
    final id = await startSearch(pattern);
    final deadline = DateTime.now().add(timeout);
    var results = <QbitSearchResult>[];

    try {
      while (DateTime.now().isBefore(deadline)) {
        final (job, found) = await searchResults(id);
        results = found;
        if (!job.isRunning) break;
        await Future<void>.delayed(pollInterval);
      }
    } finally {
      // Best effort on both. A search that produced results is still a success
      // even if tidying it away fails.
      try {
        await _authorised(
          () => _http.post(
            Uri.parse('$_searchPathAbsolute/stop'),
            headers: _formHeaders(withAuth: true),
            body: {'id': '$id'},
          ),
        );
      } on Object {
        // Already stopped, most likely.
      }
      try {
        await _authorised(
          () => _http.post(
            Uri.parse('$_searchPathAbsolute/delete'),
            headers: _formHeaders(withAuth: true),
            body: {'id': '$id'},
          ),
        );
      } on Object {
        // Leaked job. Recorded nowhere because there is nothing to do about it
        // from here, and the cap is in the dozens.
      }
    }

    return results;
  }

  /// Queues a torrent, filed under [category].
  ///
  /// `Music` because James's existing automation routes that category to the
  /// folder Plex watches — which is what makes this whole flow one step rather
  /// than three. Nothing here renames, retags or moves anything; the category
  /// is the entire integration.
  Future<void> addTorrent(String urlOrMagnet) async {
    final response = await _authorised(
      () => _http.post(
        Uri.parse('$baseUrl/api/v2/torrents/add'),
        headers: _formHeaders(withAuth: true),
        body: {'urls': urlOrMagnet, 'category': category},
      ),
    );

    // Answers 200 with `Ok.` on success and 415 for a torrent it could not
    // parse. A 200 whose body is not Ok. has happened with malformed magnets.
    if (response.body.trim().isNotEmpty &&
        response.body.trim() != 'Ok.' &&
        response.statusCode == 200) {
      throw QbitException('qBittorrent said: ${response.body.trim()}');
    }
  }

  /// Torrents in the Music category, newest activity first as the server
  /// returns them.
  Future<List<QbitTorrent>> torrents() async {
    final response = await _authorised(
      () => _http.get(
        Uri.parse(
          '$baseUrl/api/v2/torrents/info',
        ).replace(queryParameters: {'category': category, 'sort': 'added_on'}),
        headers: _authHeaders(),
      ),
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(QbitTorrent.fromJson)
        .toList()
        .reversed
        .toList();
  }

  // -------------------------------------------------------------------------

  /// Runs [send], logging in first if there is no session and **once** more if
  /// the session had expired.
  ///
  /// The single retry is the whole reason this wrapper exists: SIDs expire on
  /// their own schedule, and without it every screen would have to handle "was
  /// working a minute ago". It is bounded at one attempt, and a 403 raised by
  /// [login] latches [lockedOut] rather than coming back around.
  Future<http.Response> _authorised(
    Future<http.Response> Function() send,
  ) async {
    if (_sid == null) await login();

    var response = await send();
    if (response.statusCode == 403) {
      _sid = null;
      await login();
      response = await send();
    }

    if (response.statusCode == 409) {
      throw QbitException(
        'qBittorrent refused the request (409). For a search, that usually '
        'means no search plugins are installed on the server.',
        statusCode: 409,
      );
    }
    if (response.statusCode >= 400) {
      throw QbitException(
        'qBittorrent answered HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  Map<String, String> _authHeaders() => {
    // Sent on every request, not just the mutating ones. qBittorrent applies
    // the CSRF check to the whole API, and a GET that fails this looks exactly
    // like a session that expired.
    'Referer': baseUrl,
    'Origin': baseUrl,
    if (_sid != null) 'Cookie': 'SID=$_sid',
  };

  Map<String, String> _formHeaders({bool withAuth = false}) => {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Referer': baseUrl,
    'Origin': baseUrl,
    if (withAuth && _sid != null) 'Cookie': 'SID=$_sid',
  };

  /// Pulls `SID` out of a `Set-Cookie` header.
  ///
  /// `package:http` collapses multiple Set-Cookie headers into one
  /// comma-separated string, and cookie attributes contain commas of their own
  /// (`Expires=Mon, 01 Jan…`), so this scans for the name rather than splitting.
  static String? _sessionCookie(String? header) {
    if (header == null) return null;
    final match = RegExp(r'SID=([^;,\s]+)').firstMatch(header);
    return match?.group(1);
  }

  /// Normalises the configured address.
  ///
  /// A trailing slash makes every path double-slashed, which most servers
  /// tolerate and qBittorrent's CSRF check does not, because the `Referer` then
  /// stops matching. Cheaper to fix here than to explain.
  static String _trim(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
