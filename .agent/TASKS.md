# Plexify — task list

Working state for the build. Mirrors the in-session task list so progress survives
across sessions. See [docs/PLAN.md](../docs/PLAN.md) for the design and rationale, and
[PROJECT.md](PROJECT.md) for environment, conventions and known traps.

**Last updated:** 4 August 2026

**Status:** 22 complete · 14 open · 119 tests passing

---

## Complete

| # | Task | Notes |
|---|---|---|
| 1 | Install Flutter SDK | 3.44.8 stable at `C:\Users\James\flutter-sdk\flutter` |
| 2 | VS C++ toolchain | Already present — VS 2026, no install needed |
| 3 | `flutter doctor` clean | Windows + Android both green |
| 4 | Scaffold project | `C:\dev\plexify`, app id `com.jamesotoole.plexify` |
| 5 | Plex PIN auth + discovery | Live-verified. Wave racing: LAN → remote → relay |
| 6 | Album list from Plex | Live-verified |
| 7 | Direct-play audio | Live-verified, Windows and Android |
| 9 | Windows Developer Mode | Enabled |
| 11 | Live-verify vertical slice | Auth, browsing, playback confirmed |
| 12 | Routing so mini player is never covered | Nested `Navigator`; `PopScope` minimises instead of exiting |
| 13 | Now Playing overlay with seek | Sibling `Stack` layer, not a route — page beneath stays mounted |
| 14 | Android background playback | Verified on OPPO CPH2791 / Android 16. Three bugs found |
| 15 | drift schema and codegen | Six tables, normalised search columns, sync state |
| 16 | Paginated initial sync | Three passes plus playlists. Live-verified |
| 17 | Websocket push sync | `dart:io` socket, backoff reconnect, reconnect on resume. **Needs live verification** |
| 18 | Change-detection poll and delta sync | 30s poll on `/library/sections`, wake on resume, pull-to-refresh. Schema v3 rewinds the cursor once |
| 20 | UI reads from drift, additively | Grid streams from cache; sort by added/title/artist |
| 26 | Sidebar with recent playlists | Recents beneath the destinations; bottom nav under 800px |
| 27 | Home screen and browsing | Jump back in / recently added / favourites. Artist pages with albums *and* tracks, library toggle |
| 35 | Star ratings and favourites | Write-through to `/:/rate`, optimistic with revert. Favourite = 4★+ |
| 36 | Smart playlist support | `smart` flag stored and badged; contents always revalidated, never served from cache |
| 37 | Windows media keys | SMTC in the C++ runner. Verified end to end with synthetic key presses |
| 38 | Compact track rows | Per-track stars are desktop-only; long press opens a rating sheet on phones |

### Bugs found by device testing (#14)

All four were release-only or device-only and would have shipped:

1. **`INTERNET` missing from the main manifest.** Flutter only injects it into debug and
   profile manifests, so release builds had no network at all.
2. **`POST_NOTIFICATIONS` never requested.** `audio_service` declares it but never prompts.
3. **`androidStopForegroundOnPause: true`** deleted the notification on pause — controls
   vanished exactly when you'd reach for them.
4. **`audio_service` 0.18.19 throws on Android 13+.** It converts `MediaControl.stop` into a
   `CustomAction` requiring a non-zero icon, resolves that icon by name against *our*
   package, gets `0`, and throws — killing the whole notification. Removed that control.

---

## Open

### Needs James present

**#8 — Transcode spike.** Establish working parameters for
`/music/:/transcode/universal/start`. Confirm the **progressive** form (`start.mp3`) works
and is cacheable by `LockCachingAudioSource` — HLS (`start.m3u8`) is **not**. All remote and
cellular listening depends on this, and it is the least-documented part of the Plex API.
If progressive can't be made to work, escalate: remote falls back to direct-play only.
**Gates #23.**

### Known caveats

**Existing Plex ratings arrive on the next launch, once.** The v2 `userRating` columns start
empty, and a delta sync cannot fill them — Plex's `updatedAt` for a track rated months ago
has not moved. Schema v3 rewinds the delta cursor so the next run does one full pass. Expect
a longer-than-usual sync exactly once after upgrading, then ratings appear on their own.

**Is `updatedAt>=` actually honoured by Plex?** The delta sweep now runs every five minutes
regardless of the section clocks, so if that filter is silently ignored the app would refetch
the whole library on that cadence rather than a handful of rows. Worth confirming against the
real server — compare the response size of a listing with and without the parameter. If it is
ignored, lengthen `SyncScheduler.deltaInterval` and find another filter.

**Verify push sync (#17) against the real server.** Code-complete and covered by tests, but
the frame shapes came from Plex's documented behaviour, not from a capture. Add a track in
Plex with the app open and watch it appear without a refresh; delete one and watch it go.
If nothing happens, log the raw frames first — the likely culprits are the `state` values
and whether `identifier` is what we filter on.

### Phase 2 — data layer (remaining)

**#19 — Deletion reconcile.** Deletions don't appear in an `updatedAt` delta, so the cache
accumulates ghosts that 404 on play. #17 catches deletions that happen while connected;
this catches the rest. Periodically fetch the ratingKey set only and remove local rows Plex
no longer has. `SyncState.lastReconcileAt` exists for this. `LibraryWriter.deleteItem`
already handles cascading to children.

**#21 — Artwork disk cache.** Bounded, keyed by thumb path and size, LRU, prefetch ahead of
scroll. Biggest perceived-performance win left in the grid.

### Phase 3 — playback

**#22 — Queue controls.** Shuffle and repeat through `audio_service` so the lock screen
reflects them. Queue reorder and remove — the Up Next list in Now Playing is read-only for
now. Verify gapless **by ear** on a continuous album.

**#23 — Adaptive quality** *(needs #8)*. LAN → direct play. Remote wifi → bandwidth probe.
Cellular → 320k AAC. Data-saver → 128k. Relay always transcodes
(`PlexServer.preferTranscode` already flags it). Apply on next track, not mid-track.
**Gates #24.**

**#24 — Audio disk cache** *(needs #23)*. `LockCachingAudioSource`, bounded LRU, ~2GB
Android / ~10GB desktop, fills on wifi/LAN only. **The key must include the quality
decision, not just trackId** — otherwise a 320k copy cached on cellular is served forever
once back on the LAN.

**#25 — Timeline and scrobbling.** `/:/timeline` during playback, `/:/scrobble` on
completion. The ratingKey is already in `MediaItem.extras`.

### Phase 5 — search (next up)

**#28 — Instant local search.** drift-backed on every keystroke, no network round trip. The
normalised columns and indexes already exist. Merge with `/hubs/search` so unsynced server
content still appears.

**#29 — MusicBrainz "Not in your library" tier.** Free, no API key, art from Cover Art
Archive. **Must**: descriptive `User-Agent` with contact info (generic agents get 503),
debounced single-flight queue (~1 req/sec), cached results. Local results always render
first and independently. **Gates #30, #33.**

**#30 — De-duplicate catalog results** *(needs #29)*. Match on `Albums.mbid` where present,
falling back to `normalisedArtist` + `normalisedTitle`. Get it wrong and every album you own
appears twice.

### Phase 6 — radio

**#31 — Sonic radio and autoplay.** `/library/metadata/{ratingKey}/nearest?limit=50`.
Autoplay **on by default** — the `onQueueExhausted` hook already exists in
`PlexifyAudioHandler`. Surface a clear "sonic analysis incomplete" state.
**Prerequisite: Plex sonic analysis must have been run — takes hours to days.**

### Phase 7 — acquisition

**#32 — qBittorrent client.** WebUI API v2, native web form login → `SID` cookie, one layer,
no HTTP Basic. **Two traps:** `Referer`/`Origin` must exactly match `Host` including port, or
unexplained 403s; and 403 *also* means "IP banned for too many failed logins", so one attempt
then explicit backoff — a retry loop would get the phone banned by James's own server.
**Gates #33.**

**#33 — Acquisition flow** *(needs #29, #32)*. Search using **structured** MusicBrainz
metadata (artist + album + year), not the raw typed string. Rank by seeders and format. Add
with `category=Music` — existing automation handles routing, so no renaming or retagging.
Poll progress, then `/library/sections/{id}/refresh`.

### Phase 8 — release

**#34 — Packaging.** Signed APK with a real keystore (currently debug signing). Windows
bundle. Icons, first-run flow, settings screen. Size guard: arm64 release is 20.8MB against
a ~20MB expectation.

---

## Open decisions

- **Riverpod stays at 2.6.1.** 3.4.2 declares `test ^1.0.0` as a *runtime* dependency, which
  transitively pins `analyzer <13`, while `drift_dev` 2.34.x requires `analyzer ^13`.
  Mutually exclusive on Flutter 3.44. Revisit when upstream resolves.
- **Git author is `unknown`.** `user.name` is unset globally. Set it and the existing commits
  can be amended.
- **The Windows runner builds as C++20.** C++/WinRT falls back to
  `<experimental/coroutine>` under C++17, which current MSVC rejects outright — the same
  header that made `permission_handler` unbuildable. Raised for the runner target only.
- **ColorOS battery killer.** `OplusHansManager` tracks the process. If playback dies over a
  long session, the fix is exempting Plexify from battery optimisation, not code.
