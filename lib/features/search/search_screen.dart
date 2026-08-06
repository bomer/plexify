import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_source.dart';
import '../../core/providers.dart';
import '../../shell/layout.dart';
import '../library/library_screen.dart' show openAlbum;
import '../library/artist_detail_screen.dart';
import '../library/artwork.dart';
import '../player/playing_indicator.dart';
import '../player/playback_controller.dart';

/// Search across the library, from the cache first.
///
/// Local results come from drift on every keystroke, which is what makes this
/// feel instant: no round trip, no spinner, no debounce on the part that
/// matters. The server is asked as well and merged in behind, because the
/// cache is additive and must never be the reason something appears missing.
/// An album added five minutes ago has to be findable.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Short enough to feel immediate, long enough that typing a word does not
    // fire a server request per letter. The local half is fast either way;
    // this is really about the round trip merged in behind it.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) ref.read(searchQueryProvider.notifier).state = value;
    });
    // Only to show or hide the clear button; results are driven by the
    // provider, not by this rebuild.
    setState(() {});
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    ref.read(searchQueryProvider.notifier).state = '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Artists, albums, tracks',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close), onPressed: _clear),
          ),
          onChanged: _onChanged,
        ),
      ),
      body: switch (query.trim().isEmpty) {
        true => const _Message(
          icon: Icons.search,
          title: 'Search your library',
          detail: 'Artists, albums and tracks, as you type.',
        ),
        false => results.when(
          // Deliberately not a spinner. The local half answers in
          // milliseconds, so flashing a loader between keystrokes reads as
          // slower than doing nothing; the previous results stay put until
          // the new ones arrive.
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const _Message(
            icon: Icons.error_outline,
            title: 'Search failed',
            detail: 'Your library is still browsable from the Library tab.',
          ),
          data: (data) => data.isEmpty
              ? _Message(
                  icon: Icons.search_off,
                  title: 'Nothing for "$query"',
                  detail:
                      'Albums you do not own yet arrive in a later pass '
                      '(#29).',
                )
              : _Results(results: data),
        ),
      },
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.results});

  final SearchResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final compact = isCompactLayout(context);

    return ListView(
      children: [
        if (results.artists.isNotEmpty) ...[
          _Heading(text: 'Artists', theme: theme),
          for (final artist in results.artists)
            ListTile(
              leading: _Thumb(thumb: artist.thumb, icon: Icons.person),
              title: Text(artist.title, maxLines: 1),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ArtistDetailScreen(artist: artist),
                ),
              ),
            ),
        ],
        if (results.albums.isNotEmpty) ...[
          _Heading(text: 'Albums', theme: theme),
          for (final album in results.albums)
            ListTile(
              leading: _Thumb(thumb: album.thumb, icon: Icons.album),
              title: Text(album.title, maxLines: 1),
              subtitle: Text(album.artist, maxLines: 1),
              onTap: () => openAlbum(context, album),
            ),
        ],
        if (results.tracks.isNotEmpty) ...[
          _Heading(text: 'Tracks', theme: theme),
          for (final track in results.tracks)
            ListTile(
              dense: compact,
              selected: isNowPlaying(ref, track.ratingKey),
              leading: isNowPlaying(ref, track.ratingKey)
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(child: PlayingIndicator(size: 22)),
                    )
                  : _Thumb(thumb: track.thumb, icon: Icons.music_note),
              title: Text(track.title, maxLines: 1),
              subtitle: Text(
                [
                  track.artist,
                  track.album,
                ].where((s) => s.isNotEmpty).join(' - '),
                maxLines: 1,
              ),
              enabled: track.isPlayable,
              // Plays the one track rather than queueing the results. A search
              // is a list of things that matched a string, not an album, and
              // playing on into the next match would be surprising.
              onTap: () => ref.read(playbackControllerProvider)?.playTracks(
                [track],
                source: track.albumRatingKey == null
                    ? null
                    : PlaybackSource(
                        PlaybackSourceKind.album,
                        track.albumRatingKey!,
                      ),
              ),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: theme.textTheme.titleSmall),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.thumb, required this.icon});

  final String? thumb;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      width: 44,
      height: 44,
      child: Artwork(thumb: thumb, size: 300, icon: icon),
    ),
  );
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
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
