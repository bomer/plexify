# Plexify — task list

Working state for the build. Mirrors the in-session task list so progress survives
across sessions. See [docs/PLAN.md](../docs/PLAN.md) for the full design and rationale.

**Last updated:** 4 August 2026

**Status:** 12 complete · 1 in progress · 21 open

---

## Complete

| # | Task | Notes |
|---|---|---|
| 1 | Install Flutter SDK | 3.44.8 stable at `C:\Users\James\flutter-sdk\flutter` |
| 2 | VS C++ toolchain | Already present — VS 2026, no install needed |
| 3 | `flutter doctor` clean | Windows + Android both green |
| 4 | Scaffold project | `C:\dev\plexify`, app id `com.jamesotoole.plexify` |
| 5 | Plex PIN auth + server discovery | Live-verified. Sequential wave racing: LAN → remote → relay |
| 6 | Album list from Plex | Live-verified, artwork via photo transcoder |
| 7 | Direct-play audio | Live-verified on Windows and Android |
| 9 | Windows Developer Mode | Enabled |
| 11 | Live-verify vertical slice | Auth, browsing, playback confirmed against the real server |
| 12 | Routing so mini player is never covered | Nested `Navigator` inside shell; `PopScope` minimises instead of exiting |
| 14 | Android background playback | Verified on OPPO CPH2791 / Android 16 — see bugs below |

### Bugs found and fixed during #14

Worth keeping — all three were release-only or device-only and would have shipped:

1. **`INTERNET` missing from the main manifest.** Flutter only injects it into debug/profile
   manifests, so release builds had no network at all.
2. **`POST_NOTIFICATIONS` never requested.** `audio_service` declares the permission but never
   prompts. Now requested on first playback, never gating it.
3. **`androidStopForegroundOnPause: true`** deleted the notification the moment playback paused —
   controls vanished exactly when you'd reach for them.
4. **`audio_service` 0.18.19 throws on Android 13+.** It converts `MediaControl.stop` into a
   `PlaybackStateCompat.CustomAction` requiring a non-zero icon, resolves that icon by name
   against *our* package, gets `0`, and throws `IllegalArgumentException` — killing the entire
   notification. Removed that control. (Was **not** R8 shrinking; ruled out with `--no-shrink`.)

---

## In progress

### #13 — Now Playing overlay with seek
Reported live: tapping album art should open the player, and there is no seek control anywhere.

Build the full Now Playing view as an overlay that slides **over** the current screen without
unmounting it, so dismissing returns you exactly where you were mid-browse. Implemented as a
`Stack` layer inside the shell rather than a pushed route, to guarantee the page beneath stays
mounted.

Includes: large artwork, title/artist/album, seek bar with scrubbing and elapsed/remaining,
transport controls, upcoming queue. Add a thin progress indicator to the mini player too.

---

## Open

### Outstanding from Phase 1

**#8 — Transcode spike.** Establish working parameters for
`/music/:/transcode/universal/start` against the real server. Critically, confirm the
**progressive** form (`start.mp3`) works and is cacheable by `LockCachingAudioSource` — HLS
(`start.m3u8`) is **not**. Everything about remote and cellular listening depends on this, and it
is the least-documented part of the Plex API. If progressive cannot be made to work, escalate:
remote falls back to direct-play only. **Needs James present. Gates #23.**

### Phase 2 — data layer

**#15 — drift schema and codegen.** Artists, albums, tracks, playlists, play history, plus a
`sync_state` table holding `lastSyncAt` and per-section `updatedAt`/`scannedAt`. Index for fast
local search on normalised title and artist. Wire `drift_flutter` for Android + Windows.
**Gates #16–#19.**

**#16 — Paginated initial sync** *(needs #15)*. Full first-run sync via
`X-Plex-Container-Start`/`Size`. Background, with visible progress, browsable while it lands.
Resumable if interrupted. **Gates #20.**

**#17 — Websocket push sync** *(needs #15)*. Connect to `/:/websockets/notifications` using
`dart:io` `WebSocket.connect` (the `web_socket_channel` package was removed — not needed since we
don't target web). Handle `TimelineEntry` to delta-sync items the moment Plex finishes scanning,
plus delete events. Reconnect with backoff. **This is the primary sync mechanism** and the reason
new music appears in seconds.

**#18 — Change-detection poll and delta sync** *(needs #15)*. Poll `/library/sections` every ~30s
foreground, plus on resume and network reconnect — one tiny response. On change, delta-sync only
`updatedAt >= lastSync`. Never a full re-sync. Pull-to-refresh triggers
`/library/sections/{id}/refresh` **and** a delta sync.

**#19 — Deletion reconcile** *(needs #15)*. Deletions don't appear in an `updatedAt` delta, so the
cache accumulates ghosts that 404 on play. Periodically fetch the ratingKey set only and remove
local rows Plex no longer has.

**#20 — Switch UI to drift, additively** *(needs #16)*. Repoint providers at drift so browsing is
instant. **Critical invariant: the cache is additive, never authoritative about absence.** Detail
views render from cache then revalidate and patch; anything the server knows about must still
surface even if unsynced. Getting this wrong reintroduces the exact problem this app exists to
fix. **Gates #28.**

**#21 — Artwork disk cache.** Bounded, keyed by thumb path and size, LRU eviction, prefetch ahead
of scroll. Biggest perceived-performance win in the grid.

### Phase 3 — playback

**#22 — Queue controls.** Shuffle and repeat wired through `audio_service` so the lock screen
reflects them. Queue view with reorder and remove. Verify gapless **by ear** on a continuous
album — `setAudioSources` should give it, but it must be heard, not assumed.

**#23 — Adaptive quality policy** *(needs #8)*. LAN → direct play original. Remote wifi → bandwidth
probe, direct play if it holds, else 320k. Cellular → 320k AAC. Data-saver → 128k. Relay always
transcodes (`PlexServer.preferTranscode` already flags this). Apply on next track, not mid-track.
**Gates #24.**

**#24 — Audio disk cache** *(needs #23)*. `LockCachingAudioSource`, bounded LRU, ~2GB Android /
~10GB desktop, **fills on wifi/LAN only**. **The key must include the quality decision, not just
trackId** — otherwise a 320k copy cached on cellular is served forever once back on the LAN,
silently defeating adaptive quality. This layer later becomes explicit offline downloads.

**#25 — Timeline reporting and scrobbling.** `/:/timeline` during playback, `/:/scrobble` on
completion, so plays land in Plex's own history. The ratingKey is already carried in
`MediaItem.extras`.

### Phase 4 — UI shell

**#26 — Sidebar with recent playlists.** Home, Search, Library, with recent playlists directly
beneath so they're always one click away — a headline requirement. Collapses to bottom nav on
Android. Playlists read-only in v1.

**#27 — Home screen and browsing.** Recently played, recently added, jump back in. Artist detail
pages. Library by artist and album. Read-only playlist browsing.

### Phase 5 — search

**#28 — Instant local search** *(needs #20)*. drift-backed across artists, albums, tracks,
playlists, on every keystroke with no network round trip. Merged with `/hubs/search` so unsynced
server content still appears.

**#29 — MusicBrainz "Not in your library" tier.** Free, no API key, art from Cover Art Archive.
**Must**: descriptive `User-Agent` with contact info (generic agents get 503), debounced
single-flight queue (~1 req/sec limit), cached results. Local results always render first and
independently — MusicBrainz must never block searching your own library. **Gates #30, #33.**

**#30 — De-duplicate catalog results** *(needs #29)*. Filter owned albums out of the "Not in your
library" section, matching on MBID where Plex has one and normalised artist+title where it
doesn't. Get this wrong and every album you own appears twice.

### Phase 6 — radio

**#31 — Sonic radio and autoplay.** `/library/metadata/{ratingKey}/nearest?limit=50`. Autoplay
**on by default**: when the queue empties, seed radio from what just played (the
`onQueueExhausted` hook already exists in `PlexifyAudioHandler`). Surface a clear "sonic analysis
incomplete" state rather than silently returning nothing.
**Prerequisite: Plex sonic analysis must have been run — takes hours to days.**

### Phase 7 — acquisition

**#32 — qBittorrent client.** WebUI API v2. Native web form login: `POST /api/v2/auth/login`,
form-encoded, returns `SID` cookie — one layer, no HTTP Basic. **Two traps:** `Referer` or
`Origin` must exactly match the `Host` header including port, or you get unexplained 403s; and 403
*also* means "IP banned for too many failed logins", so a single attempt then explicit backoff —
a naive retry loop would get the phone banned by James's own server. **Gates #33.**

**#33 — Acquisition flow** *(needs #29, #32)*. From a "not in library" album: search qBittorrent
using **structured** MusicBrainz metadata (artist + album + year) rather than the raw typed string.
Rank by seeders and format. Add with `category=Music` so the existing automation routes it to the
Plex-watched folder — **no renaming or retagging needed**. Poll for progress, then
`/library/sections/{id}/refresh`. Warn if qBittorrent's search plugins aren't enabled.

### Phase 8 — release

**#34 — Packaging.** Signed release APK with a real keystore (currently debug signing). Windows
release bundle. Icons, first-run flow, settings screen (quality, cache size, autoplay,
qBittorrent). Keep the size guard: arm64 release is 20.2MB against a ~20MB expectation.

---

## Open decisions

- **Riverpod stays at 2.6.1.** 3.4.2 declares `test ^1.0.0` as a *runtime* dependency, which
  transitively pins `analyzer <13`, while `drift_dev` 2.34.x requires `analyzer ^13`. Mutually
  exclusive on Flutter 3.44. Revisit when upstream resolves.
- **Git author is `unknown`.** `user.name` is unset globally. Set it and the existing commits can
  be amended.
- **ColorOS battery killer.** `OplusHansManager` tracks the process. If playback dies over a long
  session, the fix is exempting Plexify from battery optimisation, not code.
