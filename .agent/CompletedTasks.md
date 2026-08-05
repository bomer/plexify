# Plexify, completed work

The archive. Split out of [TASKS.md](TASKS.md) so that file stays a working document -
what is left to do, and why, without scrolling past everything already done.

Kept rather than deleted because most of these entries record a *decision* and the reason
behind it. Several were bought with a bug. The reasoning is the only thing standing
between the next reader and paying for it twice.

**Last updated:** 6 August 2026 · **39 complete**

---

## Complete

| # | Task | Notes |
|---|---|---|
| 1 | Install Flutter SDK | 3.44.8 stable at `C:\Users\James\flutter-sdk\flutter` |
| 2 | VS C++ toolchain | Already present, VS 2026, no install needed |
| 3 | `flutter doctor` clean | Windows + Android both green |
| 4 | Scaffold project | `C:\dev\plexify`, app id `com.jamesotoole.plexify` |
| 5 | Plex PIN auth + discovery | Live-verified. Wave racing: LAN → remote → relay |
| 6 | Album list from Plex | Live-verified |
| 7 | Direct-play audio | Live-verified, Windows and Android |
| 8 | Transcode spike | Answered on both routes by `TranscodeProbe`, kept in the app under Sync status. Progressive works; `offset` works; **no bitrate control exists**. Parameter set and consequences in [PROJECT.md](PROJECT.md#the-music-transcode-endpoint) |
| 9 | Windows Developer Mode | Enabled |
| 11 | Live-verify vertical slice | Auth, browsing, playback confirmed |
| 12 | Routing so mini player is never covered | Nested `Navigator`; `PopScope` minimises instead of exiting |
| 13 | Now Playing overlay with seek | Sibling `Stack` layer, not a route, page beneath stays mounted |
| 14 | Android background playback | Verified on OPPO CPH2791 / Android 16. Four bugs found |
| 15 | drift schema and codegen | Six tables, normalised search columns, sync state |
| 16 | Paginated initial sync | Three passes plus playlists. Live-verified |
| 17 | Websocket push sync | `dart:io` socket, backoff reconnect, reconnect on resume. Live-verified, a new album appears instantly |
| 18 | Change-detection poll and delta sync | 30s poll on `/library/sections`, wake on resume, pull-to-refresh. Schema v3 rewinds the cursor once |
| 20 | UI reads from drift, additively | Grid streams from cache; sort by added/title/artist |
| 21 | Artwork disk cache | Hand-rolled over `path_provider`, keyed on `(thumb, size)` so a token refresh or a re-race is a hit. Custom `ImageProvider`, LRU-bounded, prefetch via `scrollCacheExtent` |
| 23 | Transcode-or-direct-play | Binary, per #8, no bitrate anywhere in the type. Three signals kept apart: connectivity, server locality, source rate. Schema v4 adds the part size. Seeking a transcode reloads at `offset=`; the handler holds the difference |
| 25 | Timeline reporting and scrobbling | `/:/timeline` every 10s and on every state change, `/:/scrobble` once past 90%. Writes `lastViewedAt` locally so Home updates immediately. Live-verified, Plexify appears in the Plex dashboard |
| 26 | Sidebar with recent playlists | Recents beneath the destinations; bottom nav under 800px |
| 27 | Home screen and browsing | Jump back in / recently added / favourites. Artist pages with albums *and* tracks, library toggle |
| 35 | Star ratings and favourites | Write-through to `/:/rate`, optimistic with revert. Favourite = 4★+ |
| 36 | Smart playlist support | `smart` flag stored and badged; contents always revalidated, never served from cache |
| 37 | Windows media keys | SMTC in the C++ runner. Verified end to end with synthetic key presses |
| 38 | Compact track rows | Per-track stars are desktop-only; long press opens a rating sheet on phones |
| 39 | Sync status screen | Socket/poll/clock state, row counts, sync now and full resync. Poll pauses off screen |
| 40 | A–Z artist index | Letter headers and a jump rail. Articles stripped, matching Plex `titleSort` |
| 41 | Reconnect when the network changes | Two triggers, one path: transport change and a run of failed requests. Sticky last-good address, manual reconnect in Sync status |
| 42 | Sign out and switch server | One teardown, two endings. Wipes the cache eagerly and stops the writers first. Chosen server is binding, no fallback. Found and fixed a `stop()` that always threw |
| 43a | Settings shell | Fourth destination, bottom of the sidebar. Sync status moved inside it. `SettingsStore` over `shared_preferences`; theme mode is the first setting through it |
| 28 | Instant local search | drift on every keystroke against the normalised columns, merged with `/hubs/search` so an album added minutes ago is still findable. Sectioned artists / albums / tracks |
| 24 | Audio disk cache | `LockCachingAudioSource` with an explicit cache file keyed `(ratingKey, decision)`. LRU by bytes, never evicts a file the queue holds, fills on wifi or ethernet only, refuses a URL carrying a seek offset |
| 44 | Now Playing navigation test | Pumps the real `AppShell`, opens an album, scrolls it, expands the overlay. Asserts both are mounted at once and that the scroll offset survives being covered |
| 45 | Restore what was playing on launch | Queue and position persisted on change, on a 10s tick and on the way out; restored **paused**. Facts stored, never URLs, quality is decided fresh against the network at launch |
| 46 | "Jump back in" shows albums and playlists | Client-owned `PlaybackHistory` (schema v5), stamped on playback *start*. Replaced `Albums.lastViewedAt`, which is Plex's: written only at 90%, and rewritten by every sync |
| 47 | Rescue the queue when the connection moves | Whole queue rebuilt at the current position on a re-resolve, quality decided again. Playback failure reports to `ConnectionHealth`, which nothing could see before. A same-address reconnect now does nothing |
| 48 | Desktop and mobile UI fixes | Mouse-scrollable shelves with a scrollbar, hover play on covers, "Reconnecting..." in the mini player; fixed its doubled height and the album header's star overflow |

---

## Bugs found by device testing (#14)

All four were release-only or device-only and would have shipped:

1. **`INTERNET` missing from the main manifest.** Flutter only injects it into debug and
   profile manifests, so release builds had no network at all.
2. **`POST_NOTIFICATIONS` never requested.** `audio_service` declares it but never prompts.
3. **`androidStopForegroundOnPause: true`** deleted the notification on pause, controls
   vanished exactly when you'd reach for them.
4. **`audio_service` 0.18.19 throws on Android 13+.** It converts `MediaControl.stop` into a
   `CustomAction` requiring a non-zero icon, resolves that icon by name against *our*
   package, gets `0`, and throws, killing the whole notification. Removed that control.

---

## Detail

Only tasks whose reasoning outlives them. The rest are the table above.

### #8, Transcode spike *(done, 5 Aug 2026)*

Answered by `TranscodeProbe`, which stays in the app under Sync status → Transcode probe
rather than being deleted: the answers are per-server and per-route, and it is the cheapest
way to re-check after a Plex upgrade. Full parameter set and reasoning in
[PROJECT.md](PROJECT.md#the-music-transcode-endpoint).

**The three findings that change other tasks:**

1. **Progressive works.** `audio/mpeg`, no HLS. Risk #1 in the plan is retired and #24 is not
   LAN-only.
2. **The `X-Plex-*` identity must be in the query string**, or the endpoint answers 400 with
   no explanation. The headers `PlexClient` already sends do not count, the URL goes to the
   audio engine, which sends none of them.
3. **No bitrate control exists.** Three mechanisms, both routes, no change; Plex's own session
   record has no bitrate field. This makes #23 materially smaller than planned.

**What it did not answer:** the relay route was never exercised, because discovery picked
local then remote and never fell back. If relay ever becomes the working route, re-run there
before trusting any of this.

### #43a, Settings shell *(done, 5 Aug 2026)*

A fourth [`ShellDestination`](../lib/shell/shell_destination.dart), not a pushed route, so
Settings keeps its own navigation stack: open Sync status, switch to Library, come back, and
you are still on Sync status. In the sidebar it is pinned below the playlists rather than
listed with the other destinations, it is the one you reach occasionally, and putting it
above the playlists would push the thing you reach constantly further down.

**Sync status moved inside it.** It was reachable only from an `info` button beside Refresh
in the Home app bar, which is not where anyone looks for a diagnostic. That button is gone,
and [settings_screen.dart](../lib/features/settings/settings_screen.dart) is now the only
route to it, which is what the test in `settings_test.dart` guards.

**The persistence seam** is [app_settings.dart](../lib/core/settings/app_settings.dart):
`AppSettings` (one immutable value), `SettingsStore` (`shared_preferences`), and
`SettingsController`. Adding a setting is three edits and no more, a field, a key, a setter -
and every mutation goes through `_apply`, so there is exactly one place that writes to disk.
That matters more than it looks: a setter that changes the state and forgets to persist works
perfectly until the next launch.

Read **synchronously**. `SettingsStore.load()` is awaited in `main()` alongside the identity
and the audio handler, and `settingsStoreProvider` is overridden the same way, so the first
frame is already correct. Loading settings lazily would paint the default and then swap,
which is a visible flash on every cold start.

**Sections shipped: Account, Appearance, Sync, About.** Playback and Storage are *not* here,
despite being in the original plan for this task, there is nothing yet for them to control,
and a screen of controls that change nothing looks finished, so nobody notices the wiring is
missing. They arrive with #43b.

Theme mode is the first real setting, and deliberately so: it removes a hardcoded
`ThemeMode.dark` from `app.dart`, so the store is exercised by something that reads it rather
than shipping as untested infrastructure. Stored by **name**, not index, a `ThemeMode` that
gained a value or reordered under an SDK upgrade would otherwise silently change the theme.

### #42, Sign out and switch server *(done, 5 Aug 2026)*

Both live in [account_controller.dart](../lib/features/settings/account_controller.dart), and
they are **one operation with a different last step** rather than two. Signing out ends with
deleting the token; switching ends with recording a preferred server. Everything before that
is shared, which is the part with an order that matters.

**The teardown, in the order it has to happen:**

1. `reportStopped()` to Plex, with a 2-second cap, while the client still works. Skip it and
   the dashboard shows Plexify playing until the server times the session out.
2. `PlexifyAudioHandler.clearQueue()`. Nothing in the provider graph does this: the audio
   handler is a root object that outlives every connection. Without it the mini player keeps
   showing the last track, because it hides on a null `mediaItem` and on nothing else.
3. Stop the scheduler and the notification socket.
4. **Then** wipe the cache.

Step 3 before step 4 is not tidiness, and there is a test that fails if they swap. Either
writer can put rows back *after* the wipe, the scheduler may be mid-pass, the socket can
deliver a push at any moment, and nothing downstream would ever notice, because the reset in
`LibrarySync` only fires when it sees a *different* server, and by then `syncState` is gone.

**Why the wipe happens here at all.** `LibrarySync._resetIfServerChanged` already wipes on a
server change, but only *during a sync*. Between switching and that sync finishing, the album
grid streams the previous server's rows, and because the cache is non-empty it does not fall
through to a live read, so you browse a library that is not there and every tap 404s. Eager
wiping is what closes that window.

**Choosing a server is binding.** `AppSettings.preferredServerId` holds a `clientIdentifier`;
`connectServerProvider` watches it, so setting it re-resolves on its own. When it is set,
*only* that server is tried, no fallback. Falling back would be actively harmful: two
libraries with overlapping ratingKeys would wipe each other's cache on every swap, so a
server that comes and goes would leave the app thrashing between full syncs. Null, the
default, and the only state on a single-server account, keeps the original behaviour of
taking whichever answers first.

The last-good sticky address is dropped whenever it is not the chosen server, or a preferred
server that failed to answer would be handed straight back.

**Found on the way:** `PlexifyAudioHandler.stop()` threw every time it was called.
`BaseAudioHandler.stop` pushes an idle state into `playbackState` by hand, and this handler
feeds that same subject from the player via `pipe`, rxdart refuses a manual `add` while a
stream is piping in. It was reachable in production from the Windows media-key **Stop**
button. The `super.stop()` call was also redundant: stopping the player emits idle through
the pipe anyway.

### #21, Artwork disk cache *(done, 5 Aug 2026)*

**Hand-rolled**, in [artwork_cache.dart](../lib/core/artwork/artwork_cache.dart) and
[artwork_image.dart](../lib/core/artwork/artwork_image.dart). `cached_network_image` was
rejected on both of its own terms: it keys on the URL, which is the one thing this cache must
not do, and it brings `flutter_cache_manager` and `sqflite`, a second SQLite binding into an
app that already ships drift and has to work on Windows. Fetch bytes, write a file, delete
the oldest is a small enough job to own.

**The key is `(thumb, size)` and nothing else.** The artwork URL embeds the base address and
the token, and both move, the token on refresh, the address every time the connection
re-races. A URL-keyed cache looks perfect on a desk and misses on every visible thumbnail the
moment you walk out of the house, which is when it is most needed. Tests cover a changed
token and a changed address both being hits.

`PlexArtwork` is an `ImageProvider` rather than bytes behind a `FutureBuilder`, which buys
the same key in Flutter's in-memory `ImageCache`: one decode shared across every cell showing
that album, surviving a reconnect. `Image.memory` keys on the byte list's identity and would
re-decode on every rebuild.

**The URL is not part of the key and is only consulted on a miss**, so a cached grid draws
with no connection at all. `Artwork` passes null while disconnected instead of giving up.

Bounded at 64 MB on Android and 256 MB elsewhere, evicted least-recently-**used**. The index
is in memory, rebuilt from the directory on first use, and nothing about it is persisted:
after a restart the order falls back to file modification time. That is close enough for
artwork and keeps a database write out of every scroll frame.

Prefetch is `scrollCacheExtent: ScrollCacheExtent.viewport(1)` on the album grid. Building a
tile is what starts its image load, so a screen of rows built ahead *is* a screen of artwork
already fetching, a scroll listener calling `precacheImage` would only duplicate machinery
the framework already has.

Signing out clears it too: thumb paths are server-scoped, so the same path on another server
is different art.

**Found on the way:** injecting a directory for tests skipped the index rebuild, so an
injected cache never saw its own files. The cold-start path was the one thing tests could not
reach, which is the path most likely to be wrong. `_override` now says *where*, not *whether
to scan*.

### #23, Transcode-or-direct-play *(done, 5 Aug 2026)*

[quality_policy.dart](../lib/core/audio/quality_policy.dart) is thirty lines of decision and
the rest is the plumbing that makes the decision reachable. #8 had already established there
is no bitrate to adapt, so the type is an enum of two values and contains no number at all.

**Three signals, kept apart deliberately.** Collapsing them into one "am I at home" flag is
the obvious simplification and it is wrong in both directions. *Connectivity* is what this
device is paying for, a laptop on a phone's hotspot reports as wifi and is still metered.
*Server locality* is what the request reaches the server through, a relay is
bandwidth-limited by Plex on top of whatever the local network is doing, so it transcodes
even on wifi. *Source rate* overrides both: transcoding a file already at the transcoder's
own output spends more data for worse audio, so it direct-plays on any connection.

**The source rate had to be added to the schema.** Plex sends no bitrate, only Media > Part's
`size`, which `PlexTrack.sourceKbps` divides by the duration. Schema v4 carries it. Unlike
v3 it does *not* rewind the sync cursor, because a null degrades safely: `QualityPolicy`
reads null as "nothing measured yet" and behaves exactly as it would have before the column
existed. Reading it as "below the floor" would pin every unsynced track to direct play on
cellular, the expensive direction to be wrong in.

**Seeking was the largest part of the work**, and the task listed it last. A transcode
answers 200 to a ranged request and declares no length, so there is nothing for the player to
seek within; the only handle is `offset=`, which starts a fresh transcode partway in. So
`seek` reloads the stream and the handler remembers where it began, adding the difference
back in `position` and `_toPlaybackState`, see invariant 11. The queue keeps its
offset-zero URLs so a second seek measures from the start of the track rather than compounding
on the first, and the session id is reused so Plex replaces the stream instead of leaving the
old transcode running for nobody.

**Sessions are torn down where they become unreachable**: replacing the queue stops the
previous batch's, and losing the connection stops whatever is still open. Plex does not stop
them on its own, and an abandoned one keeps the server encoding into a buffer nobody reads.

**Found on the way, by a fake that had to be built first.** `flutter test` has no platform
channels, so everything reaching `AudioPlayer.load` threw `MissingPluginException` and the
handler's logic was untestable, which is why it had no tests to begin with.
[fake_just_audio.dart](../test/support/fake_just_audio.dart) implements
`JustAudioPlatform` in Dart, and the first thing it caught was a real bug: reloading a stream
re-emits `currentIndex`, which fired the track-change reset and wiped the seek that had just
been performed. Every position after a seek would have read as zero, a silent failure, since
the audio plays correctly and only the progress bar and the scrobble threshold are wrong.

Migration tests needed the same honesty: `NativeDatabase.memory()` creates the schema at
head, so `onUpgrade` re-ran DDL for a column that already existed. They now drop it first,
and pass the real head as `to` rather than an intermediate version the code never sees.

---

### #28 - Instant local search *(done, 6 Aug 2026)*

The placeholder screen made the app feel unfinished, and the pieces were already there: the
normalised columns and their indexes were added in #15 for exactly this.

**Local first and independently.** drift answers on every keystroke with no round trip, which
is what makes typing feel instant. The server is asked as well, debounced, and merged in
behind, deduplicated on ratingKey. That is invariant 1 in practice rather than in principle:
the cache may answer *faster* but must never be why something appears missing, and an album
added five minutes ago has to be findable before any sync has stored it. `searchHubs` returns
empty rather than throwing, so search still works offline for the library you have.

**`contains` rather than `startsWith`**, which gives up the index for a table scan. The right
trade at this size, and the alternative is a full-text index to maintain on every sync write.

**One real limitation, recorded rather than papered over:** `Tracks` has a normalised title
but no normalised artist, so searching an artist name returns the artist and their albums but
not their tracks. Adding `normalisedArtist` to `Tracks` is what would change it. There is a
test asserting the current behaviour so the next reader knows it is known.

### #24 - Audio disk cache *(done, 6 Aug 2026)*

`just_audio` does the downloading: `LockCachingAudioSource` streams and writes the file as
the track plays, so a first listen costs nothing extra. What this owns is *where* each track
goes, how much space the whole thing may take, and what gets deleted when it takes too much.

**Keyed `(ratingKey, decision)`**, which is invariant 2 and was written down before the cache
existed precisely because it is invisible once broken. A direct-played FLAC and a transcoded
mp3 of one track are the same music and completely different bytes.

**Four reasons it declines to cache**, and each is a bug if got wrong. A URL carrying an
`offset` is the tail of a transcode rather than the track, and stored under the track's key
it would be served next time with the first two thirds missing. A metered connection, because
the caching source downloads the *whole* file even when you skip after ten seconds. A missing
key, because the only other thing to name a file after is the URL, which is invariant 4. And
a cache that could not open, which falls back to streaming exactly as playback worked before.

**Eviction never touches a file the queue is holding.** `LockCachingAudioSource` keeps the
handle for the life of the queue entry and writes to it as the track streams; deleting
underneath it truncates the download and the track stops mid-play with nothing pointing at
the cache as the cause. Replacing a queue releases the old claims, or every track ever played
would be pinned for the session and the budget would mean nothing.

Sizes are read off disk after the queue lands rather than tracked as bytes arrive, because
the writing belongs to just_audio and it reports nothing useful about partial files. That
pass runs after playback has started, deliberately: nothing about the filesystem should delay
the first note.

**It does not work on Windows, which is now measured rather than suspected.** The plan
flagged it as a genuine unknown and the answer is no. `LockCachingAudioSource` renames
`X.part` to `X` on completion while still holding the file open to serve the engine; Windows
forbids that, so every track failed with `errno 32` and took its audio source down with it.
Skipping forward then found a dead local server and playback stopped, which is worse than
having no cache at all. It is now mobile-only. Full detail in
[PROJECT.md](PROJECT.md#traps-already-paid-for).

### #44 - Now Playing navigation test *(done, 6 Aug 2026)*

docs/PLAN.md calls this invariant non-retrofittable and it had no guard, while the shell was
touched repeatedly. The test pumps the real `AppShell` rather than a stand-in, because the
thing under test *is* the shell's structure: Now Playing as a sibling `Stack` layer instead
of a pushed route.

Two things made it awkward, both worth knowing before writing another shell test.
`AudioPlayer` initialisation waits on locks that never resolve inside `testWidgets`'
fake-async zone, so the handler has to be built in `tester.runAsync`. And
`networkChangesProvider` reaches a platform channel, so it needs overriding with an empty
stream or the shell will not build at all.

Verified by regression rather than by passing: replacing the content with the overlay makes
two of the four fail. The other two cover the nested navigators, which that particular
sabotage leaves alone. Worth noting the first attempt at the sabotage changed the *narrow*
layout branch while the test runs wide, so it proved nothing until it was aimed properly.

### #45 / #46 - Playback memory *(done, 6 Aug 2026)*

Two halves of "what was I listening to", and both first attempts were wrong the same way:
they leaned on something Plex owns.

**#45** persists the queue as *facts* - ratingKey, partKey, sourceKbps, thumb - never URLs. A
playback URL embeds the server address and the token and both move, so a stored one is dead by
the next launch and fails in the least debuggable way there is: a queue that restores looking
perfect and will not play. Rebuilding also means quality is decided against the network the app
has now. Restored **paused**, because opening an app is not asking it to make a noise.

**#46** was reported twice before it was right. The shelf read `Albums.lastViewedAt`, which is
Plex's column and wrong on two counts: it is written at the 90% scrobble mark, so putting a
playlist on and quitting two minutes later recorded *nothing* - the shelf sat on an album from
half an hour earlier - and it is rewritten by every sync, so an album Plex stamped server-side
came straight back however carefully the local write was suppressed. The intermediate fix
(credit the playlist, skip the album) could not have worked; the sync undid it.
`PlaybackHistory` is client-owned, stamped on *start*, one row per `(kind, ratingKey)`.

**Position is written on the way out**, not only on the ten-second tick - before the goodbye to
Plex, since that call is capped at two seconds against a server that may have stopped answering.
Also on leaving the screen, because Android routinely kills the process without calling
`onDetach`.

**Upgrading wipes the shelf once.** v5 creates the table empty and the shelf no longer reads the
old column. It refills from the next thing played. Not backfilled from `lastViewedAt`
deliberately - those timestamps include plays from other clients and from before Plexify
existed, which is not what the table means.

### #47 - Queue rescue on reconnect *(done, 6 Aug 2026)*

Walking out of the house stopped playback and skipping forward found one dead track after
another. Three causes compounded, and the note in PROJECT.md described only one of them - and
described it wrongly, claiming the next track picks up the new address. It does not: the whole
queue is handed to the engine up front, so every URL dies at once.

The queue is now rebuilt in place at the current position, from its own `extras` rather than
from Plex or drift - this runs when the connection has just failed, which is the worst moment to
need a round trip. Playback failure reports to `ConnectionHealth`; the audio engine does its own
HTTP, so nothing else in the app could see it and the reconnect waited on the 30-second poll.
And a re-resolve onto the *same* address now does nothing at all, which is what most reconnects
are - that one also fixed a startup race where the restore and the rebuild aborted each other
with "Loading interrupted".

### #48 - UI fixes *(done, 6 Aug 2026)*

Found by using it rather than by testing it, which is the point.

- **Shelves would not scroll with a mouse.** Three separate reasons: a wheel emits a vertical
  delta and `Scrollable` only applies deltas along its own axis; Flutter excludes mice from
  `dragDevices`; and nothing said the row moved. `HorizontalScroll` handles all three.
- **The mini player was twice its needed height on mobile**, reserving the bottom system inset
  while sitting *above* the navigation bar that owns it.
- **The album header's stars overflowed at 360dp.** `IconButton` enforces a minimum tap target
  regardless of `iconSize`, so five stars are ~200px against a 192px column. `StarRating` now
  scales to fit its parent rather than a screen-width breakpoint.
- **Artwork went through three different paths.** Album header, mini player and Now Playing each
  called `Image.network`, bypassing the cache. All now go through `Artwork`; the player surfaces
  reach it via `extras['thumb']`. Fetches are gated to four at a time with one retry, which is
  the likeliest cause of thumbnails appearing in a random scatter.

---

## Still wanting live confirmation

Done in code, and neither can be confirmed from a test:

- **#41**, walk out of the house mid-track, then read "Route" and "Reconnects" on the Sync
  status screen. There is a Reconnect button there that exercises the same path indoors.
- **#25**, play a track to the end, then check Plex web → Status → Now Playing shows
  Plexify while it runs, and that the play count moved afterwards. "Plays recorded" on the
  Sync status screen says what the app thinks it sent.
- **#42**, the switch-server path has never run against a second server, because the account
  has one. Tests cover the binding behaviour and the wipe; two real servers do not exist to
  try it on.
- **#46**, whether the shelf now moves. It should update the moment something starts, and
  a Plex sweep should no longer be able to put an old album back on it. Both were the bug.
- **#23**, three things a fake engine cannot answer. That a Plex transcode actually *plays*
  through libmpv on Windows and ExoPlayer on Android, rather than merely being requested;
  that seeking one lands where the scrubber was dropped and does not stall; and that the
  policy picks transcode at all off the LAN, which needs the phone off wifi. "Route" on the
  Sync status screen says which connection is in use, and Plex web → Status shows whether
  the server thinks it is transcoding.
- **#21**, the payoff is a cold start that does not refetch every thumbnail. Visible on the
  phone, not assertable here.
