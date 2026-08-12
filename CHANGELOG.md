# Changelog

What changed in each release, written for someone deciding whether to update rather than for
someone reading the diff. The diff is in the commit log.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[semver](https://semver.org/), and while the major version is 0 the releases are marked as
prereleases on GitHub, because that is what they are.

**`tool/release.ps1` reads this file.** It publishes the section matching `version:` in
`pubspec.yaml` as the release notes and refuses to run if there is no such section, so a
release cannot go out with nothing said about it.

**Write entries under `Unreleased` as changes land, not at release time.** Reconstructing
this from thirty commits afterwards is how things get missed, and the commits that most
deserve a line are the ones least likely to be remembered a fortnight later.

Two things do not belong here, and leaving them out is what keeps it readable:

- **Anything a user cannot see.** Refactors, test changes, tooling. The audience is someone
  deciding whether to update.
- **A bug introduced and fixed before either shipped.** It never existed for anyone, so
  listing it under Fixed invents a problem the release did not have.

## [Unreleased]

### Added

- Artist radio. A **Radio** button on any artist, album and in the Now Playing header builds a
  queue from that artist plus the artists Plex considers similar, alternating between them
  rather than playing one discography after another. On a phone, long-pressing a track offers
  the same. The tracks come from your own library, so a station starts instantly and works
  offline.
- Playback keeps going when a queue ends, continuing with artists similar to the one that was
  playing. The next tracks are queued a few songs before the end, so it joins without a gap.
  There is a switch under Settings, Playback to turn it off.

### Changed

- "Jump back in" follows you between devices and survives a reinstall. It reads the server's
  own play history as well as this device's, so a new phone has a useful shelf on first login
  rather than an empty one. Playlists are still local only: Plex is never told which playlist
  a track came from.
- Home shows the artist rows Plex publishes as well as the album ones, including its own
  "Recently Played Music", which is correct across devices from the moment you sign in.
- Favourites sits above the recommendations on Home, and is ordered newest first within a
  star rating rather than alphabetically. Most favourites end up at the same four or five
  stars, so an alphabetical tiebreak showed the same handful of artists for ever.
- Home's discovery rows come from Plex itself now. Instead of three rows this app worked out
  on its own, it shows whatever the server publishes for the library, under the server's own
  titles: more by an artist, more in a genre, most played in a month, top albums from a
  decade, and whatever a later Plex adds. The three hand-made ones are gone.
- Playlist thumbnails in the sidebar are larger, with the track count under the name. A
  mosaic at the old size was a colour swatch rather than a picture of anything.
- Body text is a point larger and titles are semibold, so a name and the detail under it are
  no longer the same thing at two sizes.
- Primary text is a true neutral. It kept a faint tint from the accent colour while the
  background behind it had already lost one.

### Fixed

- A "most played this month" row appears on Home. The one in 0.9.0 never did, on any server:
  it asked Plex for play history in a way that answers with an empty result rather than an
  error. Plex's own version of the row replaces it, so it works now for a different reason
  than the one that was fixed.
- "Recently added" no longer appears twice on Home, once from the cache and once from Plex.
  The row that was meant to suppress the duplicate could never match it.
- The discovery probe can say *why* play history is empty rather than only that it is. It
  asks the same question five ways, and an empty answer from all of them is a different
  problem from an empty answer from only the one the app uses.

## [0.9.0] - 2026-08-10

First release. Everything below is new, so it is grouped by what it does rather than by
added, changed and fixed.

### Browsing and search

- Plex PIN sign-in, so no password is handled by the app. Server discovery races the LAN
  address, the remote one and the plex.tv relay and keeps whichever answers first, and
  re-races when the network moves.
- Artists with an A to Z jump rail, albums sortable by added date, title or artist with a
  favourites filter, and playlists sortable by recent or by name.
- Search runs against the local cache on every keystroke and merges Plex's own results in
  behind it, so an album added minutes ago is findable before any sync has stored it.
- Browsing reads from a local SQLite cache and works with the server unreachable.

### Home

- Jump back in, Recently added and Favourites.
- Four discovery rows: More by the artist you played last, Most played in a month counted
  from the server's play history, More in a genre that changes daily, and Buried treasure for
  albums nothing has ever played.

### Playback

- Gapless playback with a queue that shuffles, repeats, reorders and prunes.
- Desktop transport bar with scrubbing, shuffle and repeat, a queue button and volume.
- Windows media keys. Android background playback, lock screen controls and a notification.
- The session is restored on launch, paused and at the position it had reached.
- Now Playing, album, artist and playlist pages take a colour out of the artwork and wash it
  behind the page.

### Plex

- Plays reported back through `/:/timeline` and `/:/scrobble`, so history stays in one place.
- Star ratings on albums, artists and tracks, syncing both ways.
- Three sync mechanisms: a websocket delivering changes as Plex finishes scanning them, a 30
  second poll on the section clocks, and a slower unfiltered sweep for edits that move no
  timestamp at all. Pull to refresh asks Plex to rescan and then pulls the result.
- Reconnects when the network changes or requests stop arriving, and rebuilds the playing
  queue in place at the position it had reached.

### Quality and storage

- Direct play on the LAN, transcode over mobile data, overridable per connection. There is no
  bitrate control because Plex's music transcoder does not have one, which was measured
  rather than assumed.
- Artwork cached on both platforms, audio cached on mobile, both bounded and configurable.

### Albums you do not own

Off by default; one switch enables both halves.

- A "not in your library" tier under search and a missing albums grid on every artist page,
  both from MusicBrainz.
- One click hands off to qBittorrent with `category=Music`. Nothing is renamed or
  post-processed, and the library refreshes itself when a download lands.
- A result is only queued unasked when its filename names this artist and this album. Seeder
  count measures popularity, never correctness.

### Diagnostics

- A sync status screen reporting which of the three sync mechanisms is working, alongside
  probes for the transcode endpoint, the delta filter and what the server offers Home.

### Known limitations

- Playlists are read-only.
- Only the first music library on the server is synced. Sync status says when there is more
  than one.
- Favourite tracks have no view of their own; favourites are filters on artists and albums.
- The audio cache is mobile only. `LockCachingAudioSource` renames a file it still holds
  open, which Windows forbids.
