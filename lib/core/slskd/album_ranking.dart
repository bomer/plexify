/// Turns "these people are sharing files" into "this person has this record",
/// and decides whether any of it is good enough to queue without asking.
///
/// **The unit here is a folder on one peer's machine, and that is the whole
/// difference from torrent ranking.** A torrent is a record already; somebody
/// packaged it that way. Soulseek has no album object anywhere in the protocol,
/// so an album is an inference: several audio files sharing a parent directory
/// on one person's disk, in a folder whose path names the thing you asked for.
///
/// Like its torrent counterpart this is a pure function over a list, no client
/// and no futures and no state, and it is tested directly. Everything else in
/// the flow is plumbing whose failure is obvious; this one fails by quietly
/// downloading the wrong thing.
///
/// **Matching is done against the whole directory path, not the last folder.**
/// The near-universal layout is `...\Radiohead\Kid A\`, with the artist as the
/// parent, so matching the leaf alone would fail the artist half of every
/// single result. Taking the whole path also makes an important safety property
/// fall out for free: a peer who keeps every song loose in one `Music` folder
/// produces one group of four thousand files whose path names no album, so it
/// can never match and can never be queued. That is the correct outcome, and
/// discovering it by accident would have been expensive.
library;

import '../acquire/matching.dart';
import 'slskd_models.dart';

/// One peer's folder, scored.
class SlskdAlbum {
  const SlskdAlbum({
    required this.username,
    required this.directory,
    required this.files,
    required this.score,
    required this.matchesRelease,
    required this.format,
    required this.hasFreeUploadSlot,
    required this.queueLength,
    required this.uploadSpeed,
    this.bitRate,
  });

  final String username;

  /// The full path on the peer's machine, which is what has to go back to
  /// slskd verbatim.
  final String directory;

  /// Audio files only. Cover art, logs, cue sheets and playlists are dropped
  /// before this point, so [trackCount] means what it says.
  final List<SlskdFile> files;

  final double score;

  /// Whether the folder path actually names this record.
  ///
  /// The gate for queueing something without the user looking at it, and the
  /// same idea as its torrent equivalent: a search matches names, so the
  /// best-connected peer holding something whose folder shares one word with
  /// the album is not evidence of anything.
  final bool matchesRelease;

  final AudioFormat format;

  /// Whether a transfer would start now rather than joining a queue.
  ///
  /// **The honest analogue of seeder count.** It says nothing about the music
  /// and everything about whether you will ever hear it.
  final bool hasFreeUploadSlot;

  final int queueLength;

  /// Bytes per second, as the peer last reported it.
  final int uploadSpeed;

  /// The average reported bitrate across the folder, where any file reports
  /// one. Null for lossless and for peers whose client does not send it.
  final int? bitRate;

  int get trackCount => files.length;

  int get sizeBytes => files.fold(0, (sum, f) => sum + f.size);

  /// The folder alone, which is what a person recognises. The rest of the path
  /// is somebody else's directory structure.
  String get folderName {
    final back = directory.lastIndexOf(r'\');
    final forward = directory.lastIndexOf('/');
    final cut = back > forward ? back : forward;
    return cut < 0 ? directory : directory.substring(cut + 1);
  }

  /// Whether this is a plausible single record rather than a loose track or
  /// somebody's whole collection.
  ///
  /// Both ends matter. One or two files is a track somebody happens to have;
  /// eighty is a discography folder, or a genre dump, and queueing it would
  /// pull tens of gigabytes for a request to hear one album.
  bool get looksLikeAnAlbum => trackCount >= 3 && trackCount <= _maxTracks;

  static const _maxTracks = 50;
}

/// Ranks what came back for a specific record, best first.
List<SlskdAlbum> rankSlskdAlbums(
  Iterable<SlskdResponse> responses, {
  required String artist,
  required String album,
  int? year,
}) {
  final wantedArtist = significantTokens(artist);
  final wantedAlbum = significantTokens(album);

  final ranked = <SlskdAlbum>[
    for (final response in responses)
      ..._albumsIn(response, wantedArtist, wantedAlbum, year, album),
  ];

  ranked.sort((a, b) {
    // A confident match always outranks a loose one, however well connected
    // the loose one is. Availability measures whether you can get a file, never
    // whether it is the right file, and the best-connected peer matching one
    // word of an album title is routinely holding something else entirely.
    if (a.matchesRelease != b.matchesRelease) return a.matchesRelease ? -1 : 1;
    return b.score.compareTo(a.score);
  });
  return ranked;
}

/// The one folder worth queueing without asking, or null.
///
/// Deliberately strict, because the two mistakes do not cost the same. Refusing
/// to queue automatically costs one extra tap on a list that is already open.
/// Queueing the wrong thing puts files on the server, in the folder Plex
/// watches, under the album's name, and the first anyone knows of it is a
/// tribute record appearing in the library.
///
/// **No quality floor, deliberately.** A 128k rip can be chosen here when it is
/// the only confident name match, because the alternative is not getting the
/// record at all. Bitrate ranks; it never excludes.
SlskdAlbum? bestSlskdAlbum(List<SlskdAlbum> ranked) {
  if (ranked.isEmpty) return null;
  final best = ranked.first;

  if (!best.matchesRelease) return null;

  // A loose track or a whole discography. Both are still in the list to pick
  // by hand; neither is ever chosen for someone.
  if (!best.looksLikeAnAlbum) return null;

  // Somebody with no free slot and a long queue may never send anything, and a
  // snackbar saying "Queued" would be technically true and practically a lie.
  // A short queue is fine: that is an ordinary wait, not a wall.
  if (!best.hasFreeUploadSlot && best.queueLength > _acceptableQueue) {
    return null;
  }

  return best;
}

const _acceptableQueue = 10;

Iterable<SlskdAlbum> _albumsIn(
  SlskdResponse response,
  Set<String> wantedArtist,
  Set<String> wantedAlbum,
  int? year,
  String rawAlbum,
) {
  final byDirectory = <String, List<SlskdFile>>{};
  for (final file in response.files) {
    if (!file.isAudio) continue;
    byDirectory.putIfAbsent(file.directory, () => []).add(file);
  }

  return [
    for (final entry in byDirectory.entries)
      _score(response, entry.key, entry.value, wantedArtist, wantedAlbum, year,
          rawAlbum),
  ];
}

SlskdAlbum _score(
  SlskdResponse response,
  String directory,
  List<SlskdFile> files,
  Set<String> wantedArtist,
  Set<String> wantedAlbum,
  int? year,
  String rawAlbum,
) {
  final tokens = nameTokens(directory);
  final format = _formatOf(files);
  final bitRate = _averageBitRate(files);

  final named = namesRelease(
    tokens,
    wantedArtist: wantedArtist,
    wantedAlbum: wantedAlbum,
  );
  final unwanted = unwantedIn(tokens, album: rawAlbum);

  var score = 0.0;

  // Whether a transfer starts now or joins a queue is the single most useful
  // thing known about a peer, so it carries the most weight. Everything below
  // is about the files; this is about whether they ever arrive.
  if (response.hasFreeUploadSlot) score += 40;
  score -= 6 * log2(response.queueLength + 1);

  // Diminishing, like seeders. The gap between 20 KB/s and 200 decides whether
  // an album lands this evening; the gap between 2 MB/s and 20 decides nothing.
  score += 2 * log2(response.uploadSpeed ~/ 1024 + 1);

  // The same tiering as torrents: lossless above lossy, and the gap between two
  // lossy encodings is not worth a tier of its own.
  score += format.weight * 12;

  // **Where Soulseek can do something torrents cannot.** This is a real figure
  // reported by the peer's client rather than a number scraped out of a
  // filename, so it is worth ranking on. It only ever breaks ties within lossy:
  // small enough that it can never lift a good MP3 above a FLAC, and it
  // excludes nothing.
  if (format == AudioFormat.lossy && bitRate != null) {
    score += (bitRate.clamp(0, 320) / 40);
  }

  if (year != null && tokens.contains('$year')) score += 8;

  // A loose track rather than the record. Demoted rather than dropped, because
  // occasionally one file is genuinely all that is being asked for, and the
  // gate that stops it being queued for someone lives in [bestSlskdAlbum].
  if (files.length < 3) score -= 30;

  // Somebody's whole collection in one folder. Matches everything it contains
  // and is tens of gigabytes.
  if (files.length > SlskdAlbum._maxTracks) score -= 25;

  final isBundle =
      tokens.contains('discography') || tokens.contains('anthology');
  if (isBundle) score -= 25;

  score -= 40 * unwanted.length;

  return SlskdAlbum(
    username: response.username,
    directory: directory,
    files: files,
    score: score,
    // An unwanted word disqualifies rather than merely penalising, for the
    // reason already paid for on the torrent side: "Karaoke - OK Computer by
    // Radiohead" contains every word of both the artist and the album, so it
    // matches on tokens alone, and a well-connected one outranked a real rip
    // until this was a gate rather than a subtraction.
    matchesRelease: named && !isBundle && unwanted.isEmpty,
    format: format,
    hasFreeUploadSlot: response.hasFreeUploadSlot,
    queueLength: response.queueLength,
    uploadSpeed: response.uploadSpeed,
    bitRate: bitRate,
  );
}

/// The format of a folder, decided by what most of it is.
///
/// **Not `AudioFormat.detect` over every extension present**, which answers
/// lossless if *any* file is, so one stray `.wav` interlude would label an
/// entire MP3 rip as a lossless rip. The majority extension is what the folder
/// actually is.
AudioFormat _formatOf(List<SlskdFile> files) {
  final counts = <String, int>{};
  for (final file in files) {
    final suffix = file.suffix;
    if (suffix.isEmpty) continue;
    counts[suffix] = (counts[suffix] ?? 0) + 1;
  }
  if (counts.isEmpty) return AudioFormat.unknown;

  var winner = '';
  var most = 0;
  for (final entry in counts.entries) {
    if (entry.value > most) {
      most = entry.value;
      winner = entry.key;
    }
  }
  return AudioFormat.detect({winner});
}

/// The average reported bitrate, or null if nobody reported one.
///
/// Averaged rather than taken off the first file because a folder routinely
/// mixes a VBR rip's per-track figures, and one unusually quiet track's
/// bitrate is not the album's.
int? _averageBitRate(List<SlskdFile> files) {
  var total = 0;
  var counted = 0;
  for (final file in files) {
    final rate = file.bitRate;
    if (rate != null && rate > 0) {
      total += rate;
      counted++;
    }
  }
  return counted == 0 ? null : total ~/ counted;
}
