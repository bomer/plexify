# Plexify, task list

What is left to do, and why. A session's own task list starts empty and its numbering has
already diverged, so this file wins. See [docs/PLAN.md](../docs/PLAN.md) for the design and
rationale, [PROJECT.md](PROJECT.md) for environment, conventions and known traps, and
[CompletedTasks.md](CompletedTasks.md) for finished work.

**Last updated:** 9 August 2026

**Status:** 53 complete · 2 open · 518 tests passing

---

## Tasks remaining

The index. One line each; the reasoning is under [Detail](#detail), and the sequence is under
[Order](#order).

| # | Task | Where it sits |
|---|---|---|
| 31 | Sonic radio and autoplay | Needs Plex's sonic analysis to have run |
| 19 | Deletion reconcile | The one place that may treat absence as authoritative |

---

## Order

Phase numbers record where a task was *designed*, not what to do next, and the two have come
apart. This is the order. It was set with two facts about how Plexify is actually used:
listening is split roughly evenly between LAN and cellular, and James is running Plexify and
Plexamp side by side while moving over.

| | Task | Why here |
|---|---|---|
| 1 | **#19** Deletion reconcile | Ghost rows 404 on play. Real, but rarer and more obvious than anything above it. |

Finished tasks still wanting live confirmation that no test can give are listed under
[Still wanting live confirmation](CompletedTasks.md#still-wanting-live-confirmation). #23's
is the one that matters most, and #43b depends on it too: a transcode has never been *heard*
playing on either platform, only requested. The whole catalog and acquisition group (#29,
#30, #32, #33) joined that list on 7 August: it is built and tested against fixtures, and
nothing in it has met the real MusicBrainz or James's real qBittorrent.

---

## Detail

Near-term tasks are broken down properly; Phase 6–8 deliberately are not, because the design
will have moved by the time they start.

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

### Phase 6, radio

**#31, Sonic radio and autoplay.** `/library/metadata/{ratingKey}/nearest?limit=50`.
Autoplay **on by default**; the `onQueueExhausted` hook already exists at
[playback_handler.dart:41](../lib/core/audio/playback_handler.dart:41). Surface a clear
"sonic analysis incomplete" state rather than silently returning nothing.
**Prerequisite: Plex sonic analysis must have been run, takes hours to days.**

---

## Known caveats

**Albums you do not own are off by default.** One switch in Settings turns on both the
catalog tier of search and the missing-albums grid, and off means off — no client is built,
no request is made, and `downloadMonitorProvider` resolves to null so nothing polls. Settings
are per device, which is the granularity that was wanted.

**The catalog needs one thing only the user can do: a qBittorrent search plugin.** Without
one the search endpoints answer 200 and return nothing, which reads as "nobody is seeding
this" for every album ever asked for. Save and test on the qBittorrent screen reports it.

**Plex records a MusicBrainz id for very few albums, and that is expected.** `Albums.mbid` is
now written where `Guid` or `guid` carries one, and matching falls back to normalised artist
and title everywhere else. No cursor rewind was done for it, deliberately: unlike the v3 and
v7 rating columns, a null here degrades to the path most rows take anyway rather than leaving
a feature looking broken.

**Edition words are stripped from titles before matching, and the list is conservative on
purpose.** Adding a word merges two albums, and the failure that causes — a record you do not
own never appearing in the list of records you do not own — is invisible, unlike the noise it
removes. `_editionWords` in `catalog_matcher.dart`.

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
empty and a delta sync cannot fill them: rating something moves no `updatedAt` at all, which
#52 later confirmed is true of every rating rather than only old ones. Schema v3 rewinds the
delta cursor so the next run does one full pass. Expect a longer-than-usual sync exactly once
after upgrading, then ratings appear on their own.

**A rating does not move `updatedAt`.** Adding music does. So the delta filter is used only
when the section clocks were what triggered the pass; the 15-minute sweep and any forced
refresh go unfiltered, because the edits they exist for move no timestamp at all. Costs a
full pass three times an hour of foreground use, which is what honesty costs here.

**Plex applies `updatedAt>`, not `updatedAt>=`.** Found by reading "Rows in last sync" after
a five-second launch, then settled by the Delta filter probe. `>=` and `>>=` are dropped
silently, `>` and `>>` work. The operator is strict, so `PlexClient` asks one second earlier
than the cursor. Re-run the probe after a server upgrade.

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
metadata edit that produces no such entry, and it moves no timestamp either. The 15-minute
unfiltered sweep catches it; the refresh button catches it now. Accepted rather than fixed:
the alternative is watching another notification type, and James has asked that the sync
logic not grow more paths.

---

## Loose ends

**Not tasks, and deliberately not in either table above** — [Order](#order) is James's and
nothing here has been put in it. This is the list to draw from when picking what is next,
written down so it stops living in one session's head. Each is a real gap with a real
symptom, roughly by how much it would be missed.

**The failure path is gated by the poll, not by the timeout.** With nothing playing, the
only thing making requests is the 30-second poll, so three consecutive failures take a
minute and a half however short the request timeout is. Fine while a transport change is
reported — that path is immediate — and slow in exactly the case that has no OS signal: a
network fading. Probing faster while `ConnectionHealth` is already failing would close it
without adding a mechanism.

**The notification socket drops on a handover and nobody hears it.** It reconnects on its
own backoff and never tells `ConnectionHealth`, so the earliest and clearest evidence that
the network moved is discarded. A candidate *trigger* on the existing path, not a fourth
mechanism (invariant 10).

**"Queued" is never verified.** qBittorrent answers `Ok.` to an add it will later fail, and
the page-URL case is only the one that was found — a dead tracker or a rejected `.torrent`
would look identical. Polling `/torrents/info` for the hash a few seconds after adding would
turn a hopeful message into a true one.

**Artwork that failed while away is not retried in the background.** The `ImageProvider`
retries when a tile rebuilds, so scrolling past it again works, but a shelf you do not
revisit stays blank until something forces it. Worth a sweep, or worth deciding explicitly
that it is not.

**A wrongly matched artist can only be fixed by forgetting every lookup.** Settings has one
button and it clears the lot. A per-artist "not this person" would be a row in
`CatalogArtists` and a menu item, and it is the difference between correcting one page and
re-fetching a library's worth of discographies.

**The version has said 0.9.0 since packaging landed**, through the whole catalog and
acquisition group and four rounds of recovery fixes. `test/packaging_test.dart` keeps
pubspec and `PlexIdentity` in step with each other but neither of them with reality.

**Mouse button five is unbound.** Back is wired, forward is not. Two lines if it is wanted.

**The play history is not filtered to one account.** `/status/sessions/history/all` returns
every user of the server, so on a shared library "Most played in August" counts other
people's listening as well. Harmless on a single-user server and wrong on any other.
`accountID` is the parameter, and finding the right value for the owner is the work.

**Nothing renders the server's own hubs.** `PlexClient.sectionHubs` exists and only
`DiscoveryProbe` calls it. Deliberate: a hub identifier that is present on one server version
and absent on the next is not something to build a row on before seeing what this one has.
Run the probe and the answer decides whether it is worth wiring.

**The two server-backed shelves are fetched once and never again.** They are `FutureProvider`s,
so they resolve on the first Home build of a session and hold that answer until something
invalidates them. A month rolling over, or an hour's listening, will not move "Most played"
until the app restarts. Pull-to-refresh is the obvious place to hang the invalidation.

**The genre row needs the network and vanishes without it.** Genres are not synced into
drift, because they are a many-to-many that would want its own table and its own delta path
for one shelf. The cost is that the row is missing on a cold start off the LAN, where the two
local rows are not.

### Testing gaps worth closing

- **Compact layout navigation is untested.** The pop-to-root behaviour is asserted at
  desktop width only; the phone's `NavigationBar` goes through the same callback but nothing
  proves it.
- **Nothing asserts that the catalog switched off is genuinely off.** The providers return
  early and `downloadMonitorProvider` resolves to null, but no test walks an artist page with
  it disabled — and "unobtrusive on the phone" is the whole point of that switch.
- **The web-page branch of the download sheet has no test.** Tapping one opens a browser
  rather than queueing; the ranking is covered, the tap is not.
- **No test covers a second Plex server**, which is why #42 still wants live confirmation.
  Unchanged, and unfixable without a second server.

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
- **The connection never resolves to null once it has worked.** Only signing out clears it.
  A failed re-resolve keeps the stale address, because no server means no client, no client
  means no requests, and no requests means nothing can ever observe the failure that would
  trigger the next attempt. Written down because "it looks connected but isn't" reads like a
  bug until you know what the alternative costs.
