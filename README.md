# Plexify

A fast, clean and simple music client for a Plex library. Windows desktop and Android, one codebase.

The full build plan — decisions, phases, API details and known risks — is in
[docs/PLAN.md](docs/PLAN.md). This README covers architecture and how to run things.

Built because Plexamp's UI basically just a mobile wrapped experience. I wanted something more
akin to Spotify with playlist on the left and easily jumping between playlists, searching, and
moving between "now playing" and "finding something else" without losing your place.
Plex is the source of truth and your plays filter back, whilst handling transcoding on Mobile.

This was built entirely with Claude (and potentially other AI Agents) to test their capability
in building custom software for me.

As a developer, I really wanted a better experience but it would have taken me weeks to learn
dart and this weeks to build. I'm a bit worried it did too much work under the hood handling
streams that it might make it's own issues. We'll find out.

## Requirements

- **Flutter** 3.44+ (`C:\Users\James\flutter-sdk\flutter`)
- **Visual Studio 2026** with Desktop development with C++ — Windows target
- **Android SDK** 36 with cmdline-tools — Android target
- **Windows Developer Mode enabled** — Flutter needs symlink support to build with plugins.
  `start ms-settings:developers`. Builds fail without it.

Verify with `flutter doctor` — it should report no issues.

## Running

```
flutter run -d windows
flutter run -d android
```

Drift generates database code. After changing anything under `lib/core/db/`:

```
dart run build_runner build --delete-conflicting-outputs
```

## Architecture

Feature-first. The UI never talks to Plex directly — it reads from a local SQLite cache
(drift) that a background sync keeps current. This is what makes browsing feel instant
rather than network-bound.

```
lib/
  core/
    plex/       Plex auth, server discovery, API client, models
    catalog/    MusicBrainz — albums you DON'T own, for search + acquisition
    qbit/       qBittorrent WebUI API client
    db/         drift schema: cached library, play history  [codegen]
    audio/      playback handler, queue, cache policy, quality policy
    source/     SourceProvider interface — the seam for future sources
  features/
    auth/       PIN link flow, server picker
    library/    artists, albums, playlists (read-only in v1)
    search/     unified search
    player/     now playing + mini player
    radio/      sonic radio + autoplay
    acquire/    qBittorrent search / add / monitor
  shell/        navigation scaffold, sidebar, routing
```

**State:** Riverpod, no code generation — providers are declared explicitly so the graph is
readable without understanding build*runner. (Drift \_does* use codegen; that's unavoidable
and is the only generated code in the project.)

**Storage:** drift (SQLite) for the library cache. `flutter_secure_storage` for the Plex
token and qBittorrent credentials — Android Keystore and Windows DPAPI respectively. Never
plain SharedPreferences for secrets.

### The two rules that matter

**1. The cache is additive, never authoritative about absence.**

Search queries the local database _and_ Plex in parallel, merging results. Detail views
render from cache instantly, then revalidate and patch in differences. The cache can only
ever make things appear _faster_ — it must never be the reason something appears missing.
Violating this reintroduces exactly the "I added it to Plex and it won't show up" problem
this app exists to avoid.

Sync has three tiers:

1. **Websocket push** — `/:/websockets/notifications` emits a `TimelineEntry` the moment
   Plex finishes scanning an item. Sub-second, and the primary mechanism.
2. **Cheap change detection** — `/library/sections` returns `updatedAt`/`scannedAt` per
   section in one tiny response. Polled every ~30s foreground and on resume/reconnect, to
   catch anything the websocket missed while backgrounded.
3. **Delta sync** — fetch only `updatedAt >= lastSync`, paginated. Never a full re-sync.

Deletions don't appear in an `updatedAt` delta, so a periodic ratingKey-set reconcile
handles those separately.

**2. Cache entries are keyed by `(trackId, qualityDecision)`, never `trackId` alone.**

Quality adapts to the network: direct-play the original on LAN, 320k AAC on cellular. If the
cache key ignored quality, a lossy copy cached on cellular would be served forever once
you're back on LAN — silently defeating the point of adaptive quality.

Note that `LockCachingAudioSource` caches progressive HTTP only, **not HLS**. Plex's
transcode endpoint offers both; we must use the progressive form or transcoded audio can't
be cached at all.

## Platform notes

**Android** — `audio_service` runs playback in a foreground service for background playback
and lock-screen controls. Requires the service and `POST_NOTIFICATIONS` permission declared
in `AndroidManifest.xml`.

**Windows** — `just_audio` has no native Windows backend; `just_audio_media_kit` (libmpv)
provides one and must be initialised at startup before any player is constructed.

## Out of scope for v1

Playlist editing (read-only), YouTube playback, explicit offline downloads, cross-device
handoff, Last.fm, iOS, multi-user, Cast.
