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

### Changed

- Playlist thumbnails in the sidebar are larger, with the track count under the name. A
  mosaic at the old size was a colour swatch rather than a picture of anything.

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
