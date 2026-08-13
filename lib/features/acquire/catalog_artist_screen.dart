import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/catalog_matcher.dart';
import '../../core/catalog/catalog_models.dart';
import '../../core/providers.dart';
import 'catalog_release_card.dart';

/// The discography of an artist the library has never heard of.
///
/// **Deliberately not a variant of `ArtistDetailScreen`.** That screen plays
/// albums, lists tracks, shows stars and reads a `ratingKey`, and none of those
/// exist here: there is nothing to play, nothing to rate, and the identifier is
/// an MBID that means nothing to Plex. This is the same reasoning already
/// written at the top of `catalog_models.dart`, that a catalog release is not a
/// [PlexAlbum] with its fields nulled out, applied one level up.
///
/// Albums and EPs only, matching the missing-albums grid, and for the reason
/// recorded on [CatalogRelease.isPrimaryWork]: a well-catalogued artist has
/// three or four times as many compilations, live records and singles as
/// albums, and listing them turns a discography into a wall nobody reads.
class CatalogArtistScreen extends ConsumerWidget {
  const CatalogArtistScreen({required this.artist, super.key});

  final CatalogArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final discography = ref.watch(catalogDiscographyProvider(artist.mbid));
    final owned = ref.watch(ownedIndexProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: discography.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          icon: Icons.cloud_off,
          title: 'Could not reach MusicBrainz',
          detail:
              'Your own library is unaffected and still browsable from the '
              'Library tab.',
        ),
        data: (data) {
          final releases = [
            for (final release in data.releases)
              if (release.isPrimaryWork) release,
          ];

          if (releases.isEmpty) {
            return _Message(
              icon: Icons.album_outlined,
              title: 'Nothing listed for ${artist.name}',
              // Stated rather than left blank. "This artist released no albums"
              // and "MusicBrainz has them under a different entry" look
              // identical from here, and only one is worth acting on.
              detail:
                  'MusicBrainz has no albums or EPs under this entry. '
                  'Compilations and singles are not listed here, but they are '
                  'still findable through search.',
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    _summary(releases, owned),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        childAspectRatio: 0.66,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                  itemCount: releases.length,
                  itemBuilder: (context, i) => CatalogReleaseCard(
                    release: releases[i],
                    // **Not decoration.** This artist got here by *not*
                    // matching a library name, and Plex spelling them
                    // differently is exactly how you come to own some of their
                    // records anyway. Without this the page offers to download
                    // things already on the shelf.
                    owned: owned?.owns(releases[i]) ?? false,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Names the disambiguation when MusicBrainz has one, because "Nirvana" and
  /// "Genesis" each match several real artists and the wrong one presents as a
  /// page of albums this person never made.
  String _summary(List<CatalogRelease> releases, OwnedIndex? owned) {
    final held = owned == null ? 0 : releases.where(owned.owns).length;

    final counts = held > 0
        ? '${releases.length} albums and EPs, $held already yours'
        : '${releases.length} albums and EPs';

    final note = artist.disambiguation;
    return note == null || note.isEmpty ? counts : '$counts · $note';
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
