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
