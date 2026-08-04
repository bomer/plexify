import 'package:flutter/material.dart';

import '../../core/plex/plex_models.dart';
import 'artist_index.dart';
import 'artwork.dart';

/// Alphabetical artist list with an A–Z rail.
///
/// Row heights are fixed so a letter's scroll offset can be worked out by
/// arithmetic. That is the whole reason this does not need a positioned-list
/// package: with a header and a row height known up front, jumping to "R" is a
/// sum, not a search.
class ArtistList extends StatefulWidget {
  const ArtistList({required this.artists, required this.onOpen, super.key});

  final List<PlexArtist> artists;
  final void Function(PlexArtist) onOpen;

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  static const _rowHeight = 60.0;
  static const _headerHeight = 34.0;

  final _controller = ScrollController();

  /// The letter being dragged over, shown as a bubble. Null when not dragging.
  String? _touchedBucket;

  late ArtistIndex _index;

  @override
  void initState() {
    super.initState();
    _index = ArtistIndex.from(widget.artists);
  }

  @override
  void didUpdateWidget(ArtistList old) {
    super.didUpdateWidget(old);
    // Rebuilt rather than diffed: sync writes land as whole new lists, and
    // sorting a few thousand rows is far cheaper than the frame drawing them.
    if (!identical(old.artists, widget.artists)) {
      _index = ArtistIndex.from(widget.artists);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scroll offset of the row at [index], counting the headers above it.
  double _offsetOf(int index) {
    var headers = 0;
    for (final start in _index.bucketStart.values) {
      if (start <= index) headers++;
    }
    return index * _rowHeight + headers * _headerHeight;
  }

  void _jumpTo(String bucket) {
    final start = _index.bucketStart[bucket];
    if (start == null || !_controller.hasClients) return;

    // The header belongs on screen with its first artist, so aim slightly above
    // the row itself.
    final target = (_offsetOf(start) - _headerHeight).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.jumpTo(target);
  }

  void _handleRailTouch(Offset local, double railHeight) {
    if (_index.buckets.isEmpty) return;
    final slot = (local.dy / railHeight * _index.buckets.length).floor();
    final bucket = _index.buckets[slot.clamp(0, _index.buckets.length - 1)];
    if (bucket == _touchedBucket) return;

    setState(() => _touchedBucket = bucket);
    _jumpTo(bucket);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        ListView.builder(
          controller: _controller,
          // Room for the rail, so a long artist name never runs under it.
          padding: const EdgeInsets.only(right: 28),
          itemCount: _index.artists.length,
          itemBuilder: (context, i) {
            final artist = _index.artists[i];
            final row = SizedBox(
              height: _rowHeight,
              child: ListTile(
                leading: ClipOval(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Artwork(
                      thumb: artist.thumb,
                      size: 100,
                      icon: Icons.person,
                    ),
                  ),
                ),
                title: Text(
                  artist.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                onTap: () => widget.onOpen(artist),
              ),
            );

            if (!_index.startsBucket(i)) return row;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: _headerHeight,
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    _index.bucketAt(i),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                row,
              ],
            );
          },
        ),

        Positioned(
          top: 4,
          bottom: 4,
          right: 0,
          width: 28,
          child: _Rail(
            buckets: _index.buckets,
            active: _touchedBucket,
            onTouch: _handleRailTouch,
            onRelease: () => setState(() => _touchedBucket = null),
          ),
        ),

        if (_touchedBucket != null)
          Positioned(
            right: 36,
            top: 0,
            bottom: 0,
            child: Center(
              child: Material(
                color: theme.colorScheme.primary,
                shape: const CircleBorder(),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: Text(
                      _touchedBucket!,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The A–Z strip down the right edge.
///
/// Only letters that actually have artists are drawn, so every target does
/// something — a rail full of dead letters is worse than a short one.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.buckets,
    required this.active,
    required this.onTouch,
    required this.onRelease,
  });

  final List<String> buckets;
  final String? active;
  final void Function(Offset local, double height) onTouch;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (buckets.length < 2) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onTouch(d.localPosition, height),
          onTapUp: (_) => onRelease(),
          onTapCancel: onRelease,
          onVerticalDragStart: (d) => onTouch(d.localPosition, height),
          onVerticalDragUpdate: (d) => onTouch(d.localPosition, height),
          onVerticalDragEnd: (_) => onRelease(),
          onVerticalDragCancel: onRelease,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final bucket in buckets)
                Text(
                  bucket,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: bucket == active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: bucket == active ? FontWeight.bold : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
