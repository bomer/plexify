# Plexify, task list

What is left to do, and why. A session's own task list starts empty and its numbering has
already diverged, so this file wins. See [docs/PLAN.md](../docs/PLAN.md) for the design and
rationale, [PROJECT.md](PROJECT.md) for environment, conventions and known traps, and
[CompletedTasks.md](CompletedTasks.md) for finished work.

**Last updated:** 6 August 2026

**Status:** 44 complete · 7 open · 383 tests passing

---

## Tasks remaining

The index. One line each; the reasoning is under [Detail](#detail), and the sequence is under
[Order](#order).

| # | Task | Where it sits |
|---|---|---|
| 29 | MusicBrainz "not in your library" | Gates #30 and #33. #28 left the empty-result message pointing at it |
| 30 | De-duplicate catalog results | Needs #29 |
| 31 | Sonic radio and autoplay | Needs Plex's sonic analysis to have run |
| 32 | qBittorrent client | Gates #33 |
| 33 | Acquisition flow | Needs #29 and #32 |
| 19 | Deletion reconcile | The one place that may treat absence as authoritative |
| 51 | Use a delta filter Plex honours | Needs one run of the Delta filter probe to say which spelling works. Not slotted into Order, that is yours |

---

## Order

Phase numbers record where a task was *designed*, not what to do next, and the two have come
apart. This is the order. It was set with two facts about how Plexify is actually used:
listening is split roughly evenly between LAN and cellular, and James is running Plexify and
Plexamp side by side while moving over.

| | Task | Why here |
|---|---|---|
| 1 | **#19** Deletion reconcile | Ghost rows 404 on play. Real, but rarer and more obvious than anything above it. |

Eight finished tasks still want live confirmation that no test can give, listed under
[Still wanting live confirmation](CompletedTasks.md#still-wanting-live-confirmation). #23's
is the one that matters most, and #43b now depends on it too: a transcode has never been
*heard* playing on either platform, only requested.

---

## Detail

Near-term tasks are broken down properly; Phase 6–8 deliberately are not, because the design
will have moved by the time they start.

### #51, Use a delta filter Plex honours

`updatedAt>=` is ignored, so every sweep refetches the library. #50 made a quiet relaunch
cheap by sweeping less often; this would make the sweeps themselves cheap.

Blocked on evidence, not on work. Run **Sync status → Delta filter probe** against the real
server, read which spelling it reports as usable, and change the one line in
`PlexClient.sectionPage`.

**What the first run already established**, on 6 August 2026 against 11,492 tracks:
`updatedAt>=` and `updatedAt>>=` returned all of them, so both are ignored. `updatedAt>` and
`updatedAt>>` returned **zero**, which is either a working filter or one the server turns
into an empty set, and those are not the same thing at all: adopting the second would stop
the library ever gaining music, silently. The probe now asks each spelling twice, once where
it must return nothing and once where it must return everything, so a second run settles it.

**If `>` turns out to work, the cursor needs care.** It is strict, and the stored cursor is
the newest `updatedAt` already held, so a row sharing that exact second and not yet seen would
be skipped for ever. A bulk edit stamps many rows with one timestamp, so this is not
hypothetical. Store `cursor - 1`.

If the probe says nothing is usable, this task becomes "lengthen `deltaInterval` and let the
section clocks carry it alone" instead.

### #19, Deletion reconcile

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
  A pass that drops halfway (a network blip, a server restart mid-pagination) must be
  discarded entirely. Treating a partial fetch as authoritative deletes a chunk of the library, and the
  user's first symptom is albums vanishing.
- Test this failure directly: simulate a fetch that fails on page 3 of 5 and assert **nothing**
  is deleted. That test matters more than the happy path.
- Plex has no keys-only projection, so the pass is not cheap. Daily is right; hourly is not.

### Phase 5, search

**#29, MusicBrainz "Not in your library" tier.** Free, no API key, art from Cover Art
Archive. **Must**: descriptive `User-Agent` with contact info (generic agents get 503),
debounced single-flight queue (~1 req/sec), cached results. Local results always render first
and independently, that is what makes the rate limit invisible. **Gates #30, #33.**

**#30, De-duplicate catalog results** _(needs #29)_. Match on `Albums.mbid` where present,
falling back to `normalisedArtist` + `normalisedTitle`, the column exists and is unused so
far. Get it wrong and every album you own appears twice.

### Phase 6, radio

**#31, Sonic radio and autoplay.** `/library/metadata/{ratingKey}/nearest?limit=50`.
Autoplay **on by default**; the `onQueueExhausted` hook already exists at
[playback_handler.dart:41](../lib/core/audio/playback_handler.dart:41). Surface a clear
"sonic analysis incomplete" state rather than silently returning nothing.
**Prerequisite: Plex sonic analysis must have been run, takes hours to days.**

### Phase 7, acquisition

**#32, qBittorrent client.** WebUI API v2, native web form login → `SID` cookie, one layer,
no HTTP Basic. **Two traps:** `Referer`/`Origin` must exactly match `Host` including port, or
unexplained 403s; and 403 _also_ means "IP banned for too many failed logins", so one attempt
then explicit backoff, a retry loop would get the phone banned by James's own server.
**Gates #33.**

**#33, Acquisition flow** _(needs #29, #32)_. Search using **structured** MusicBrainz
metadata (artist + album + year), not the raw typed string. Rank by seeders and format. Add
with `category=Music`, existing automation handles routing, so no renaming or retagging.
Poll progress, then `/library/sections/{id}/refresh`.

---

## Known caveats

**Releasing needs a signing key that does not exist yet.** `tool/package.ps1` refuses to
build without `android/key.properties`, deliberately: a debug-signed APK installs and runs
perfectly and only fails much later, when a properly signed build will not upgrade it.
[tool/README.md](../tool/README.md) has the one `keytool` command. **The first
release-signed install will need the current build uninstalled**, taking the library cache
and the token with it, because Android refuses an upgrade across a signature change.

**Artist ratings are Plex's, not local.** They live on the same `/:/rate` endpoint as albums
and tracks and sync both ways: set one in the Plex web UI and it arrives on the next pass,
set one on the artist page and it shows up in Plex. Schema v6 added the column and v7 rewinds
the delta cursor so ratings set before Plexify existed actually come through, for the same
reason v3 did. Expect one longer sync after upgrading.

**Existing Plex ratings arrive on the next launch, once.** The v2 `userRating` columns start
empty, and a delta sync cannot fill them, Plex's `updatedAt` for a track rated months ago
has not moved. Schema v3 rewinds the delta cursor so the next run does one full pass. Expect
a longer-than-usual sync exactly once after upgrading, then ratings appear on their own.

**`updatedAt>=` is not honoured by Plex.** Answered 6 August 2026 by reading "Rows in last
sync" after a five-second launch: cursor set, initial sync complete, **13,704 rows** came
back, which is the whole library. Plex accepts the parameter, answers 200 and drops it, so an
ignored filter looks exactly like a library where everything changed. #50 stopped the
*launch* paying for that; #51 is finding a spelling the server acts on.

**Repeating a track does not record a second play.** `TimelineReporter` resets its
"already counted" mark when the media item changes, and repeat-one never changes it -
`just_audio` keeps the same index. Going back to a track manually _does_ count again, which
is the common case. Worth revisiting alongside #22, which is where repeat gets built.

**A play is judged by elapsed time, not by the player's position.** At the moment a track
change arrives the player has already moved on, so its position getter reports the _new_
track. `TimelineReporter` projects the outgoing track's position from the last sample plus
wall time instead. That is right for a track that ran to its end and for one that was
skipped, and slightly wrong if playback stalled on a long buffer just before the change -
which would under-count, never over-count. The safer direction of the two.

**Ratings set in Plex are not pushed, only polled.** Plex emits a timeline entry when it
finishes _scanning_ an item, which is why a new album appears instantly, but rating one is a
metadata edit that produces no such entry. The five-minute sweep catches it; the refresh
button catches it now. Accepted rather than fixed, the alternative is watching another
notification type, and James has asked that the sync logic not grow more paths.

---

## Open decisions

- **Riverpod stays at 2.6.1.** 3.4.2 declares `test ^1.0.0` as a _runtime_ dependency, which
  transitively pins `analyzer <13`, while `drift_dev` 2.34.x requires `analyzer ^13`.
  Mutually exclusive on Flutter 3.44. Revisit when upstream resolves.
- **Git author is `unknown`.** `user.name` is unset globally. Set it and the existing commits
  can be amended.
- **The Windows runner builds as C++20.** C++/WinRT falls back to
  `<experimental/coroutine>` under C++17, which current MSVC rejects outright, the same
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
  at the cost of a stutter mid-song. Left as is deliberately, revisit only if it grates in
  practice.
- **The connection never resolves to null once it has worked.** Only signing out clears it.
  A failed re-resolve keeps the stale address, because no server means no client, no client
  means no requests, and no requests means nothing can ever observe the failure that would
  trigger the next attempt. Written down because "it looks connected but isn't" reads like a
  bug until you know what the alternative costs.
