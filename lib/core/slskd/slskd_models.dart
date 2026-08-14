/// Data models for the slskd API v0.
///
/// Parsed the same defensive way the Plex and qBittorrent models are, and for
/// the same reason: fields come and go between releases, and a missing one
/// should cost a single value rather than throw away a whole result list.
///
/// **The thing to understand before reading any of this: Soulseek shares files,
/// not records.** A search answers with one response per *user*, each carrying
/// a flat list of whatever of theirs matched. There is no album object anywhere
/// in the protocol. An album is an inference this app makes, by noticing that
/// several files share a parent directory on one person's machine, and that is
/// what [SlskdFile.directory] exists for.
library;

/// Extensions this app will queue.
///
/// Everything else in a shared folder is cover art, a playlist, a log or a cue
/// sheet. They are excluded from the count that decides whether a directory
/// looks like a record, so a folder with two songs and six JPEGs is not
/// mistaken for an eight-track album.
const audioExtensions = {
  'flac',
  'mp3',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'wav',
  'ape',
  'alac',
  'wma',
  'aiff',
  'aif',
  'dsf',
  'dff',
  'mpc',
  'wv',
};

/// One file somebody is sharing.
class SlskdFile {
  const SlskdFile({
    required this.filename,
    required this.size,
    this.bitRate,
    this.lengthSeconds,
    this.extension,
  });

  /// The full path on the sharing peer's machine, which is what has to be sent
  /// back verbatim to download it.
  ///
  /// **Soulseek paths use backslashes**, whatever platform the peer is on, and
  /// this is the single easiest thing to get wrong in the whole integration.
  /// Splitting on `/` finds no separator at all, so every file in every folder
  /// collapses into one group named after the whole path, and the ranking then
  /// silently scores one enormous imaginary album instead of the real ones.
  /// Nothing throws and nothing looks broken.
  final String filename;

  final int size;

  /// Reported by the peer's client rather than guessed from the name, which is
  /// what makes it worth ranking on at all. Null on plenty of files: some
  /// clients do not send it, and it is absent for lossless.
  final int? bitRate;

  final int? lengthSeconds;

  /// Sent separately by slskd, but not always, and sometimes empty. [suffix]
  /// falls back to the filename so a missing one costs nothing.
  final String? extension;

  /// The lowercase extension, from whichever source has it.
  String get suffix {
    final given = extension?.trim().toLowerCase();
    if (given != null && given.isNotEmpty) {
      return given.startsWith('.') ? given.substring(1) : given;
    }
    final name = _name.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1);
  }

  bool get isAudio => audioExtensions.contains(suffix);

  /// The folder this file sits in, which is this app's stand-in for an album.
  ///
  /// Splits on backslash *and* forward slash. Backslash is what Soulseek
  /// actually sends; forward slash costs one extra character to accept and
  /// means a peer on a client that normalises paths does not silently produce
  /// one giant group.
  String get directory {
    final cut = _lastSeparator;
    return cut < 0 ? '' : filename.substring(0, cut);
  }

  /// The last path segment, for display.
  String get name => _name;

  String get _name {
    final cut = _lastSeparator;
    return cut < 0 ? filename : filename.substring(cut + 1);
  }

  int get _lastSeparator {
    final back = filename.lastIndexOf(r'\');
    final forward = filename.lastIndexOf('/');
    return back > forward ? back : forward;
  }

  factory SlskdFile.fromJson(Map<String, dynamic> json) => SlskdFile(
    filename: _str(json['filename']) ?? '',
    size: _int(json['size']) ?? 0,
    bitRate: _int(json['bitRate']),
    lengthSeconds: _int(json['length']),
    extension: _str(json['extension']),
  );
}

/// What one user answered with.
///
/// The three connection fields are the honest analogue of a torrent's seeder
/// count: they say whether a transfer will actually start, which matters more
/// than anything about the files themselves. A perfect rip behind a queue two
/// hundred deep is worse than a good one from somebody idle.
class SlskdResponse {
  const SlskdResponse({
    required this.username,
    required this.files,
    this.hasFreeUploadSlot = false,
    this.uploadSpeed = 0,
    this.queueLength = 0,
  });

  final String username;
  final List<SlskdFile> files;

  final bool hasFreeUploadSlot;

  /// Bytes per second, as the peer last reported it.
  final int uploadSpeed;

  final int queueLength;

  factory SlskdResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['files'];
    return SlskdResponse(
      username: _str(json['username']) ?? '',
      files: raw is List
          ? [
              for (final row in raw.whereType<Map<String, dynamic>>())
                SlskdFile.fromJson(row),
            ]
          : const [],
      hasFreeUploadSlot: json['hasFreeUploadSlot'] == true,
      uploadSpeed: _int(json['uploadSpeed']) ?? 0,
      queueLength: _int(json['queueLength']) ?? 0,
    );
  }
}

/// A search on the server.
///
/// Searches are asynchronous the same way qBittorrent's are: starting one
/// returns an id and responses accumulate until peers stop answering or the
/// timeout expires.
class SlskdSearch {
  const SlskdSearch({
    required this.id,
    required this.state,
    this.responseCount = 0,
    this.fileCount = 0,
  });

  final String id;

  /// slskd's own flag string, `InProgress` or `Completed, TimedOut` and
  /// several others. Kept raw and interpreted by [isComplete] rather than
  /// parsed into an enum, because the set grows between releases and an
  /// unrecognised state must not become an error.
  final String state;

  final int responseCount;
  final int fileCount;

  /// A search is done when slskd says `Completed`, however it ended.
  ///
  /// `Completed, TimedOut` is the *normal* ending, not a failure: a Soulseek
  /// search has no natural end, so slskd stops waiting after its timeout and
  /// keeps whatever arrived. Treating that as an error would discard every
  /// successful search.
  ///
  /// **Asked positively, and that is the whole point.** This was once
  /// `!contains('inprogress')`, which is subtly and expensively wrong: the
  /// states run `Requested` → `InProgress` → `Completed, …`, and the first poll
  /// lands within milliseconds of the POST while the state is still
  /// `Requested`. That does not contain `inprogress`, so it read as finished
  /// before the search had begun, the client fetched an empty response list and
  /// reported that nobody had the record, while slskd carried on and filled the
  /// search in perfectly. It presented as downloads failing at random, because
  /// occasionally the state had already flipped by the time the poll arrived.
  ///
  /// A negative check answers "yes" to every state it has never heard of. A
  /// positive one answers "not yet", which is the safe way round: the worst it
  /// costs is polling until the deadline.
  bool get isComplete => state.toLowerCase().contains('completed');

  factory SlskdSearch.fromJson(Map<String, dynamic> json) => SlskdSearch(
    id: _str(json['id']) ?? '',
    state: _str(json['state']) ?? '',
    responseCount: _int(json['responseCount']) ?? 0,
    fileCount: _int(json['fileCount']) ?? 0,
  );
}

/// One file being transferred.
class SlskdTransfer {
  const SlskdTransfer({
    required this.filename,
    required this.state,
    required this.size,
    this.bytesTransferred = 0,
    this.averageSpeed = 0,
  });

  final String filename;

  /// Another flag string: `Queued, Remotely`, `InProgress`,
  /// `Completed, Succeeded`, `Completed, Errored` and so on. Raw for the same
  /// reason as [SlskdSearch.state].
  final String state;

  final int size;
  final int bytesTransferred;
  final double averageSpeed;

  bool get isComplete => _has('completed') && _has('succeeded');

  /// Everything that means this file is not arriving.
  ///
  /// Cancelled counts. A transfer the peer refused or dropped is finished in
  /// the only sense that matters here, and showing it as still in progress
  /// would leave the Downloads screen waiting on something nobody is sending.
  bool get isFailed =>
      _has('errored') ||
      _has('cancelled') ||
      _has('timedout') ||
      _has('rejected');

  bool _has(String flag) =>
      state.toLowerCase().replaceAll(' ', '').contains(flag);

  factory SlskdTransfer.fromJson(Map<String, dynamic> json) => SlskdTransfer(
    filename: _str(json['filename']) ?? '',
    state: _str(json['state']) ?? '',
    size: _int(json['size']) ?? 0,
    bytesTransferred: _int(json['bytesTransferred']) ?? 0,
    averageSpeed: _double(json['averageSpeed']) ?? 0,
  );
}

/// A folder being downloaded from one peer, which is what this app calls a job.
///
/// **The unit the Downloads screen shows.** slskd tracks individual files, but
/// a record was queued as a folder and is only useful once all of it has
/// landed, so progress, failure and completion are all aggregated to this
/// level. A torrent is the equivalent thing on the other source.
class SlskdDownload {
  const SlskdDownload({
    required this.username,
    required this.directory,
    required this.files,
  });

  final String username;
  final String directory;
  final List<SlskdTransfer> files;

  /// The folder name alone, which is what a person recognises. The rest of the
  /// path is somebody else's directory structure and means nothing here.
  String get name {
    final back = directory.lastIndexOf(r'\');
    final forward = directory.lastIndexOf('/');
    final cut = back > forward ? back : forward;
    return cut < 0 ? directory : directory.substring(cut + 1);
  }

  int get sizeBytes => files.fold(0, (sum, f) => sum + f.size);
  int get transferredBytes => files.fold(0, (sum, f) => sum + f.bytesTransferred);

  double get progress {
    final total = sizeBytes;
    if (total <= 0) return 0;
    return (transferredBytes / total).clamp(0.0, 1.0);
  }

  /// Bytes per second across whatever is moving right now.
  int get rateBytes => files
      .where((f) => !f.isComplete && !f.isFailed)
      .fold(0, (sum, f) => sum + f.averageSpeed.round());

  /// **Every file, not any file.** A folder is done when the last track lands;
  /// reporting completion on the first would ask Plex to rescan a half-written
  /// album, which is exactly the state that gets a broken record into the
  /// library and then needs fixing by hand.
  bool get isComplete => files.isNotEmpty && files.every((f) => f.isComplete);

  /// One failure is enough. The folder will not be complete, and saying so is
  /// more useful than showing 90% forever.
  bool get isFailed => files.any((f) => f.isFailed);

  factory SlskdDownload.fromJson(String username, Map<String, dynamic> json) {
    final raw = json['files'];
    return SlskdDownload(
      username: username,
      directory: _str(json['directory']) ?? '',
      files: raw is List
          ? [
              for (final row in raw.whereType<Map<String, dynamic>>())
                SlskdTransfer.fromJson(row),
            ]
          : const [],
    );
  }
}

/// Why an slskd request failed, in terms the UI can act on.
///
/// The distinction worth carrying is [forbidden]. slskd answers **401 for a
/// wrong or missing API key and 403 when the key is right but the caller's
/// address falls outside the CIDR list configured against it**. Those need
/// different fixes and one of them is close to invisible: the key works from
/// the machine it was tested on and fails from the phone, or works everywhere
/// until a reverse proxy starts presenting its own address. Reporting both as
/// "could not sign in" would send the user to check a key that is perfectly
/// correct.
class SlskdException implements Exception {
  const SlskdException(
    this.message, {
    this.statusCode,
    this.unauthorized = false,
    this.forbidden = false,
  });

  final String message;
  final int? statusCode;
  final bool unauthorized;
  final bool forbidden;

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
