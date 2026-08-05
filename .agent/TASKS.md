# Plexify — task list

Working state for the build, and the durable record — a session's own task list starts empty
and its numbering has already diverged, so this file wins. See [docs/PLAN.md](../docs/PLAN.md)
for the design and rationale, and [PROJECT.md](PROJECT.md) for environment, conventions and
known traps.

**Last updated:** 5 August 2026

**Status:** 28 complete · 14 open · 209 tests passing

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
| 41 | Reconnect when the network changes | Two triggers, one path: transport change and a run of failed requests. Sticky last-good address, manual reconnect in Sync status |
| 8 | Transcode spike | Answered on both routes by `TranscodeProbe`, kept in the app under Sync status. Progressive works; `offset` works; **no bitrate control exists**. Parameter set and consequences in [PROJECT.md](PROJECT.md#the-music-transcode-endpoint) |
| 43a | Settings shell | Fourth destination, bottom of the sidebar. Sync status moved inside it. `SettingsStore` over `shared_preferences`; theme mode is the first setting through it |
| 25 | Timeline reporting and scrobbling | `/:/timeline` every 10s and on every state change, `/:/scrobble` once past 90%. Writes `lastViewedAt` locally so Home updates immediately. Live-verified — Plexify appears in the Plex dashboard |

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

## Order

Phase numbers record where a task was *designed*, not what to do next, and the two have come
apart. This is the order. It was set with two facts about how Plexify is actually used:
listening is split roughly evenly between LAN and cellular, and James is running Plexify and
Plexamp side by side while moving over.

| | Task | Why here |
|---|---|---|
| 1 | **#42** Sign out and switch server | Small, and the only route out of a bad token that isn't clearing app data. Its home in Settings → Account now exists. |
| 2 | **#21** Artwork disk cache | Cheap, and the largest repeating data cost after audio. Worth doing before more cellular use, not after. |
| 3 | **#23 → #24 → #43b** Quality, audio cache, their settings | Unblocked by #8, and **smaller than planned** — see below. This is what makes the cellular half pleasant rather than merely working. |
| 4 | **#19** Deletion reconcile | Ghost rows 404 on play. Real, but rarer and more obvious than anything above it. |
| 5 | **#44** Now Playing navigation test | The invariant the plan calls non-retrofittable is the least guarded thing in the app. Cheap insurance before the shell is touched again — and the shell just gained a destination. |
| 6 | **#22** Queue controls, then Phase 5 onward | Feature work resumes here. |

**#41 and #25 are done.** Both still want live confirmation, and neither can be confirmed
from a test:

- **#41** — walk out of the house mid-track, then read "Route" and "Reconnects" on the Sync
  status screen. There is a Reconnect button there that exercises the same path indoors.
- **#25** — play a track to the end, then check Plex web → Status → Now Playing shows
  Plexify while it runs, and that the play count moved afterwards. "Plays recorded" on the
  Sync status screen says what the app thinks it sent.

#28 was previously marked "next up". It is a feature, and it now sits behind correctness.

---

## Detail

Near-term tasks are broken down properly; Phase 6–8 deliberately are not, because the design
will have moved by the time they start.

### #8 — Transcode spike *(done, 5 Aug 2026)*

Answered by `TranscodeProbe`, which stays in the app under Sync status → Transcode probe
rather than being deleted: the answers are per-server and per-route, and it is the cheapest
way to re-check after a Plex upgrade. Full parameter set and reasoning in
[PROJECT.md](PROJECT.md#the-music-transcode-endpoint).

**The three findings that change other tasks:**

1. **Progressive works.** `audio/mpeg`, no HLS. Risk #1 in the plan is retired and #24 is not
   LAN-only.
2. **The `X-Plex-*` identity must be in the query string**, or the endpoint answers 400 with
   no explanation. The headers `PlexClient` already sends do not count — the URL goes to the
   audio engine, which sends none of them.
3. **No bitrate control exists.** Three mechanisms, both routes, no change; Plex's own session
   record has no bitrate field. This makes #23 materially smaller than planned.

**What it did not answer:** the relay route was never exercised, because discovery picked
local then remote and never fell back. If relay ever becomes the working route, re-run there
before trusting any of this.

### #43a — Settings shell *(done, 5 Aug 2026)*

A fourth [`ShellDestination`](../lib/shell/shell_destination.dart), not a pushed route, so
Settings keeps its own navigation stack: open Sync status, switch to Library, come back, and
you are still on Sync status. In the sidebar it is pinned below the playlists rather than
listed with the other destinations — it is the one you reach occasionally, and putting it
above the playlists would push the thing you reach constantly further down.

**Sync status moved inside it.** It was reachable only from an `info` button beside Refresh
in the Home app bar, which is not where anyone looks for a diagnostic. That button is gone,
and [settings_screen.dart](../lib/features/settings/settings_screen.dart) is now the only
route to it — which is what the test in `settings_test.dart` guards.

**The persistence seam** is [app_settings.dart](../lib/core/settings/app_settings.dart):
`AppSettings` (one immutable value), `SettingsStore` (`shared_preferences`), and
`SettingsController`. Adding a setting is three edits and no more — a field, a key, a setter —
and every mutation goes through `_apply`, so there is exactly one place that writes to disk.
That matters more than it looks: a setter that changes the state and forgets to persist works
perfectly until the next launch.

Read **synchronously**. `SettingsStore.load()` is awaited in `main()` alongside the identity
and the audio handler, and `settingsStoreProvider` is overridden the same way, so the first
frame is already correct. Loading settings lazily would paint the default and then swap,
which is a visible flash on every cold start.

**Sections shipped: Account, Appearance, Sync, About.** Playback and Storage are *not* here,
despite being in the original plan for this task — there is nothing yet for them to control,
and a screen of controls that change nothing looks finished, so nobody notices the wiring is
missing. They arrive with #43b.

Theme mode is the first real setting, and deliberately so: it removes a hardcoded
`ThemeMode.dark` from `app.dart`, so the store is exercised by something that reads it rather
than shipping as untested infrastructure. Stored by **name**, not index — a `ThemeMode` that
gained a value or reordered under an SDK upgrade would otherwise silently change the theme.

### #43b — Settings: playback and storage

Quality override per network, data-saver toggle, artwork and audio cache size and clear.
Lands **with** #23/#24, not after — that is what fills the two missing sections.

**Considerations**

- Do not build settings nothing reads yet. That rule is why #43a shipped four sections and
  not six.
- Android data-saver state is not exposed by `connectivity_plus`. Either a platform channel or
  — far cheaper — a manual toggle. Suggest manual.

### #42 — Sign out and switch server

`PlexAuth.signOut()` exists at [plex_auth.dart:151](../lib/core/plex/plex_auth.dart:151) and
nothing calls it. An expired token or a different server currently means clearing app data.

**Subtasks**

1. Call `signOut()`, clear `authTokenProvider`, return to the login screen.
2. **Wipe the drift cache.** ratingKeys are unique only within a server, so a stale cache
   against a new server blends two libraries. Identifier-mismatch handling already exists in
   `SyncState` — confirm it covers sign-out and does not merely repair on next sync.
3. Stop the notification socket, the scheduler and playback before tearing down the client.
4. Confirm before doing it — it discards the whole local cache and forces a full re-sync.
5. Server switch needs a stored preferred `clientIdentifier`; `connectServerProvider`
   currently takes the first reachable server on the account.

### #21 — Artwork disk cache

[artwork.dart:45](../lib/features/library/artwork.dart:45) is a plain `Image.network`, so the
cache is Flutter's in-memory `ImageCache` — dropped on every launch. Every cold start
refetches every visible thumbnail.

**Subtasks**

1. Pick the mechanism: `cached_network_image` (brings `flutter_cache_manager`) or hand-rolled
   over `path_provider` + drift.
2. **Key on `(thumb, size)`, never the URL.** The artwork URL embeds both `baseUrl` and
   `X-Plex-Token` ([plex_client.dart:246](../lib/core/plex/plex_client.dart:246)), and both
   change — the token on refresh, the base URL every time #41 re-races. URL-keyed caching
   would silently miss on every network switch, which is the exact moment it matters most.
3. Bound it and evict LRU.
4. Prefetch ahead of scroll in the album grid.
5. Keep the existing placeholder for both null and error — that consistency is why `Artwork`
   is centralised.

**Considerations**

- **Verify the chosen package works on Windows before committing to it.**
  `flutter_cache_manager` reaches for `sqflite`, whose Windows support is not a given. If it
  does not, a drift-backed custom cache manager is the fallback — drift is already there and
  already works on both platforms.
- `Artwork` watches `plexClientProvider`, so a re-resolve rebuilds every image widget with a
  new URL. With the key right this is a cache hit; with it wrong it is a full re-download of
  the visible grid on every network change.
- Test: same thumb at two sizes yields two entries; same thumb after a token change yields a
  hit, not a second entry.

### #23 — Transcode-or-direct-play *(unblocked, and smaller than planned)*

Renamed from "adaptive quality" because #8 established there is no quality to adapt: Plex
transcodes music to VBR mp3 at ~235–242 kbps and ignores every documented way of asking for
less. The decision is binary.

**Subtasks**

1. A `QualityPolicy` mapping (connectivity type, server locality, user override) → direct play
   or transcode. No bitrate anywhere in the type — there is nothing to put there.
2. **Compare source rate against ~240 kbps before transcoding.** Transcoding a 128k mp3 up to
   240 spends more data for worse audio, so the policy must transcode lossless and leave
   already-small files alone. `PlexTrack` does not currently parse the part's `size`, so this
   needs adding — the probe reads it from a ranged request instead.
3. `PlaybackController._toMediaItem` chooses the URL from the decision. Already the single
   place that knows how to reach a playable URL; the comment at
   [playback_controller.dart:54](../lib/features/player/playback_controller.dart:54) marks it.
4. Record the decision on the `MediaItem` so #24 can key its cache on it.
5. Apply on next track, not mid-track.
6. Seeking a transcode must restart it at `offset=` — Range is not supported, and
   `LockCachingAudioSource` throws if asked to seek past what it has downloaded.

**Considerations**

- The remote-wifi bandwidth probe is now pointless: there is no lower rate to fall back to.
  The choice is transcode or don't.
- The cache key stays `(trackId, decision)` even though the decision is binary — a direct-play
  FLAC and a transcoded mp3 of the same track are still different bytes.


### #24 — Audio disk cache *(needs #23)*

**Subtasks**

1. `LockCachingAudioSource` in place of `AudioSource.uri` at
   [playback_handler.dart:63](../lib/core/audio/playback_handler.dart:63).
2. **Key on `(ratingKey, qualityDecision)`.** Keyed on ratingKey alone, a 320k copy cached on
   cellular is served forever once back on the LAN, and the fidelity adaptive quality exists
   to protect silently never arrives.
3. Bounded LRU — ~2GB Android, ~10GB desktop, configurable in #43b.
4. Fill on wifi/LAN only, so it never burns cellular in the background.
5. Eviction must not delete a file currently being read.

**Considerations**

- **Verify `LockCachingAudioSource` works under `just_audio_media_kit` on Windows.** The
  caching source is a just_audio feature and the media_kit backend is a different engine;
  this is a genuine unknown, not a formality. If it does not work, the cache is Android-only
  — acceptable, but worth knowing before designing around it.
- This layer is what later becomes explicit offline downloads. Worth not painting into a
  corner, without building for it yet.

### #19 — Deletion reconcile

Deletions do not appear in an `updatedAt` delta, so the cache accumulates ghosts that 404 on
play. #17 catches deletions that happen while connected; this catches the rest.
`SyncState.lastReconcileAt` exists for it and `LibraryWriter.deleteItem` already cascades.

**Subtasks**

1. Fetch the ratingKey set for the section, paginated.
2. Delete local rows Plex no longer has.
3. Stamp `lastReconcileAt`; run daily, plus on demand from Sync status.

**Considerations**

- **This is the one place that deliberately breaks the "cache is additive, never
  authoritative about absence" invariant, so it needs the strongest guard in the codebase.**
  A pass that drops halfway — network blip, server restart mid-pagination — must be discarded
  entirely. Treating a partial fetch as authoritative deletes a chunk of the library, and the
  user's first symptom is albums vanishing.
- Test this failure directly: simulate a fetch that fails on page 3 of 5 and assert **nothing**
  is deleted. That test matters more than the happy path.
- Plex has no keys-only projection, so the pass is not cheap. Daily is right; hourly is not.

### #44 — Widget test: Now Playing preserves navigation state

docs/PLAN.md calls this invariant non-retrofittable and it has no test. The sibling-`Stack`
overlay design in [app_shell.dart](../lib/shell/app_shell.dart) exists solely to guarantee it.

Navigate deep into a tab's nested `Navigator`, scroll, expand the overlay via
`nowPlayingExpandedProvider`, assert the underlying route is still mounted, collapse, assert
the scroll position survived.

### #22 — Queue controls

**Subtasks**

1. Shuffle and repeat: `setShuffleModeEnabled` / `setLoopMode`, exposed through
   `AudioHandler.setShuffleMode` / `setRepeatMode`, which are **not currently overridden**.
2. Publish both in `_toPlaybackState` so the lock screen reflects them rather than showing a
   control that lies.
3. Queue reorder and remove — the Up Next list in Now Playing is read-only. `moveAudioSource`
   / `removeAudioSourceAt`, keeping `queue` in step.
4. Verify gapless **by ear** on a continuous album, both platforms.

### Phase 5 — search

**#28 — Instant local search.** drift-backed on every keystroke, no network round trip. The
normalised columns and their indexes already exist (`idx_artists_norm`, `idx_albums_norm_title`,
`idx_albums_norm_artist`, `idx_tracks_norm`). Merge with `/hubs/search` so unsynced server
content still appears. [search_screen.dart](../lib/features/search/search_screen.dart) is a
placeholder wired into the shell, so there is a visible "coming soon" in the app until this
lands.

**#29 — MusicBrainz "Not in your library" tier.** Free, no API key, art from Cover Art
Archive. **Must**: descriptive `User-Agent` with contact info (generic agents get 503),
debounced single-flight queue (~1 req/sec), cached results. Local results always render first
and independently — that is what makes the rate limit invisible. **Gates #30, #33.**

**#30 — De-duplicate catalog results** *(needs #29)*. Match on `Albums.mbid` where present,
falling back to `normalisedArtist` + `normalisedTitle` — the column exists and is unused so
far. Get it wrong and every album you own appears twice.

### Phase 6 — radio

**#31 — Sonic radio and autoplay.** `/library/metadata/{ratingKey}/nearest?limit=50`.
Autoplay **on by default**; the `onQueueExhausted` hook already exists at
[playback_handler.dart:41](../lib/core/audio/playback_handler.dart:41). Surface a clear
"sonic analysis incomplete" state rather than silently returning nothing.
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

**#34 — Packaging.** Signed APK with a real keystore — `android/app/build.gradle.kts:32` still
signs release with the debug key. Windows bundle: currently a 48MB folder under
`build/windows/x64/runner/Release/`, and the whole folder is the deliverable — `plexify.exe` is
157KB and will not start without the sibling DLLs (`flutter_windows`, `libmpv-2`, `sqlite3`)
and `data/`. Icons, first-run flow. Size guard: arm64 release is 21.4MB against a ~20MB
expectation.

---

## Known caveats

**Existing Plex ratings arrive on the next launch, once.** The v2 `userRating` columns start
empty, and a delta sync cannot fill them — Plex's `updatedAt` for a track rated months ago
has not moved. Schema v3 rewinds the delta cursor so the next run does one full pass. Expect
a longer-than-usual sync exactly once after upgrading, then ratings appear on their own.

**Is `updatedAt>=` actually honoured by Plex?** Check "Rows in last sync" on the Sync status
screen after a routine sweep with nothing new. Near zero means the filter works. Anything
near the library size means Plex is ignoring it and every sweep refetches everything —
tolerable on a LAN, ruinous on cellular. If so, lengthen `SyncScheduler.deltaInterval` and
find a filter Plex does honour.

**Repeating a track does not record a second play.** `TimelineReporter` resets its
"already counted" mark when the media item changes, and repeat-one never changes it —
`just_audio` keeps the same index. Going back to a track manually *does* count again, which
is the common case. Worth revisiting alongside #22, which is where repeat gets built.

**A play is judged by elapsed time, not by the player's position.** At the moment a track
change arrives the player has already moved on, so its position getter reports the *new*
track. `TimelineReporter` projects the outgoing track's position from the last sample plus
wall time instead. That is right for a track that ran to its end and for one that was
skipped, and slightly wrong if playback stalled on a long buffer just before the change —
which would under-count, never over-count. The safer direction of the two.

**Ratings set in Plex are not pushed, only polled.** Plex emits a timeline entry when it
finishes *scanning* an item, which is why a new album appears instantly, but rating one is a
metadata edit that produces no such entry. The five-minute sweep catches it; the refresh
button catches it now. Accepted rather than fixed — the alternative is watching another
notification type, and James has asked that the sync logic not grow more paths.

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
- **The playing track is not rescued when the connection re-resolves.** `just_audio` holds
  URL strings and re-resolving does not rewrite them, so the track in flight fails and the
  next one uses the new address. Rebuilding the queue at the current position would save it
  at the cost of a stutter mid-song. Left as is deliberately — revisit only if it grates in
  practice.
- **The connection never resolves to null once it has worked.** Only signing out clears it.
  A failed re-resolve keeps the stale address, because no server means no client, no client
  means no requests, and no requests means nothing can ever observe the failure that would
  trigger the next attempt. Written down because "it looks connected but isn't" reads like a
  bug until you know what the alternative costs.
