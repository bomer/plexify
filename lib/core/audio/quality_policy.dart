import 'package:connectivity_plus/connectivity_plus.dart';

import '../plex/plex_server.dart';

/// Whether to stream a track's original file or Plex's transcode of it.
///
/// Binary rather than a bitrate to request: #8 measured that Plex's music
/// transcoder ignores every documented way of asking for less, settling at
/// ~235–242 kbps regardless of what is asked for. There is nothing to adapt
/// *to* — only whether transcoding happens at all — which is why no bitrate
/// appears anywhere in this file.
enum QualityDecision {
  /// Stream the file Media > Part points at, untouched.
  directPlay,

  /// Ask Plex's transcoder for whatever it produces.
  transcode;

  bool get isTranscode => this == QualityDecision.transcode;
}

/// Decides [QualityDecision] from three signals kept deliberately apart
/// rather than collapsed into one "at home" flag:
///
/// - **Connectivity** — what pipe *this device* is paying for right now. A
///   laptop tethered to a phone's hotspot reports as wifi and is still
///   metered; a hotel's wired connection is ethernet and may not be.
/// - **Server locality** — what pipe the request reaches the *server*
///   through. A relay connection is bandwidth-limited by Plex itself, on top
///   of whatever the local network is doing, so it transcodes regardless of
///   how this device is connected.
/// - **Source rate** — #8 also found transcoding has a floor: pushing a file
///   already at or below the transcoder's own output through it spends more
///   data for worse audio. Below that floor, direct play wins on any
///   connection; there is nothing to gain.
///
/// Stateless and cheap to call per track — nothing here is worth caching.
class QualityPolicy {
  const QualityPolicy();

  /// Plex's transcoder settles at ~235–242 kbps regardless of what is asked
  /// for (#8, confirmed against a real server — see PROJECT.md). A source at
  /// or below this has nothing to gain from transcoding and something to
  /// lose.
  static const worthTranscodingAboveKbps = 240;

  /// [sourceKbps] is `PlexTrack.sourceKbps` — null when the part size hasn't
  /// synced yet, which is treated as "nothing measured", not as a floor
  /// crossed.
  ///
  /// [override] is the escape hatch #43b's settings screen will wire up.
  /// Null means "decide automatically"; anything else always wins, skipping
  /// every other signal.
  QualityDecision decide({
    required List<ConnectivityResult> connectivity,
    required PlexServer server,
    required int? sourceKbps,
    QualityDecision? override,
  }) {
    if (override != null) return override;

    if (sourceKbps != null && sourceKbps <= worthTranscodingAboveKbps) {
      return QualityDecision.directPlay;
    }

    // Bandwidth-limited by Plex itself, regardless of what the local network
    // is doing.
    if (server.preferTranscode) return QualityDecision.transcode;

    // On the LAN the local network is not what's metered — direct play
    // regardless of how the OS reports connectivity.
    if (server.isLocal) return QualityDecision.directPlay;

    // Remote and not relayed: what matters now is what this device is paying
    // for, not how it reaches the server. Wifi or ethernet anywhere in the
    // report is enough — Android can report more than one transport at once
    // (e.g. wifi alongside a VPN), and the presence of either means the
    // traffic isn't riding on cellular.
    final onWifiOrEthernet = connectivity.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
    return onWifiOrEthernet
        ? QualityDecision.directPlay
        : QualityDecision.transcode;
  }
}
