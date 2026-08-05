# Plexify — task list

Working state for the build, and the durable record — a session's own task list starts empty
and its numbering has already diverged, so this file wins. See [docs/PLAN.md](../docs/PLAN.md)
for the design and rationale, and [PROJECT.md](PROJECT.md) for environment, conventions and
known traps.

**Last updated:** 5 August 2026

**Status:** 24 complete · 18 open · 133 tests passing

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
| 17 | Websocket push sync | `dart:io` socket, backoff reconnect, reconnect on resume. Live-verified — a new album appears instantly |
| 18 | Change-detection poll and delta sync | 30s poll on `/library/sections`, wake on resume, pull-to-refresh. Schema v3 rewinds the cursor once |
| 20 | UI reads from drift, additively | Grid streams from cache; sort by added/title/artist |
| 26 | Sidebar with recent playlists | Recents beneath the destinations; bottom nav under 800px |
| 27 | Home screen and browsing | Jump back in / recently added / favourites. Artist pages with albums *and* tracks, library toggle |
| 35 | Star ratings and favourites | Write-through to `/:/rate`, optimistic with revert. Favourite = 4★+ |
| 36 | Smart playlist support | `smart` flag stored and badged; contents always revalidated, never served from cache |
| 37 | Windows media keys | SMTC in the C++ runner. Verified end to end with synthetic key presses |
| 38 | Compact track rows | Per-track stars are desktop-only; long press opens a rating sheet on phones |
| 39 | Sync status screen | Socket/poll/clock state, row counts, sync now and full resync. Poll pauses off screen |
| 40 | A–Z artist index | Letter headers and a jump rail. Articles stripped, matching Plex `titleSort` |

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

### Order

Phase numbers record where a task was *designed*, not what to do next, and the two have come
apart. This is the order. It was set with two facts about how Plexify is actually used:
listening is split roughly evenly between LAN and cellular, and James is running Plexify and
Plexamp side by side while moving over.

| | Task | Why here |
|---|---|---|
| 1 | **#41** Reconnect when the network changes | The app is currently broken in the exact case that "even split" describes. Nothing else matters while carrying the phone out of the house kills playback. |
| 2 | **#25** Timeline and scrobbling | Plays are split across two clients right now, so every Plexify play is silently missing from the history both clients read. Every day this waits is a day of history that cannot be recovered. |
| 3 | **#8** Transcode spike | Needs James present. Gates #23 and #24, i.e. all of cellular listening — half the use. |
| 4 | **#21** Artwork disk cache | Cheap, and the largest repeating data cost after audio. Worth doing before more cellular use, not after. |
| 5 | **#23 → #24** Adaptive quality, then audio cache | Unblocked by #8. This is what makes the cellular half pleasant rather than merely working. |
| 6 | **#43** Settings screen | Do not sequence this after #23/#24 — they need somewhere to expose quality and cache controls, and shipping them with hidden hardcoded policy is what forces a rewrite. |
| 7 | **#42** Sign out and switch server | Small, and the only route out of a bad token that isn't clearing app data. |
| 8 | **#19** Deletion reconcile | Ghost rows 404 on play. Real, but rarer and far more obvious than anything above it. |
| 9 | **#44** Now Playing navigation test | The invariant the plan calls non-retrofittable is the least guarded thing in the app. Cheap insurance before the shell is touched again. |
| 10 | **#22** Queue controls, then Phase 5 onward | Feature work resumes here. |

#28 was previously marked "next up". It is a feature, and it now sits behind correctness.

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

**Is `updatedAt>=` actually honoured by Plex?** Check "Rows in last sync" on the Sync status
screen after a routine sweep with nothing new. Near zero means the filter works. Anything
near the library size means Plex is ignoring it and every sweep refetches everything —
tolerable on a LAN, ruinous on cellular. If so, lengthen `SyncScheduler.deltaInterval` and
find a filter Plex does honour.

**Ratings set in Plex are not pushed, only polled.** Plex emits a timeline entry when it
finishes *scanning* an item, which is why a new album appears instantly, but rating one is a
metadata edit that produces no such entry. The five-minute sweep catches it; the refresh
button catches it now. Accepted rather than fixed — the alternative is watching another
notification type, and James has asked that the sync logic not grow more paths.

### Correctness — found reviewing the list, not by planning it

**#41 — Reconnect when the network changes.** Carrying the phone from wifi to cellular kills
playback; starting fresh on cellular is fine. `connectServerProvider` is a `FutureProvider`
keyed only on the auth token, so it resolves **once per session**. On the LAN, wave 1 wins
and `baseUrl` is pinned to the local `plex.direct` address; leaving the house does not
re-run it. The resume hook reconnects the notification socket and the poll scheduler, but
both then aim at the dead address, as do the audio URLs already handed to `just_audio`.
The reverse is quieter and also wrong: coming home keeps the remote or relay connection, so
audio transcodes over the internet while the server sits on the same wifi. Needs a
connectivity listener and repeated-failure detection to re-race the waves, plus a decision
about the currently-playing track — re-resolving the client does not rewrite a URL already
inside the player.

**#42 — Sign out and switch server.** `PlexAuth.signOut()` exists and nothing calls it.
An expired token or a different server currently means clearing app data.

**#43 — Settings screen.** The Sync status screen is the only settings-shaped thing that
exists. **Sequence this before #23/#24, not after** — quality policy and cache size need
somewhere to live, and shipping them as hidden constants is what forces the rewrite.
Account, quality override per network, cache size and clear-cache, sign out.

**#44 — Widget test: Now Playing preserves navigation state.** The plan calls this
invariant non-retrofittable and it has no test. The overlay-not-a-route design exists
solely to guarantee it, and it would break silently in any shell refactor.

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

This is filed under Phase 3 but is **already a visible bug**, not a future feature. Home's
"Jump back in" reads `Albums.lastViewedAt`, and only Plex writes that column — so playing an
album in Plexify updates nothing, and that row goes staler the more Plexify gets used. It
also breaks the plan's premise that Plex stays the single source of truth for history. With
Plexamp still in use alongside, history is currently being split between a client that
reports and one that does not, and the unreported half cannot be reconstructed later.

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
bundle — currently a 48MB folder under `build/windows/x64/runner/Release/`, and the whole
folder is the deliverable: `plexify.exe` is only 157KB and will not start without the sibling
DLLs (`flutter_windows`, `libmpv-2`, `sqlite3`) and `data/`. Icons, first-run flow, a real
settings screen — the Sync status screen is the only settings-shaped thing that exists.
Size guard: arm64 release is 21.4MB against a ~20MB expectation.

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
- **The sync logic does not grow more paths.** James asked for this explicitly after the
  ratings-not-appearing round. Three delivery mechanisms is the ceiling: push, poll, sweep.
  Prefer making the existing ones observable over adding a fourth.
- **Artists file under their first non-article word**, so The Beatles sits under B, matching
  Plex's own `titleSort`. Reverse it and the app disagrees with the server it browses.
