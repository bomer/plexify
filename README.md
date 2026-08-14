# Plexify

A fast, clean and simple music client for a Plex library. Windows desktop and Android, one
codebase.

Built because Plexamp's UI is basically just a mobile experience in a desktop window. I wanted
something more akin to Spotify: playlists down the left, easy jumping between them, searching,
and moving between "now playing" and "finding something else" without losing your place. Plex
stays the source of truth and your plays filter back, with transcoding handled on mobile.

This was coded entirely with Claude (and potentially other AI agents in future) to test their
capability in building custom software for me.

As a developer I really wanted a better experience, but it would have taken me weeks to learn
Dart and weeks more to build. I'm a bit worried it did too much work under the hood handling
streams, and that might make its own issues. We'll find out.

![Plexify on Windows](https://github.com/bomer/plexify/blob/main/docs/windows.png?raw=true)

## What it does

**Browsing and search**

- Signs in with Plex's PIN flow, so no password is ever handled by the app. Server discovery
  races the LAN address, the remote one and the relay, and keeps whichever answers first.
- Artists with an A to Z jump rail, albums sortable by added date, title or artist, and
  playlists sortable by recent or by name with smart playlists grouped first.
- One search box, three tiers: the local cache on every keystroke, Plex's own search merged
  in behind it, and optionally records you do not own at all.
- Everything renders from a local SQLite cache, so browsing is instant and works with the
  server unreachable.

**Home**

- Jump back in, Recently added and Favourites.
- The rows Plex itself publishes for the library, under the server's own titles: more by an
  artist, more in a genre, most played in a month, top albums from a decade.
- Buried treasure, for albums nothing has ever played.

**Playback**

- Gapless playback with a queue you can shuffle, repeat, reorder and prune.
- A desktop transport bar with scrubbing, shuffle and repeat, a queue button and volume.
- Media keys on Windows. Background playback, lock screen controls and a notification on
  Android.
- What was playing comes back on the next launch, paused and at the right position.
- Now Playing lifts a colour out of the album art and washes it behind the page. Album,
  artist and playlist pages do the same.

**Radio**

- Artist radio from any artist, album, track or from Now Playing: that artist plus the ones
  Plex considers similar, alternating between them rather than playing one discography after
  another.
- Plex's own stations on Home, and playback that keeps going with similar music when a queue
  runs out.

**Plex is the source of truth**

- Plays are reported back, so history stays in one place whichever app you listened in.
- Star ratings on albums, artists and tracks sync both ways.
- Three sync mechanisms: a websocket that delivers a change the moment Plex finishes
  scanning it, a cheap 30 second poll, and a slower unfiltered sweep for edits that move no
  timestamp. Pull to refresh asks Plex to rescan and then pulls the result.
- Reconnects on its own when the network changes or requests stop arriving, and rebuilds the
  playing queue at the position it had reached.

**Quality and storage**

- Direct play at home, transcode over mobile data, overridable per connection.
- Artwork cached on both platforms and audio cached on mobile, both bounded and both with a
  budget you can set.

**Albums you do not own** (off by default, one switch)

- A "not in your library" tier under search and a missing albums grid on every artist page,
  both from MusicBrainz.
- Artists you own nothing by appear in that tier too. Open one and you get their discography,
  with anything you already have marked rather than offered, and each record marked with how
  much it is listened to relative to that artist's biggest, from ListenBrainz.
- Asking for an album queues it. Searches run one at a time in the background and the
  Downloads screen shows what is waiting, what arrived, and what failed with a retry.
- One click hands off to qBittorrent or to Soulseek, whichever you pick, and the library
  refreshes itself when the download lands. Soulseek needs
  [slskd](https://github.com/slskd/slskd) running somewhere; see
  [docs/SOULSEEK.md](docs/SOULSEEK.md).
- Nothing is queued for you unless the name actually matches the record, whichever source it
  came from.

**Diagnostics**

- A sync status screen that says which of the three mechanisms is working, plus probes for
  the transcode endpoint, the delta filter and what the server offers the Home screen.

## Requirements

- **Flutter** 3.44+
- **Visual Studio 2026** with Desktop development with C++, for the Windows target
- **Android SDK** 36 with cmdline-tools, for the Android target
- **Windows Developer Mode enabled** — Flutter needs symlink support to build with plugins.
  `start ms-settings:developers`. Builds fail without it.

Verify with `flutter doctor`; it should report no issues.

## Running

```
flutter run -d windows
flutter run -d android
```

Drift generates database code. After changing anything under `lib/core/db/`:

```
dart run build_runner build --delete-conflicting-outputs
```

## Putting a build on the phone

Two commands, in this order.

```
flutter build apk --release --target-platform android-arm64
```

```
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**`flutter install` does not build.** It pushes whatever APK is already on disk, so skipping
the first command silently installs a stale one.

**Test in release on Android, not debug.** Flutter injects the `INTERNET` permission into
debug manifests only, so a debug build hides manifest problems that break release entirely.

## Releasing

```
powershell -File tool/release.ps1
```

Builds both targets, tags the commit, and publishes a GitHub release with the Windows zip and
the Android APK attached. Needs the [GitHub CLI](https://cli.github.com/). To build the
artefacts without publishing anything, use `tool/package.ps1`.

It refuses to run rather than publishing something wrong: the tree must be clean and pushed,
the tag must not exist, and [CHANGELOG.md](CHANGELOG.md) must have a section for the version.
[tool/README.md](tool/README.md) covers signing, what each check is protecting against, and
why the keystore needs backing up.

## How it is put together

Feature-first. The UI never talks to Plex directly: it reads from a local SQLite cache (drift)
that a background sync keeps current, which is what makes browsing feel instant rather than
network-bound. State is Riverpod with no code generation, so the provider graph is readable
without understanding `build_runner`; drift's generated code is the only generated code in the
project. Secrets live in `flutter_secure_storage` (Android Keystore, Windows DPAPI), never in
`SharedPreferences`.

```
lib/
  core/     plex/ catalog/ qbit/ db/ audio/ source/
  features/ auth/ library/ search/ player/ radio/ acquire/
  shell/    navigation scaffold, sidebar, routing
```

## Documentation

| | |
|---|---|
| [.agent/PROJECT.md](.agent/PROJECT.md) | How a change reaches the screen, the twelve architecture invariants, code conventions, how the tests lie, and every trap already paid for. Start here before changing anything. |
| [docs/PLEX-API.md](docs/PLEX-API.md) | The Plex API as this app actually uses it: every endpoint, what is sent, and what will mislead you. Plex publishes no documentation, so several findings here came from building an instrument after guessing gave a wrong answer. |
| [docs/SOULSEEK.md](docs/SOULSEEK.md) | Downloading from Soulseek through slskd: why a daemon rather than the protocol, the endpoints, and the two things the app cannot check for you. |
| [docs/PLAN.md](docs/PLAN.md) | The original build plan: decisions, phases and known risks. |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each release. |
| [tool/README.md](tool/README.md) | Packaging, signing and the release script. |

## Out of scope for v1

Playlist editing (read-only), YouTube playback, explicit offline downloads, cross-device
handoff, Last.fm, iOS, multi-user, Cast.

Torrent *management* too. The Downloads screen is read-only: pausing, reprioritising and
deleting all exist perfectly well in qBittorrent's own interface, and a second copy here would
be one more thing to keep in step.
