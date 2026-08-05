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

## Order

Phase numbers record where a task was *designed*, not what to do next, and the two have come
apart. This is the order. It was set with two facts about how Plexify is actually used:
listening is split roughly evenly between LAN and cellular, and James is running Plexify and
Plexamp side by side while moving over.

| | Task | Why here |
|---|---|---|
| 1 | **#41** Reconnect when the network changes | The app is currently broken in the exact case that "even split" describes. Also builds the connectivity listener #23 needs, so it is infrastructure as well as a fix. |
| 2 | **#25** Timeline and scrobbling | Plays are split across two clients right now, so every Plexify play is missing from the history both read. Every day this waits is history that cannot be recovered. |
| 3 | **#8** Transcode spike | Needs James present. Gates #23 and #24, i.e. all of cellular listening — half the use. |
| 4 | **#43a** Settings shell | Small. Needed as somewhere for #42 to live, and for #23/#24 to expose policy rather than hardcode it. |
| 5 | **#42** Sign out and switch server | Small, and the only route out of a bad token that isn't clearing app data. |
| 6 | **#21** Artwork disk cache | Cheap, and the largest repeating data cost after audio. Worth doing before more cellular use, not after. |
| 7 | **#23 → #24 → #43b** Quality, audio cache, their settings | Unblocked by #8. This is what makes the cellular half pleasant rather than merely working. |
| 8 | **#19** Deletion reconcile | Ghost rows 404 on play. Real, but rarer and more obvious than anything above it. |
| 9 | **#44** Now Playing navigation test | The invariant the plan calls non-retrofittable is the least guarded thing in the app. Cheap insurance before the shell is touched again. |
| 10 | **#22** Queue controls, then Phase 5 onward | Feature work resumes here. |

#28 was previously marked "next up". It is a feature, and it now sits behind correctness.

---

## Detail

Near-term tasks are broken down properly; Phase 6–8 deliberately are not, because the design
will have moved by the time they start.

### #41 — Reconnect when the network changes

**The bug.** Carrying the phone from wifi to cellular kills playback. Launching cold on
cellular is fine, which disguises it as a playback fault.
`connectServerProvider` ([providers.dart:71](../lib/core/providers.dart:71)) is a
`FutureProvider` keyed on the auth token alone, so it resolves **once per session**. On the
LAN, wave 1 wins and `baseUrl` is pinned to the local `plex.direct` address. Leaving the
house never re-runs it, so every request, the notification socket, the poll, and any audio
URL already inside `just_audio` all keep aiming at an unreachable host. Coming home is the
quiet inverse: the remote or relay connection is kept, so audio transcodes over the internet
from a server on the same wifi.

**Subtasks**

1. Add `connectivity_plus`. Note it reports *transport* changes, not reachability — a wifi
   network with no route out still reads as connected, so it is a trigger to re-check, never
   evidence that anything works.
2. Add a failure-count trigger as well. Transport changes are not the only way a connection
   dies (server restart, DHCP change, VPN), and on desktop the transport rarely changes at
   all. N consecutive failures against the current `baseUrl` should re-race regardless.
3. Make the connection re-resolvable. The cheap version is `ref.invalidate(connectServerProvider)`,
   which rebuilds `plexClientProvider` and everything downstream. **Verify the UI does not
   blank while it re-races** — the grid streams from drift so it should hold, and if it does,
   that is the additive-cache invariant paying for itself.
4. Re-race the waves. `PlexDiscovery.connect()` already contains the whole wave algorithm;
   this calls it again rather than reimplementing.
5. Single-flight and debounce it. A flapping connection must not start a re-race per event,
   and being unreachable is normal (server asleep, genuinely offline) — back off rather than
   spin.
6. Rebuild the notification socket. Its URL is built from `baseUrl`, so a re-resolve has to
   tear down and recreate it, not just call `reconnectNow()` on the old one.
7. Decide what happens to the currently-playing track — see below.
8. Surface it: connection type belongs on the Sync status screen, and a manual "reconnect"
   button there makes the whole thing testable by hand.

**Considerations**

- **The in-flight track is a real decision, not an implementation detail.** `just_audio`
  holds URL strings; re-resolving the client does not rewrite them. Either (a) let the
  current track fail and have the next one use the new connection, or (b) rebuild the queue
  with `setAudioSources(initialIndex:, initialPosition:)` at the current position. (b) is
  more correct and risks a stutter mid-song; (a) is simpler and drops one track. **Suggest
  (a) first** — it is a two-line policy, and if it feels bad in use, (b) is a contained
  change afterwards.
- `PlexServer.isLocal` / `isRelay` change on re-resolve, and `preferTranscode` reads them.
  Getting this right is a precondition for #23 being correct rather than merely present.
- **This is why #41 sits above #23 rather than beside it.** The connectivity listener is the
  same input the quality policy needs; building it as a bug fix means #23 inherits it.
- Windows is affected too (ethernet unplugged, VPN up) but far less visibly.
- Test: fake `PlexDiscovery` that answers LAN-then-nothing, then remote. Assert a re-race
  after the failure trigger, that the new `baseUrl` is remote, and that no re-race happens
  while one is already running.

### #25 — Timeline and scrobbling

**Already a visible bug, not a future feature.** Home's "Jump back in" reads
`Albums.lastViewedAt` ([providers.dart:452](../lib/core/providers.dart:452)), and only Plex
writes that column. Playing an album in Plexify updates nothing, so the row goes staler the
more Plexify is used. With Plexamp still in rotation, history is being split between a client
that reports and one that does not, and the unreported half cannot be reconstructed later.

**Subtasks**

1. `PlexClient.reportTimeline(...)` → `/:/timeline` with `ratingKey`,
   `key=/library/metadata/{ratingKey}`, `state=playing|paused|stopped`, `time` (ms),
   `duration` (ms), `identifier=com.plexapp.plugins.library`. The client identifier header is
   already sent by `PlexIdentity`.
2. `PlexClient.scrobble(ratingKey)` → `/:/scrobble?key={ratingKey}&identifier=com.plexapp.plugins.library`.
3. A `TimelineReporter` listening to the handler's streams: post every ~10s while playing,
   and immediately on play, pause, stop and track change.
4. Fire the scrobble once per play at ~90% (what Plex's own clients use), and **only once** —
   seeking backwards or repeating the track must not re-fire until the track actually changes.
5. Write `lastViewedAt` locally at the same moment, through `LibraryWriter`, so Home updates
   instantly instead of waiting for the next sweep to bring it back from Plex.
6. `MediaItem.extras['ratingKey']` is already populated
   ([playback_controller.dart:74](../lib/features/player/playback_controller.dart:74)) — the
   URL cannot be reversed into a ratingKey, which is why it is carried.

**Considerations**

- **Every call must fail silently.** Reporting runs against a server that may be asleep,
  unreachable, or (before #41 lands) at a dead address. Nothing here may block or interrupt
  playback — this is a background courtesy, not part of the playback path.
- The local `lastViewedAt` write needs the same guard ratings needed: an `UPDATE` matches
  nothing for a track the sync has not reached. Go through `LibraryWriter`.
- Data cost is negligible — a timeline post is a few hundred bytes every 10s, far below the
  audio it accompanies.
- Verification is direct: Plex web → Status → Now Playing should list Plexify as an active
  session while a track plays, and the play should appear in history afterwards.
- Test with a recording fake client: assert scrobble fires once per track, at the threshold,
  not twice across a seek-back, and not at all for a track skipped early.

### #8 — Transcode spike *(needs James present)*

Establish working parameters for `/music/:/transcode/universal/start`. The least-documented
part of the Plex API, and everything about cellular listening depends on it.

**Subtasks**

1. Build the progressive URL: `start.mp3` with `path=/library/metadata/{ratingKey}`,
   `mediaIndex=0`, `partIndex=0`, `protocol=http`, `offset=0`, `directPlay=0`,
   `directStream=0`, a per-session `session` uuid, plus token and client identifier.
2. Confirm it returns audio directly — 200 with an audio content type, not a redirect into
   the HLS variant.
3. Confirm it honours Range requests. Seeking and caching both depend on it.
4. Confirm `LockCachingAudioSource` will cache it. **HLS cannot be cached** — if only the
   HLS form works, transcoded playback cannot be cached at all and #24 shrinks to LAN-only.
5. Work out which bitrate parameter Plex actually honours for music — `musicBitrate` and
   `maxAudioBitrate` are both cited and they may not both apply.
6. Check session cleanup (`/:/transcode/universal/stop?session=`) — abandoned sessions can
   leave the server transcoding into nothing.
7. Record the exact working parameter set in PROJECT.md. This is the deliverable; a spike
   that works but is not written down has to be redone.

**Considerations**

- Test **off** the LAN, not just remotely-addressed on it. Relay behaves differently again.
- If progressive cannot be made to work, escalate rather than improvise: remote falls back to
  direct-play only, #23 becomes a much smaller task, and cellular use gets expensive. That is
  a plan change worth making explicitly.

### #43 — Settings screen (split)

The Sync status screen is the only settings-shaped thing in the app. Split, because the shell
is needed early and the contents are not.

**#43a — the shell.** A Settings destination, with Sync status nested inside it rather than
reached from an app-bar icon. Sections: Account, Playback, Storage, Sync, About. Persist with
`shared_preferences`, already a dependency.

**#43b — playback and storage.** Quality override per network, data-saver toggle, artwork and
audio cache size and clear. Lands **with** #23/#24, not after.

**Considerations**

- Do not build settings nothing reads yet. The split exists so #42 has a home immediately
  without inventing controls for policy that does not exist.
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

### #23 — Adaptive quality *(needs #8)*

**Subtasks**

1. A `QualityPolicy` mapping (connectivity type, server locality, user override) → decision.
2. Inputs already exist or arrive with #41: `PlexServer.isLocal`, `preferTranscode` for
   relay, the connectivity listener, and the #43b override.
3. `PlaybackController._toMediaItem` chooses direct-play or transcode URL from the decision —
   it is already the single place that knows how to reach a playable URL, and the comment at
   [playback_controller.dart:54](../lib/features/player/playback_controller.dart:54) marks the
   spot.
4. Record the decision on the `MediaItem` so #24 can key its cache on it.
5. Apply on next track, not mid-track.

**Considerations**

- The remote-wifi bandwidth probe can be deferred. Start with "remote wifi → direct play,
  fall back on failure" and add the probe only if that proves wrong in use.
- Ladder: LAN → direct play. Remote wifi → probe or direct. Cellular → 320k. Data-saver →
  128k. Relay → always transcode.

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
- **Open: what happens to the playing track when the connection re-resolves.** #41 leans
  toward letting it fail and fixing the next track. Revisit after using it.
