import 'plex_identity.dart';

/// Which query parameter Plex honours when a music transcode is asked for a
/// bitrate.
///
/// Both names are cited for `/music/:/transcode/universal/start`, neither is
/// documented, and they are not interchangeable on every server version. The
/// spike in `transcode_probe.dart` settles it by measurement. Until then, code
/// that needs a bitrate names the one it is assuming rather than picking
/// silently — a transcode that quietly ignores the parameter looks identical to
/// one that honours it, right up until the cellular bill.
enum TranscodeBitrateParameter {
  musicBitrate('musicBitrate'),
  maxAudioBitrate('maxAudioBitrate');

  const TranscodeBitrateParameter(this.queryName);

  /// The literal query-string key.
  final String queryName;
}

/// One candidate set of transcode parameters.
///
/// `/music/:/transcode/universal/start` rejects requests it cannot form a
/// decision from, and the minimum it needs is not written down anywhere
/// trustworthy. Rather than guess once and find out a round trip later, the
/// probe walks these in order and reports which the server accepts — so the
/// answer arrives as a measurement with a name attached, not as folklore.
///
/// The [why] of each is the hypothesis it tests. When one works and the one
/// before it did not, the difference between them is the finding.
class TranscodeProfile {
  const TranscodeProfile(this.name, this.why, this.build);

  final String name;

  /// What this profile is testing, in one line.
  final String why;

  /// Parameters layered over the base set, given the app's identity.
  ///
  /// A function rather than a map because half of what is being tested *is*
  /// the identity, which is only known at runtime.
  final Map<String, String> Function(PlexIdentity identity) build;

  /// Only the parameters every write-up mentions.
  static final minimal = TranscodeProfile(
    'minimal',
    'The commonly cited parameters and nothing else.',
    (_) => {'protocol': 'http'},
  );

  /// The same, without `protocol`.
  ///
  /// `start.mp3` already says what the protocol is; naming it as well may be
  /// redundant, or may be contradictory enough to reject.
  static final noProtocol = TranscodeProfile(
    'no protocol',
    'Lets the .mp3 extension imply the protocol instead of stating it.',
    (_) => const {},
  );

  /// Adds everything Plex normally learns from `X-Plex-*` headers.
  ///
  /// This URL is handed to the audio engine, which does its own HTTP and sends
  /// none of our headers — so as far as the server is concerned the request
  /// arrives from a client that has declared nothing about itself. If a
  /// transcode decision needs to know what is asking, this is the profile that
  /// supplies it.
  static final identified = TranscodeProfile(
    'identified',
    'Carries the X-Plex-* identity in the query, since the audio engine '
        'cannot send it as headers.',
    (id) => {
      'protocol': 'http',
      'X-Plex-Product': PlexIdentity.product,
      'X-Plex-Version': PlexIdentity.version,
      'X-Plex-Platform': id.platform,
      'X-Plex-Device': id.platform,
      'X-Plex-Device-Name': id.deviceName,
      'X-Plex-Session-Identifier': id.sessionIdentifier,
    },
  );

  /// Permits a remux instead of insisting on a full re-encode.
  ///
  /// `directPlay=0` with `directStream=0` forbids every option but one. If the
  /// server treats that as a request it cannot satisfy rather than an
  /// instruction, this is the profile that shows it.
  static final directStreamed = TranscodeProfile(
    'direct stream allowed',
    'Same as identified, but permits a remux rather than forbidding '
        'everything except a full transcode.',
    (id) => {...identified.build(id), 'directStream': '1'},
  );

  /// What Plex's own web client sends, minus the video-only parameters.
  ///
  /// The heaviest candidate, and the one to fall back on if the leaner sets
  /// are rejected: whatever the server insists on, the web client is
  /// demonstrably sending it.
  static final webClient = TranscodeProfile(
    'web client',
    "Mirrors what Plex's own web client sends, including a decode profile.",
    (id) => {
      ...identified.build(id),
      'hasMDE': '1',
      'directStream': '1',
      'directStreamAudio': '1',
      'fastSeek': '1',
      'location': 'lan',
      'copyts': '1',
      'audioBoost': '100',
      'mediaBufferSize': '102400',
      // Tells the transcoder what this client can actually decode. Without a
      // profile the server has nothing to decide against.
      'X-Plex-Client-Profile-Extra':
          'add-transcode-target(type=musicProfile&context=streaming'
          '&protocol=http&container=mp3&audioCodec=mp3)',
    },
  );

  /// Tried in order, cheapest and most specific first.
  ///
  /// Ordering is the point: the first that works is the one to adopt, and
  /// every profile it beat is a parameter the server did not need.
  static final candidates = [
    minimal,
    noProtocol,
    identified,
    directStreamed,
    webClient,
  ];
}
