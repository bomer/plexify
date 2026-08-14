import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_models.dart';
import '../../core/catalog/listenbrainz_client.dart';
import 'catalog_artwork.dart';
import 'download_sheet.dart';

/// One record you do not have, with the button that queues it.
///
/// **Shared rather than copied**, because this widget carries the compromise the
/// whole acquisition flow is built on: tap queues the obvious answer and only
/// the obvious answer, long press opens the full list of hits. Both go through
/// the same search, and the difference is purely whether a confident result is
/// added without asking. Two copies would eventually disagree about that, and
/// the one that drifts is the one that queues the wrong album.
///
/// Used from the missing-albums grid on a library artist and from the
/// discography of an artist the library has never heard of. Those two screens
/// answer very different questions and this is the one thing they share.
class CatalogReleaseCard extends ConsumerWidget {
  const CatalogReleaseCard({
    required this.release,
    this.owned = false,
    this.popularity,
    this.peakListens,
    super.key,
  });

  final CatalogRelease release;

  /// How much this record is listened to, when ListenBrainz knew.
  final ReleasePopularity? popularity;

  /// The listen count of the **most-listened record in the same discography**.
  ///
  /// **The bar is relative to this, and that is the whole design.** Fifty
  /// thousand listens is a monstrous hit for an obscure producer and a rounding
  /// error for Radiohead, so a globally scaled bar would draw every page for a
  /// small artist as uniformly empty and every page for a large one as
  /// uniformly full, which answers a question nobody asked. What is wanted is
  /// "which of *these* are the ones people love", and that is only ever
  /// relative to the row it is in.
  ///
  /// The absolute figure is still printed, because it is the thing that says
  /// whether an artist is heard by thousands or by dozens, which the bar
  /// deliberately hides.
  final int? peakListens;

  /// Whether the library already holds this record.
  ///
  /// Always false on the missing grid, which by construction only lists things
  /// that are absent. It exists for the catalog artist screen, where an artist
  /// arrived precisely by *not* matching a library name, and Plex spelling them
  /// differently is exactly how you come to own some of their records anyway.
  /// Showing those as downloadable would offer to fetch what is already there.
  final bool owned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      // Long press opens the full list of search hits, tap queues the obvious
      // one. Both go through the same search; the difference is only whether a
      // confident result is added without asking. See `acquire`.
      onTap: owned ? null : () => acquire(context, ref, release),
      onLongPress: owned ? null : () => showAcquireSheet(context, ref, release),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  // Dimmed, so a grid of records you own and a grid of records
                  // you do not are distinguishable at a glance rather than by
                  // reading the heading above them. Undimmed when it *is*
                  // owned, which is the same signal read the other way round.
                  child: Opacity(
                    opacity: owned ? 1 : 0.55,
                    child: CatalogArtwork(mbid: release.mbid),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: owned
                        ? _OwnedBadge(theme: theme)
                        : Material(
                            color: theme.colorScheme.primaryContainer,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => acquire(context, ref, release),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.download,
                                  size: 18,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            release.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            [
              if (release.year != null) '${release.year}',
              if (release.kind == ReleaseKind.ep) 'EP',
              if (owned) 'in your library',
              if (popularity?.isKnown ?? false)
                '${_short(popularity!.listens)} plays',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: owned
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_share case final share?) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// This record's listens as a fraction of the biggest in its own discography,
/// or null when there is nothing to compare against.
///
/// Null rather than zero when the peak is zero or missing: a row of empty bars
/// says "nobody listens to any of this", which is a claim, whereas no bars at
/// all correctly says nothing. Dividing by a zero peak is the obvious way to
/// get that backwards.
extension on CatalogReleaseCard {
  double? get _share {
    final listens = popularity?.listens;
    final peak = peakListens;
    if (listens == null || peak == null || peak <= 0) return null;
    return (listens / peak).clamp(0.0, 1.0);
  }
}

/// Listen counts as something readable at the size of a card subtitle.
String _short(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

/// Sits where the download button would be, so the two states read the same way
/// at a glance rather than one of them simply lacking a control.
class _OwnedBadge extends StatelessWidget {
  const _OwnedBadge({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Already in your library',
    child: Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          Icons.check,
          size: 18,
          color: theme.colorScheme.primary,
        ),
      ),
    ),
  );
}
