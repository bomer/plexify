/// The one shape the acquisition UI knows about, whichever server is behind it.
///
/// **Why a seam rather than two screens.** The sheet that shows results, the
/// one-tap flow that queues the obvious answer, and the screen that watches
/// what is arriving are all the same interaction whether the file comes from a
/// tracker or from a person. What differs is entirely vocabulary: seeders
/// against upload slots, a magnet link against a folder on somebody's disk.
/// Two copies of that UI would be two places to fix every future bug, and the
/// second copy would be the one nobody remembered.
///
/// So the source-specific models stay source-specific and are wrapped in an
/// [AcquireCandidate] at the boundary. The sheet reads six things off it and
/// knows nothing else.
library;

import '../catalog/catalog_models.dart';
import '../qbit/qbit_models.dart';
import '../qbit/torrent_ranking.dart';
import '../slskd/album_ranking.dart';
import '../slskd/slskd_models.dart';

/// Which server does the downloading.
///
/// **Only one is ever active**, chosen in Settings. Searching both and merging
/// was considered and rejected: the two rank on entirely different evidence,
/// and a combined list would either be sorted by a number that means different
/// things in each half, or would double the wait exactly when a record is hard
/// to find and patience is thinnest.
enum DownloadSourceKind {
  qbittorrent('qBittorrent'),
  soulseek('Soulseek');

  const DownloadSourceKind(this.label);

  /// What to call it on screen. The servers' own names, because those are what
  /// the user configured and what they will search for when something breaks.
  final String label;

  static DownloadSourceKind byName(String? name) => values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => qbittorrent,
  );
}

/// How likely tapping a result is to actually start a download.
///
/// Four states rather than a boolean because the difference is categorical and
/// it is the first thing worth knowing about a row. Deliberately shared across
/// both sources even though the underlying reasons have nothing in common: a
/// magnet and an idle peer both mean "this starts now", and that is what the
/// person reading the list is asking.
enum AcquireReadiness {
  /// Starts immediately. A magnet, or a peer with a free upload slot.
  now,

  /// Will start, after something. A torrent file the client must fetch first,
  /// or a peer with a queue in front of you.
  soon,

  /// No way to tell from here.
  unknown,

  /// Will never download. A web page rather than a torrent.
  never,
}

/// One result, as the UI sees it.
///
/// Sealed so that adding a third source is a compile error everywhere it needs
/// to be handled, rather than a runtime surprise in whichever branch nobody
/// updated.
sealed class AcquireCandidate {
  const AcquireCandidate();

  /// The line a person reads to decide. A torrent filename, or the folder a
  /// peer keeps the record in.
  String get title;

  /// Everything else worth knowing, already phrased in the vocabulary of
  /// whichever source produced it. The sheet renders this and does not try to
  /// understand it.
  String get subtitle;

  /// Whether the name actually names this record.
  ///
  /// The gate for acting without being asked. Both sources match on names, so
  /// both can return something popular and wrong.
  bool get matchesRelease;

  AcquireReadiness get readiness;

  /// Whether handing this to the server stands any chance of working.
  bool get addable => readiness != AcquireReadiness.never;

  /// Where to send someone whose chosen result turns out to be a page. Null
  /// for anything with nowhere to go, which is every Soulseek result.
  String? get pageUrl => null;

  /// Shown when the icon is hovered, and source-specific on purpose: "magnet
  /// link" and "free upload slot" both mean [AcquireReadiness.now] and neither
  /// explains the other.
  String get readinessTooltip;
}

/// A torrent search hit.
class TorrentCandidate extends AcquireCandidate {
  const TorrentCandidate(this.torrent);

  final RankedTorrent torrent;

  @override
  String get title => torrent.result.fileName;

  @override
  bool get matchesRelease => torrent.matchesRelease;

  @override
  AcquireReadiness get readiness => switch (torrent.result.link) {
    TorrentLink.webPage => AcquireReadiness.never,
    TorrentLink.magnet =>
      // A magnet nobody is seeding cannot fail to add and will never finish
      // either, so it is not "starts now" in any sense that helps.
      torrent.result.hasSeeders && torrent.result.seeders < 1
          ? AcquireReadiness.unknown
          : AcquireReadiness.now,
    TorrentLink.torrentFile => AcquireReadiness.soon,
    TorrentLink.unknown => AcquireReadiness.unknown,
  };

  @override
  String get readinessTooltip => switch (torrent.result.link) {
    TorrentLink.magnet => 'Magnet link, adds directly',
    TorrentLink.torrentFile => 'Torrent file, qBittorrent fetches it',
    TorrentLink.unknown => 'Plain link, probably a torrent file',
    TorrentLink.webPage => 'A page, not a torrent. Opens in your browser',
  };

  @override
  String? get pageUrl =>
      torrent.result.link == TorrentLink.webPage ? torrent.result.pageUrl : null;

  @override
  String get subtitle => [
    torrent.result.link.label,
    if (torrent.result.hasSeeders)
      '${torrent.result.seeders} seeders'
    else
      'seeders unknown',
    if (torrent.result.hasSize) formatBytes(torrent.result.sizeBytes),
    if (torrent.format != AudioFormat.unknown) torrent.format.name,
  ].join(' · ');
}

/// A folder one peer is sharing.
class SoulseekCandidate extends AcquireCandidate {
  const SoulseekCandidate(this.album);

  final SlskdAlbum album;

  @override
  String get title => album.folderName;

  @override
  bool get matchesRelease => album.matchesRelease;

  /// **Never [AcquireReadiness.never].** Anything Soulseek returns can be
  /// queued; the only question is how long it waits. There is no equivalent of
  /// a torrent search plugin handing back a web page.
  @override
  AcquireReadiness get readiness {
    if (album.hasFreeUploadSlot) return AcquireReadiness.now;
    if (album.queueLength <= 10) return AcquireReadiness.soon;
    return AcquireReadiness.unknown;
  }

  @override
  String get readinessTooltip => album.hasFreeUploadSlot
      ? 'Free upload slot, starts now'
      : album.queueLength > 0
      ? '${album.queueLength} ahead of you in this person\'s queue'
      : 'No free slot right now, so it will wait';

  @override
  String get subtitle => [
    album.username,
    '${album.trackCount} ${album.trackCount == 1 ? 'track' : 'tracks'}',
    if (album.sizeBytes > 0) formatBytes(album.sizeBytes),
    if (album.format != AudioFormat.unknown)
      // The real figure from the peer's client, so it is worth showing rather
      // than just ranking on.
      album.format == AudioFormat.lossy && album.bitRate != null
          ? '${album.bitRate} kbps'
          : album.format.name,
  ].join(' · ');
}

/// What came back from looking for a record, and what was done about it.
class AcquireOutcome {
  const AcquireOutcome({
    required this.kind,
    this.queued,
    this.candidates = const [],
    this.error,
    this.unusable = false,
  });

  const AcquireOutcome.failed(this.kind, String this.error)
    : queued = null,
      candidates = const [],
      unusable = false;

  final DownloadSourceKind kind;

  /// The result that was added, when one was good enough to add without asking.
  final AcquireCandidate? queued;

  /// Everything found, best first. Populated whether or not anything was
  /// queued, so "change that" is always one tap away.
  final List<AcquireCandidate> candidates;

  final String? error;

  /// The server is reachable but cannot search at all.
  ///
  /// Called out separately because it is the one failure that looks exactly
  /// like success: the search runs happily and returns nothing, so without this
  /// it reads as "nobody has this album" for every album forever. qBittorrent
  /// with no plugins installed and slskd logged out of Soulseek are the same
  /// problem wearing different clothes.
  final bool unusable;

  bool get isEmpty => candidates.isEmpty && error == null;
}

/// Finds and queues records the library does not hold.
abstract interface class DownloadSource {
  DownloadSourceKind get kind;

  /// Searches and queues the obvious answer if there is one.
  Future<AcquireOutcome> queueBest(CatalogRelease release);

  /// Searches without adding anything.
  Future<AcquireOutcome> find(CatalogRelease release);

  /// Queues one specific result the user picked. Returns an error, or null.
  Future<String?> add(AcquireCandidate candidate);

  /// The search string for a release.
  ///
  /// **Built from MusicBrainz's structured fields, never from what was typed.**
  /// A raw search string finds names containing it, which for "ok computer"
  /// includes tribute albums, karaoke versions and an unrelated record by
  /// someone else. Artist plus album title is what identifies the thing.
  ///
  /// The year is deliberately absent even though it is known: names carry it
  /// inconsistently, perhaps half of them, so requiring it halves the results
  /// for no gain in correctness. It earns its keep in ranking instead, where a
  /// name that does contain the right year scores up and one that does not is
  /// merely not scored up.
  static String queryFor(CatalogRelease release) =>
      '${release.artist} ${release.title}'.trim();
}

/// One thing arriving, as the Downloads screen sees it.
///
/// A torrent on one source and a folder from one peer on the other. Both are
/// "the record I asked for, on its way", which is the only question that screen
/// answers.
class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.name,
    required this.progress,
    required this.sizeBytes,
    required this.isComplete,
    required this.isFailed,
    this.rateBytes = 0,
    this.detail,
  });

  /// Stable for the life of the download, and unique across the list. Used to
  /// remember which completions have already been reported, so a finished item
  /// that stays in the list does not ask Plex to rescan on every poll.
  final String id;

  final String name;

  /// 0.0 to 1.0.
  final double progress;

  final int sizeBytes;
  final int rateBytes;
  final bool isComplete;
  final bool isFailed;

  /// Whatever the source wants to say when this has gone wrong, in its own
  /// words. Shown only on failure, where a generic message would be useless.
  final String? detail;
}

extension TorrentAsJob on QbitTorrent {
  /// The hash is qBittorrent's own identity for a torrent and survives
  /// restarts, so a completion reported once stays reported.
  DownloadJob get asJob => DownloadJob(
    id: hash,
    name: name,
    progress: progress,
    sizeBytes: sizeBytes,
    rateBytes: downloadRateBytes,
    isComplete: isComplete,
    isFailed: isFailed,
    detail: isFailed ? state : null,
  );
}

extension SlskdDownloadAsJob on SlskdDownload {
  /// **Keyed on the peer and the folder together.** Neither alone is unique:
  /// two people can share the same album, and one person can be sending two
  /// different records at once. slskd's own per-file transfer ids are no use
  /// here because a job is the whole folder.
  DownloadJob get asJob => DownloadJob(
    id: '$username/$directory',
    name: name,
    progress: progress,
    sizeBytes: sizeBytes,
    rateBytes: rateBytes,
    isComplete: isComplete,
    isFailed: isFailed,
    detail: isFailed ? 'from $username' : null,
  );
}

/// Bytes as something readable. Shared by both candidates and the downloads
/// screen.
String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).round()} MB';
  }
  return '${(bytes / 1024).round()} KB';
}
