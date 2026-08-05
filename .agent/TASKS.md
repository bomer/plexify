# Plexify — task list

What is left to do, and why. A session's own task list starts empty and its numbering has
already diverged, so this file wins. See [docs/PLAN.md](../docs/PLAN.md) for the design and
rationale, [PROJECT.md](PROJECT.md) for environment, conventions and known traps, and
[CompletedTasks.md](CompletedTasks.md) for finished work.

**Last updated:** 5 August 2026

**Status:** 31 complete · 13 open · 238 tests passing

---

## Tasks remaining

The index. One line each; the reasoning is under [Detail](#detail), and the sequence is under
[Order](#order).

| # | Task | Where it sits |
|---|---|---|
| 23 | Transcode-or-direct-play | Next. Smaller than planned — #8 found no bitrate to adapt |
| 24 | Audio disk cache | Needs #23's decision to key on |
| 43b | Settings: playback and storage | Lands with #23/#24 — the two sections #43a left empty |
| 19 | Deletion reconcile | The one place that may treat absence as authoritative |
| 44 | Now Playing navigation test | The plan's non-retrofittable invariant, currently unguarded |
| 22 | Queue controls | Shuffle, repeat, reorder; gapless verified by ear |
| 28 | Instant local search | Indexes and columns already exist; screen is a placeholder |
| 29 | MusicBrainz "not in your library" | Gates #30 and #33 |
| 30 | De-duplicate catalog results | Needs #29 |
| 31 | Sonic radio and autoplay | Needs Plex's sonic analysis to have run |
| 32 | qBittorrent client | Gates #33 |
| 33 | Acquisition flow | Needs #29 and #32 |
| 34 | Packaging and release | Real keystore, icons, first-run, size guard |

---

## Order

Phase numbers record where a task was *designed*, not what to do next, and the two have come
apart. This is the order. It was set with two facts about how Plexify is actually used:
listening is split roughly evenly between LAN and cellular, and James is running Plexify and
Plexamp side by side while moving over.

| | Task | Why here |
|---|---|---|
| 1 | **#23 → #24 → #43b** Quality, audio cache, their settings | Unblocked by #8, and **smaller than planned** — see below. This is what makes the cellular half pleasant rather than merely working. |
| 2 | **#19** Deletion reconcile | Ghost rows 404 on play. Real, but rarer and more obvious than anything above it. |
| 3 | **#44** Now Playing navigation test | The invariant the plan calls non-retrofittable is the least guarded thing in the app. Cheap insurance before the shell is touched again — and the shell just gained a destination. |
| 4 | **#22** Queue controls, then Phase 5 onward | Feature work resumes here. |

#28 was previously marked "next up". It is a feature, and it now sits behind correctness.

Four finished tasks still want live confirmation that no test can give — listed under
[Still wanting live confirmation](CompletedTasks.md#still-wanting-live-confirmation).

---

## Detail

Near-term tasks are broken down properly; Phase 6–8 deliberately are not, because the design
will have moved by the time they start.

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

### #43b — Settings: playback and storage

Quality override per network, data-saver toggle, artwork and audio cache size and clear.
Lands **with** #23/#24, not after — that is what fills the two missing sections.

**Considerations**

- Do not build settings nothing reads yet. That rule is why #43a shipped four sections and
  not six.
- Android data-saver state is not exposed by `connectivity_plus`. Either a platform channel or
  — far cheaper — a manual toggle. Suggest manual.

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
