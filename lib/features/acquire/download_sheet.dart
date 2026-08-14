import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/acquire/download_source.dart';
import '../../core/catalog/catalog_models.dart';
import '../../core/providers.dart';
import '../settings/download_source_screen.dart';
import 'downloads_screen.dart';

export '../../core/acquire/download_source.dart' show formatBytes;

/// Queues a record in one tap, and only when that is safe.
///
/// **The compromise this encodes.** "One click to download" is the thing worth
/// having on an artist page, and blindly adding the most popular search hit is
/// not a safe way to provide it: both sources match on names, so the top result
/// for an album is routinely a different record that shares a word. Popularity
/// and availability measure whether you can get a file, never whether it is the
/// right file.
///
/// So the button searches, and adds *only* if a result actually names this
/// artist and this album. When one does, it is queued and the snackbar says
/// what, with **Change** open beside it, because the user should be able to see
/// and undo a decision made for them. When none does, nothing is added and the
/// list opens instead. One tap in the common case, and never one tap away from
/// the wrong album.
///
/// Everything here reads [AcquireCandidate] and nothing here knows which server
/// produced it. That is the point: this screen was written once.
void acquire(BuildContext context, WidgetRef ref, CatalogRelease release) {
  final kind = ref.read(downloadSourceKindProvider);
  final added = ref.read(acquireQueueProvider).add(release);

  // **One message, and the previous one is dismissed first.**
  //
  // This used to search inline and hold a progress banner for the fifteen to
  // twenty-five seconds a Soulseek search takes. Snackbars queue, so asking for
  // three albums left six of them playing out one after another long after
  // their searches had finished, and you would sit watching "Searching, up to
  // 30 seconds" for something that finished a minute ago. Replacing rather than
  // enqueueing is what makes tapping four albums in a row read sensibly.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          added
              // Named rather than "added to queue", because after four taps the
              // useful question is which ones you already asked for.
              ? 'Looking for ${release.title} on ${kind.label}'
              : '${release.title} is already on the list',
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Downloads',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
          ),
        ),
      ),
    );
}

/// Fire-and-forget wrapper so a `SnackBarAction` can open the sheet.
void unawaitedSheet(
  BuildContext context,
  WidgetRef ref,
  CatalogRelease release, {
  AcquireOutcome? prefetched,
}) {
  showAcquireSheet(context, ref, release, prefetched: prefetched);
}

/// Shows every search hit, ranked, and adds whichever one is tapped.
Future<void> showAcquireSheet(
  BuildContext context,
  WidgetRef ref,
  CatalogRelease release, {
  AcquireOutcome? prefetched,
}) async {
  final controller = await ref.read(downloadSourceProvider.future);
  if (!context.mounted) return;
  if (controller == null) {
    _notConfigured(context, ref);
    return;
  }

  // Reused when the caller already searched, which is the whole point of
  // `prefetched`: opening the list after an automatic attempt must not run the
  // same twenty-second search a second time.
  final outcome =
      prefetched ??
      await _whileSearching(
        context,
        release,
        controller.kind,
        () => controller.find(release),
      );
  if (!context.mounted) return;

  if (outcome.candidates.isEmpty) {
    _report(
      context,
      outcome.error ??
          'No downloads found for ${release.artist} — ${release.title}',
      isError: outcome.error != null,
    );
    return;
  }

  // Held separately from the sheet's own context, which stops existing the
  // moment the sheet closes — reporting through it afterwards silently does
  // nothing, which is how "it opened the browser and said nothing" happened.
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ResultList(
      release: release,
      candidates: outcome.candidates,
      onPick: (picked) async {
        // Popped through the sheet's *own* context, which resolves to the
        // navigator the sheet was actually pushed on. Using the caller's would
        // pop the page underneath instead — see [_whileSearching].
        Navigator.of(sheetContext).pop();

        // A page cannot be queued, so tapping one opens it instead of
        // pretending. qBittorrent would accept the URL, answer `Ok.`, and fail
        // decoding HTML somewhere this app can never read, so a snackbar saying
        // "Queued" would be a lie with no way to find out it was one.
        //
        // Only torrents ever reach this: nothing Soulseek returns is a page.
        final page = picked.pageUrl;
        if (page != null) {
          await _openPage(messenger, page);
          return;
        }

        final error = await controller.add(picked);
        _show(
          messenger,
          error ?? 'Queued ${picked.title}',
          isError: error != null,
        );
      },
    ),
  );
}

/// Opens a result's own page in the system browser.
///
/// The useful thing to do with a link that is a page: the magnet is on the
/// other side of it, one click away, and copying it back is a job for a browser
/// rather than for a music player.
/// Takes a messenger rather than a context, because by the time this runs the
/// sheet that triggered it has already closed and its context is gone.
Future<void> _openPage(ScaffoldMessengerState messenger, String url) async {
  final uri = Uri.tryParse(url);
  final opened =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  _show(
    messenger,
    opened
        ? 'Opened the page. Copy the magnet link there, then add it in '
              'qBittorrent.'
        : 'Could not open $url',
    isError: !opened,
  );
}

/// Runs [work] while telling the user it is running, without a modal.
///
/// **This was a dialog, and the dialog was two bugs.**
///
/// It was dismissed with `Navigator.of(context).pop()`, where `context` belongs
/// to the page that started the search. `showDialog` pushes onto the **root**
/// navigator by default and `Navigator.of` resolves the **nested** one — this
/// app puts every page inside a per-tab navigator on purpose — so the pop took
/// the artist page off the stack and left the dialog spinning on top of the
/// album page underneath. Both halves of the report, from one line.
///
/// A snackbar has no navigator to get wrong, and it is the better answer
/// anyway: searching several trackers takes tens of seconds, and blocking the
/// whole screen for it means you cannot look at anything else meanwhile.
Future<AcquireOutcome> _whileSearching(
  BuildContext context,
  CatalogRelease release,
  DownloadSourceKind kind,
  Future<AcquireOutcome> Function() work,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final progress = messenger.showSnackBar(
    SnackBar(
      // Long enough to outlast the search's own timeout, then closed by hand.
      // Left to expire it would vanish mid-search and look like a failure.
      duration: const Duration(minutes: 2),
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(
            // Says how long, because the honest answer is "a while", and says
            // where, because with two possible sources "it found nothing" is a
            // different fact depending on which one was asked.
            child: Text(
              switch (kind) {
                // Several plugins across several trackers, and the slowest one
                // sets the pace.
                DownloadSourceKind.qbittorrent =>
                  'Searching trackers for ${release.title}, up to 30 seconds',
                // A Soulseek search has no natural end: peers answer whenever
                // they feel like it, so the server simply stops waiting.
                DownloadSourceKind.soulseek =>
                  'Asking Soulseek for ${release.title}, up to 30 seconds',
              },
            ),
          ),
        ],
      ),
    ),
  );

  try {
    return await work();
  } finally {
    progress.close();
  }
}

/// Names the source that is not set up, rather than saying "downloads are not
/// configured".
///
/// With two possible sources, the generic phrasing sends someone to check the
/// one they already filled in.
void _notConfigured(BuildContext context, WidgetRef ref) {
  final kind = ref.read(downloadSourceKindProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${kind.label} is not set up yet'),
      action: SnackBarAction(
        label: 'Settings',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DownloadSourceScreen(kind: kind),
          ),
        ),
      ),
    ),
  );
}

void _report(BuildContext context, String message, {bool isError = false}) {
  _show(
    ScaffoldMessenger.of(context),
    message,
    isError: isError,
    theme: Theme.of(context),
  );
}

/// The one place a message is put on screen.
///
/// Takes the messenger rather than a context so it still works after whatever
/// triggered it has been dismissed — a sheet's context is dead the instant the
/// sheet pops, and reporting through it does nothing at all, silently.
void _show(
  ScaffoldMessengerState messenger,
  String message, {
  bool isError = false,
  ThemeData? theme,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: isError ? 8 : 4),
        backgroundColor: isError ? theme?.colorScheme.errorContainer : null,
      ),
    );
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.release,
    required this.candidates,
    required this.onPick,
  });

  final CatalogRelease release;
  final List<AcquireCandidate> candidates;
  final ValueChanged<AcquireCandidate> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confident = candidates.where((c) => c.matchesRelease).length;
    final addable = candidates.where((c) => c.addable).length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                '${release.artist} — ${release.title}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                // Two different warnings, and the second is the one that had no
                // voice at all until now: a list full of pages looks exactly
                // like a list full of torrents, right up until nothing
                // downloads and only qBittorrent's log says why.
                addable == 0
                    ? 'None of these is a torrent, they are all pages. Tap one '
                          'to open it and copy the magnet.'
                    : confident == 0
                    // Said plainly rather than hidden. Every result here shares
                    // words with the album and none of them names it, which is
                    // exactly when a hasty tap costs a wrong download.
                    ? 'No result clearly names this album. Check the names.'
                    : '$confident of ${candidates.length} name this album · '
                          '$addable can be added directly',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: candidates.length,
                itemBuilder: (context, i) {
                  final candidate = candidates[i];
                  final readiness = candidate.readiness;

                  return ListTile(
                    // Readiness leads, because it decides whether tapping
                    // downloads anything at all, which matters more here than
                    // how well the name matches. A magnet and an idle peer are
                    // the same answer to the same question.
                    leading: Tooltip(
                      message: candidate.readinessTooltip,
                      child: Icon(
                        switch (readiness) {
                          AcquireReadiness.now => Icons.bolt,
                          AcquireReadiness.soon => Icons.schedule,
                          AcquireReadiness.unknown => Icons.link,
                          AcquireReadiness.never => Icons.open_in_new,
                        },
                        color: switch (readiness) {
                          AcquireReadiness.now => theme.colorScheme.primary,
                          AcquireReadiness.never => theme.colorScheme.error,
                          _ => theme.colorScheme.onSurfaceVariant,
                        },
                      ),
                    ),
                    title: Text(
                      candidate.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      candidate.subtitle,
                      style: readiness == AcquireReadiness.never
                          ? theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            )
                          : null,
                    ),
                    // Kept as a trailing mark rather than dropped: whether the
                    // name names this record is still the thing that stops you
                    // downloading a tribute album, it is just no longer the
                    // first question.
                    trailing: candidate.matchesRelease
                        ? Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                    onTap: () => onPick(candidate),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

}
