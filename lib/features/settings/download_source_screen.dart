import 'package:flutter/material.dart';

import '../../core/acquire/download_source.dart';
import 'qbittorrent_screen.dart';
import 'slskd_screen.dart';

/// Opens whichever source's settings are wanted.
///
/// A dispatcher rather than one combined screen, because the two have almost
/// nothing in common past having an address field: one needs a username and a
/// password and explains a CSRF trap, the other needs an API key and explains
/// where downloads have to land. Merging them would mean a screen half of which
/// is always irrelevant.
///
/// It exists so callers that only know a [DownloadSourceKind], like the "not
/// set up yet" snackbar, can send someone to the right place without a switch
/// of their own.
class DownloadSourceScreen extends StatelessWidget {
  const DownloadSourceScreen({super.key, required this.kind});

  final DownloadSourceKind kind;

  @override
  Widget build(BuildContext context) => switch (kind) {
    DownloadSourceKind.qbittorrent => const QbittorrentScreen(),
    DownloadSourceKind.soulseek => const SlskdScreen(),
  };
}
