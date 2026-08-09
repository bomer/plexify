/// Data models for the qBittorrent WebUI API v2.
///
/// Everything here is parsed the same defensive way the Plex models are, for
/// the same reason: fields come and go between qBittorrent releases, and a
/// missing one should degrade a single value rather than throw away a whole
/// result list.
library;

/// What a search plugin actually handed back in `fileUrl`.
///
/// **This is not a detail, it is the difference between a download starting and
/// silently not.** Plugins are inconsistent: some return a magnet, some a
/// `.torrent` file, and some — LimeTorrents among them — return the *human
/// page* where you would click the magnet yourself. qBittorrent accepts that
/// page URL, answers `Ok.`, fetches it, tries to bencode-decode a page of HTML
/// and fails in its own log with
/// `expected value (list, dict, int or string) in bencoded string`.
///
/// The app never sees that. The API call succeeded, so there is nothing to
/// report and nothing to retry — which is why this is handled by *preferring*
/// links that work and *labelling* the ones that do not, rather than by error
/// handling after the fact.
enum TorrentLink {
  /// `magnet:?xt=…`. Needs no fetch at all, so nothing can go wrong between
  /// here and the swarm.
  magnet,

  /// A URL ending `.torrent`. qBittorrent fetches and decodes it, which works
  /// unless the host wants a cookie or a referer.
  torrentFile,

  /// A page for a person to read. Adding it is the failure above.
  webPage,

  /// A URL with no extension to judge by — plenty of trackers serve a real
  /// torrent from `/download/12345`. Allowed, ranked below the certain ones.
  unknown;

  /// Classifies by URL shape, which is all there is to go on without fetching.
  ///
  /// Deliberately conservative in one direction: an unrecognised URL is
  /// [unknown] rather than [webPage], because plenty of working download links
  /// carry no extension and refusing them would rule out whole trackers. Only
  /// an extension that is definitely a document is called a page.
  static TorrentLink of(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.startsWith('magnet:')) return magnet;

    final path = Uri.tryParse(lower)?.path ?? lower;
    if (path.endsWith('.torrent')) return torrentFile;
    for (final extension in const ['.html', '.htm', '.php', '.aspx', '.jsp']) {
      if (path.endsWith(extension)) return webPage;
    }
    return unknown;
  }

  /// Whether handing this to qBittorrent stands a chance.
  bool get addable => this != webPage;

  /// Shown on every row in the results list.
  String get label => switch (this) {
    magnet => 'magnet',
    torrentFile => 'torrent file',
    webPage => 'web page',
    unknown => 'link',
  };
}

/// One search hit — a *torrent filename*, not a catalog entry.
///
/// Worth stating plainly, because it is the whole reason MusicBrainz is in this
/// app at all. qBittorrent's search plugins can tell you that somebody is
/// seeding something whose name matches your string. They cannot tell you that
/// an album exists, who released it, or when. That is why acquisition is
/// driven by a [CatalogRelease] and this is only ever the last step.
class QbitSearchResult {
  const QbitSearchResult({
    required this.fileName,
    required this.fileUrl,
    required this.sizeBytes,
    required this.seeders,
    required this.leechers,
    this.siteUrl,
    this.descriptionUrl,
  });

  final String fileName;

  /// A magnet link or a `.torrent` URL. This is what gets handed back to
  /// qBittorrent's add endpoint; nothing is downloaded by this app.
  final String fileUrl;

  /// -1 from some plugins, meaning "unknown", which must not be read as zero:
  /// a result with unknown size sorting below every 0-byte result would bury
  /// perfectly good hits.
  final int sizeBytes;

  /// Also -1 for "unknown" on some plugins. Ranking treats that as unknown
  /// rather than as unseeded.
  final int seeders;
  final int leechers;

  final String? siteUrl;

  /// The plugin's own link to the description page, when it offers one
  /// separately from [fileUrl].
  ///
  /// Worth carrying because it is the honest destination for a result whose
  /// [fileUrl] turns out to *be* a page: opening it in a browser is something
  /// the user can act on, whereas queueing it is a failure they will only ever
  /// see in qBittorrent's log.
  final String? descriptionUrl;

  bool get hasSize => sizeBytes > 0;
  bool get hasSeeders => seeders >= 0;

  /// What kind of link this is, which decides whether adding it can work.
  TorrentLink get link => TorrentLink.of(fileUrl);

  /// Where to send someone whose chosen result is a page rather than a torrent.
  String get pageUrl => descriptionUrl ?? fileUrl;

  factory QbitSearchResult.fromJson(Map<String, dynamic> json) =>
      QbitSearchResult(
        fileName: _str(json['fileName']) ?? '',
        fileUrl: _str(json['fileUrl']) ?? '',
        sizeBytes: _int(json['fileSize']) ?? -1,
        seeders: _int(json['nbSeeders']) ?? -1,
        leechers: _int(json['nbLeechers']) ?? -1,
        siteUrl: _str(json['siteUrl']),
        descriptionUrl: _str(json['descrLink']),
      );
}

/// A search job on the server. Searches are asynchronous: starting one returns
/// an id, and results accumulate until the plugins finish.
class QbitSearchJob {
  const QbitSearchJob({required this.id, required this.status});

  final int id;

  /// `Running` or `Stopped`. Polling stops when it stops, which is the only
  /// signal that no more results are coming.
  final String status;

  bool get isRunning => status.toLowerCase() == 'running';
}

/// A torrent qBittorrent is working on.
class QbitTorrent {
  const QbitTorrent({
    required this.hash,
    required this.name,
    required this.progress,
    required this.state,
    required this.sizeBytes,
    required this.category,
    this.etaSeconds,
    this.downloadRateBytes = 0,
  });

  final String hash;
  final String name;

  /// 0.0 to 1.0.
  final double progress;

  /// qBittorrent's own state string — `downloading`, `stalledDL`, `uploading`,
  /// `pausedUP`, `error`, and a dozen others. Kept raw and interpreted by
  /// [isComplete] and [isFailed] rather than parsed into an enum, because the
  /// set grows between releases and an unrecognised state must not become an
  /// error.
  final String state;

  final int sizeBytes;
  final String category;
  final int? etaSeconds;
  final int downloadRateBytes;

  /// Every state qBittorrent uses once the data is on disk. The upload-side
  /// states all mean "finished downloading", which is what matters here — this
  /// app cares about when to tell Plex to rescan, not about seeding.
  static const _completeStates = {
    'uploading',
    'stalledup',
    'pausedup',
    'stoppedup',
    'queuedup',
    'forcedup',
    'checkingup',
  };

  static const _failedStates = {'error', 'missingfiles', 'unknown'};

  bool get isComplete =>
      _completeStates.contains(state.toLowerCase()) || progress >= 1.0;

  bool get isFailed => _failedStates.contains(state.toLowerCase());

  factory QbitTorrent.fromJson(Map<String, dynamic> json) => QbitTorrent(
    hash: _str(json['hash']) ?? '',
    name: _str(json['name']) ?? '',
    progress: _double(json['progress']) ?? 0,
    state: _str(json['state']) ?? '',
    sizeBytes: _int(json['size']) ?? 0,
    category: _str(json['category']) ?? '',
    etaSeconds: _int(json['eta']),
    downloadRateBytes: _int(json['dlspeed']) ?? 0,
  );
}

/// Why a qBittorrent request failed, in terms the UI can act on.
///
/// The distinction that matters is [banned]. qBittorrent answers **403 both for
/// "not logged in" and for "this IP is temporarily banned for too many failed
/// logins"**, and the natural response to the first — log in again — is exactly
/// what extends the second. Anything retrying has to know which it is looking
/// at, and since the server does not say, the client treats a 403 *during
/// login* as a ban and refuses to try again on its own.
class QbitException implements Exception {
  const QbitException(this.message, {this.statusCode, this.banned = false});

  final String message;
  final int? statusCode;
  final bool banned;

  @override
  String toString() => message;
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

double? _double(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
