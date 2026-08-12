import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';
import '../radio/radio_action.dart';
import 'rating_controller.dart';
import 'star_rating.dart';

/// Rates a single track from a sheet.
///
/// Track lists on narrow layouts have no room for a row of five stars — it
/// crowds out the title, which is what people are actually scanning for. Rating
/// still matters on the phone though, so it moves to a long press rather than
/// disappearing.
Future<void> showTrackRatingSheet(
  BuildContext context,
  WidgetRef ref,
  PlexTrack track,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track.title,
              style: Theme.of(sheetContext).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (track.artist.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                track.artist,
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Under the stars rather than above them, because rating is what
            // this sheet has always been for and a new action should not
            // displace the reason people open it.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.radio),
              title: const Text('Start radio'),
              subtitle: Text(
                track.artist.isEmpty
                    ? 'Music like this artist'
                    : 'Music like ${track.artist}',
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await startRadioForAlbum(context, ref, track.albumRatingKey);
              },
            ),
            const Divider(height: 24),
            Center(
              child: Consumer(
                builder: (context, ref, _) => StarRating(
                  // Read live so the sheet reflects a rating set moments ago
                  // rather than the snapshot the row was built from.
                  rating:
                      ref
                          .watch(trackRatingProvider(track.ratingKey))
                          .valueOrNull ??
                      track.userRating,
                  size: 34,
                  onRate: (stars) async {
                    final ok = await ref
                        .read(ratingControllerProvider)
                        ?.rateTrack(track, stars);
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    if (ok == false) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not save rating to Plex'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
