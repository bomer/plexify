# Plexify, completed work

The archive. Split out of [TASKS.md](TASKS.md) so that file stays a working document -
what is left to do, and why, without scrolling past everything already done.

Kept rather than deleted because most of these entries record a *decision* and the reason
behind it. Several were bought with a bug. The reasoning is the only thing standing
between the next reader and paying for it twice.

**Last updated:** 10 August 2026 · **59 complete**

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
| 22 | Queue controls | Shuffle and repeat overridden and published, with controls in Now Playing. Up Next reorders by drag handle and removes by swipe, engine and published queue moved together |
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
| 49 | Rate artists | Artist ratings are Plex's, on the same `/:/rate` endpoint. Reading was already wired; writing was not, so a rating would sync in and never out. Stars on the artist page, schema v7 rewinds the cursor so existing ones arrive |
| 34 | Packaging and release | Real signing config that falls back to the debug key loudly, generated icons on both platforms, `tool/package.ps1` that refuses a debug-signed or oversized build. Version unified at 0.9.0 |
| 43b | Settings: playback and storage | Quality override per connection, which *is* the data saver, there being no bitrate to lower. Both cache budgets, live usage, and one clear button. Budgets push into the running cache rather than rebuilding it |
| 29 | MusicBrainz "Not in your library" | Paced at 1.1s through one serialised chain and a user agent naming the app and a contact — MusicBrainz answers **503** for either rule and says which for neither. Answers cached in drift for a week (schema v9) and deliberately *not* cleared on sign-out: MBIDs are global, unlike ratingKeys. A separate provider from local search on purpose, so the fast half never waits for the slow half |
| 30 | De-duplicate catalog results | MBID where Plex recorded one, which is a minority of rows, otherwise normalised artist and title with *edition* qualifiers stripped. Only recognised edition words go: stripping every bracket is one line shorter and wrong in both directions — it makes *(What's the Story) Morning Glory?* differ from itself and collapses *Greatest Hits (Volume 1)* into *(Volume 2)*, so owning one hides the other, invisibly |
| 32 | qBittorrent client | Form login → `SID`, one auth layer. `Referer`/`Origin` derived from the configured address so they cannot drift from `Host`; a trailing slash trimmed in the setter, since it breaks that check specifically. A 403 during login **latches** rather than retrying — the client cannot tell a ban from a wrong password, and retrying is what extends a ban. A rejected password is a 200 whose body is `Fails.` Searches are always deleted; leaked ones cap out the server |
| 33 | Acquisition flow | Query built from MusicBrainz's fields, not the typed string; the year scores rather than filters, because torrent names carry it about half the time. Ranking is a pure function: confident matches first, then format and diminishing seeders. One click queues **only** when the filename names this artist and this album, otherwise the list opens — seeder count measures popularity, never correctness. `DownloadMonitor` turns a completion into the existing refresh path, adaptively polled and null unless configured |
| 54 | Missing albums on the artist page | A discography subtracted from what you own, studio albums and EPs only. Artist resolution refuses to guess: an exact name wins, an inexact one needs a 90+ score, and everything else resolves to nobody and is *cached* as nobody. Taking the top hit attaches one artist's records to another's page and offers to download them |
| 50 | Stop resyncing the library on every launch | Plex ignores `updatedAt>=`, so a forced launch pass plus an in-memory sweep clock meant 13,704 rows and ~70 requests every time. Schema v8 persists the clock; `start` asks instead of forcing. Ships the probe that will settle the filter itself |
| 51 | Use a delta filter Plex honours | `updatedAt>` works and `updatedAt>=` never did. Strict, so the client asks a second earlier than the cursor. Took two probe runs and one corrected verdict rule |
| 52 | Filter the poll, never the sweep | A rating moves no timestamp, so a filtered sweep cannot find the one thing it exists for. Sweep and forced refresh go unfiltered, interval 5 → 15 min. The fake server now applies the filter, which is why the guard is real |
| 53 | Recover from a handover that lands nowhere | A sticky re-resolve was clearing the failure streak, and the audio cache's own HTTP client was invisible to everything. Together they left playback dead until a restart |
| 61 | Detail pages lose their app bar | The bar held one control and a copy of the title printed six lines below it, and cost a band of chrome plus a hard line straight across the gradient, which is the part of the page actually worth looking at. Back floats over the top-left instead, pinned rather than scrolled with the header, with its own scrim so it stays legible over a light sleeve. Album and playlist only: the artist page's collapsing hero is already the treatment this is reaching for, and Home keeps its bar because James wants the breathing room there |
| 60 | Playlist page shaped like an album page | The sidebar shows a playlist's mosaic and opening one landed on a bare list with no artwork at all, which read as the wrong screen having loaded. Same header shape as the album page down to the cover size: mosaic, title, kind, songs and running time, Play. Rows numbered by position, since a playlist's order is an arrangement rather than a pressing. Six tests, because "the header is there" is obvious in a screenshot and invisible in a diff. Also collapsed the third copy of the clock formatter |
| 59 | Visual pass: neutral chrome, depth, content colour | The window had a blue cast nobody chose, because M3 tints greys with the seed twice over: `fromSeed` leaves chroma in the surface palette, and `surfaceTint` then blends primary in again per elevation. Overriding the surface family to true neutral and spreading the values apart is the change that made it stop looking like a default Flutter project. Then depth on covers so artwork reads as objects rather than as texture; section headers with enough weight to bind to their row; the Now Playing gradient generalised to album and artist pages so every screen is coloured by its own content; a neutral play button, since an accent disc inches from the sleeve is chrome arguing with content; playlist thumbnails in the sidebar; one larger shelf so the page opens on something. Deliberately not reclaiming the app bar: James likes the breathing room |
| 58 | Window geometry, playlist sort, sidebar count | Five small things. The window is remembered in the registry from the C++ runner rather than from Dart, so it is the right shape in the first frame instead of jumping once the engine has read a preference; `GetWindowPlacement` so closing maximised does not store the screen as the normal size, and a check that the frame still lands on a monitor that exists, or a window closed on a since-unplugged screen launches invisible. Playlists sort by recent or by name, with smart ones grouped first under either name order because that is when you are hunting rather than returning. The Favourites tab is gone: Artists and Albums each carry the filter, so it was a fourth place to go for a question the other three already answered. **Favourite tracks lost their only view with it.** Sync status now shows Plex's own counts beside the cached ones and names every music library, because the sync reads the first one only |
| 57 | Volume on the desktop bar | Desktop only, because a phone's hardware keys and OS mixer already own the level and a second app-local one is a way for it to be wrong somewhere nobody looks. Persisted, or the slider reads full every launch. Follows the engine rather than the setting, so the control cannot lie about what is making the sound. Mute remembers where it was, since dragging to zero and pressing the speaker are the same state to the player |
| 56 | Desktop transport bar, Spotify-shaped | Two shapes rather than one that stretches: the phone bar is untouched, the desktop one is three columns with the transport centred against the window and a real scrub bar on it. Left and right carry equal flex, or a long title pushes the play button off-centre and moves it on every track change. Now Playing's sleeve drops to 300 logical, because 420 against a 600px source is a third of upscaling in the place it is looked at hardest, and gains a gradient taken from the artwork's own colours by histogram rather than by averaging, which returns grey for every record ever pressed |
| 55 | Discovery shelves on Home | Four rows Plex does not publish, because it publishes almost nothing: two computed from the local cache and on screen before the first frame, two from the server and absent when it says no. "Most played in {month}" is counted from `/status/sessions/history/all`, which is the endpoint Plexamp's equivalent row and Plex Web's history both read, and which needs owner access and answers everyone else with an empty container rather than a 403. Ships `DiscoveryProbe` under Sync status, because what a given server offers here is a measurement, not a fact |

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

### #22 - Queue controls *(done, 6 Aug 2026)*

Four things, three of them shipped and the fourth still owed to a pair of ears.

**Shuffle and repeat** are declared by `BaseAudioHandler` and were never implemented, so the
lock screen offered controls that did nothing. Both are overridden, published in the reported
state, and now have buttons in Now Playing. Publishing is the part that matters: the lock
screen renders whatever the state says, so setting the engine without publishing shows the
wrong icon for ever, which reads as a broken button. The controls read their state from the
session rather than holding their own boolean, or they would disagree with the lock screen
the first time either was used.

That needed `playbackState` to have a **single writer**. It was fed directly by `pipe`, which
is `addStream`, and rxdart refuses a manual `add` while a stream is being piped in. The same
trap broke `super.stop()` earlier in the project and is recorded in PROJECT.md; I walked into
it again anyway. Player events and mode changes now both go through one controller.

**Reorder and remove** move the engine's playlist and the published queue together. They have
to: the engine plays by index and `queue` is what every screen and the lock screen render, so
a mismatch means tapping the third row plays the fourth track, and nothing throws when it
happens. Only the tracks *after* the current one are offered, and `removeQueueItemAt` refuses
the playing track outright, because swiping a row further down the list must never stop what
you are listening to. Dragging uses an explicit handle rather than long-press, since the rows
are tappable and a long press that sometimes plays and sometimes lifts is worse than a grip
you can see.

`onReorderItem` rather than the deprecated `onReorder`, which reported the destination as an
index in the list *before* the dragged item was removed and left every caller to correct for
it.

**Gapless is still unverified.** It cannot be tested from Dart: `setAudioSources` hands the
engine the whole list at once so it can pre-buffer, which is the mechanism, but whether there
is an audible seam between two consecutive album tracks is a question for a pair of ears on
each platform.

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

### #53 - Recover from a handover that lands nowhere *(done, 6 August 2026)*

Reported as "I switched wifi to 5G and now nothing will play", guessed as a cache problem,
and settled by logcat rather than by guessing. Two faults, and the app needed both to get
stuck.

```
19:17:17  ExoPlayerImplInternal  Playback error ... SocketTimeoutException
19:17:17  ExoPlayerImpl          Release
19:17:40  flutter  Proxy request failed: SocketException: Network is unreachable,
                   address = 192-168-0-2...plex.direct, port = 32400   (x5)
19:17:40  flutter  Unhandled Exception: SocketException ...
```

**The re-resolve landed back on the dead address, and that counted as success.** Discovery is
deliberately sticky: with nothing reachable it keeps the last address that worked, which is
right in general and exactly wrong here. `ConnectionMonitor` called `_health.reset()` on any
completion, so the failure streak that had triggered the attempt was wiped, and the cooldown
held off the next one. On a handover the re-resolve fires while the OS still reports the old
transport, finds nothing, and keeps the LAN address. `reconnect` now returns **whether the
address changed**, and the streak survives when it did not.

**And then nothing could fail.** `LockCachingAudioSource` runs a loopback server and fetches
bytes itself, in Dart. Those failures reach neither `errorStream` nor
`HealthReportingClient`, so `ConnectionHealth` observed nothing and no further attempt was
ever triggered. That the rebuild used the cache at all is itself informative: `_cacheFile`
only returns a file on an unmetered connection, so Android was still reporting wifi seconds
after it had gone. `playbackRecoveryProvider` now installs a
`PlatformDispatcher.instance.onError` hook routing a `SocketException` into
`recordUnreachable`, returning false so Flutter still reports it. It observes; it does not
swallow.

This is invariant 10 read backwards: **a recovery mechanism driven by failures must leave
something running that can still fail.** #47 covered the ExoPlayer path, and the cache did
not exist yet when it landed.

---

### #52 - Filter the poll, never the sweep *(done, 6 August 2026)*

Reported an hour after #51 shipped: a favourite set on the phone showed there and never
reached the desktop, not even on manual refresh. It was a regression from #51, and the
mechanism is worth stating exactly because it is not obvious.

**Plex moves a row's `updatedAt` when music is added and leaves it alone when a rating
changes.** Measured with the probe: rate an album, and Albums-changed-in-the-last-five-minutes
stays at zero, while an album *added* shows up immediately.

While the filter was being ignored, every sweep was accidentally a full pass, so ratings
arrived by brute force and nobody knew the sweep depended on that. The moment the filter
started working, the sweep kept running, kept costing requests, and became structurally
incapable of finding the only thing it exists for.

So the filter is applied per pass, by trigger:

| Trigger | Filtered | Why |
|---|---|---|
| Section clock moved | **Yes** | Whatever moved the clock moved the row's timestamp. Seventeen rows instead of thirteen thousand |
| Periodic sweep | **No** | It exists for edits that move no timestamp |
| Forced refresh / full resync | **No** | The point of the gesture is to override our judgement |

`deltaInterval` goes 5 → 15 minutes, because an unfiltered pass over 11.5k tracks is about
seventy requests and three of those an hour is defensible where twelve is not. Nothing waits
on it that matters: new music still arrives by push in under a second, and the refresh button
forces a pass immediately.

**The test that should have caught this was vacuous.** `sync_scheduler_test.dart` had a test
called "a rating set in Plex arrives even with the section clocks still", and it passed
throughout, because the `MockClient` returned its canned album regardless of any filter in the
request. A fake server that answers the same however it is asked is not testing the question.
It applies the filter now, and the album in that test carries an `updatedAt` *below* the
cursor, which is what a real unmoved rating looks like. Three tests fail if the sweep starts
using the cursor again, verified by making it do so.

---

### #51 - Use a delta filter Plex honours *(done, 6 August 2026)*

**`updatedAt>` works. `updatedAt>=`, which this app had sent since #18, never did.**

The probe took two runs, and the first one nearly produced a much worse bug than the one being
fixed:

| | 1 minute | 10 years |
|---|---|---|
| `updatedAt>=` | 11,492 | ignored |
| `updatedAt>>=` | 11,492 | ignored |
| `updatedAt>` | 0 | 9,988 |
| `updatedAt>>` | 0 | 9,988 |

The first run measured only the left column. Read from that alone, `>` returning zero is a
perfect filter, and it is *equally* consistent with a spelling the server turns into an empty
set. Adopting one of those would have meant a delta sync returning nothing for ever: the
library would stop gaining music with no error anywhere, presenting as Plex having gone quiet.
That is the additive-cache invariant broken outright, and strictly worse than the bandwidth
bug. Hence the second measurement, where a working filter has to return *everything*.

**And then the verdict rule itself was wrong.** It required the widening measurement to equal
the unfiltered count, which assumes every row has an `updatedAt` inside the window. About
1,500 of 11,492 tracks are older than a decade or carry no timestamp, so a working filter
reported 9,988 and was declared broken. The rule is now `recent < baseline && ancient > recent`:
one clause per failure mode, no threshold to be wrong about on the next library.

**The operator is strict, so the client asks one second earlier than the cursor.** The cursor
is the newest `updatedAt` already stored; asking for strictly-newer-than-it would skip a row
stamped that same second which has never been seen, and a bulk edit stamps many rows with one
timestamp. The compensation costs one already-cached row per pass, which upserts onto itself.

Three tests fail if that `- 1` is removed, which is how it was verified.

---

### #50 - Stop resyncing the library on every launch *(done, 6 August 2026)*

Reported as "the sync that loads every time takes about five seconds for 11k songs". Settled
in one reading, by the counter built for it: **Rows in last sync: 13,704**, delta cursor set,
initial sync complete. So the app was asking correctly and Plex was returning the whole
library anyway.

**Plex ignores `updatedAt>=`.** It accepts the parameter, answers 200, and drops it. This had
been an open question in TASKS.md since #18 with the instruction to read exactly that counter,
and it survived that long because an ignored filter is indistinguishable from a library where
everything changed. There is no error, no warning, and no shape difference in the response.

Two independent causes, and only one of them is Plex's.

**Ours: the sweep clock lived in memory.** `_lastDelta` began null on every launch, so a
sweep was always due, and `start()` forced a pass on top of that. Quit and reopen ten times in
an hour and that is ten full syncs. Schema **v8** adds `SyncState.lastDeltaSweepAt` so the
five minutes means elapsed time rather than uptime, and `start()` now asks the section clocks
instead of forcing.

Dropping `force` sounds riskier than it is. What it was really protecting is an interrupted
initial sync, and that survives on its own: `initialSyncComplete` being false makes the
change check report a change regardless of the clocks. There is a test for exactly that,
because it is the failure nobody would notice until half the library was missing.

The migration starts the column **null**, which reads as "never swept" and sweeps once. That
is the safe direction: defaulting to *now* would skip the first sweep after an upgrade and
hide any rating set while the old build was running.

**Plex's: the filter itself**, left to #51 and shipped with an instrument rather than a guess.
`DeltaFilterProbe` asks each candidate spelling with `X-Plex-Container-Size: 0` so nothing is
fetched, and deliberately not with the real cursor, where a genuinely changed library would
make a partial result look like an ignored filter.

**The first run of it changed its design, and that is the part worth keeping.** Against
James's server: `updatedAt>=` and `updatedAt>>=` both returned all 11,492 tracks, so both are
ignored; `updatedAt>` and `updatedAt>>` both returned **zero**, which reads as a perfect
filter. It is equally consistent with a spelling the server turns into an empty set, and
adopting one of those would have meant a delta sync that returned nothing for ever: the
library would simply stop gaining music, with no error anywhere, which is worse than the bug
being fixed and breaks the cache-is-never-authoritative-about-absence invariant outright.

So every spelling is now measured **twice**, once where it must return nothing (a minute ago)
and once where it must return everything (ten years ago). A filter is only reported as usable
if it narrows *and* widens. The probe calls the narrow-but-never-wide case out by name,
because on one measurement it looks like the answer.

The measured cost, on an 11k-track library: a quiet relaunch goes from about **seventy
requests to two**.

---

### #43b - Settings: playback and storage *(done, 6 August 2026)*

**The data-saver toggle was deliberately not built, and that is the finding.** #8 asked
Plex's music transcoder for 128kbps three documented ways and got the natural rate back byte
for byte each time, so there is no quality ladder to descend. The only lever is whether
transcoding happens, and forcing it on mobile data is exactly what a data-saver switch would
have done. A second control writing the same field under a friendlier name would be one more
thing to keep in step for nothing. So the task shipped as *quality per connection*, and the
mobile-data row is the data saver.

Two overrides rather than one, on purpose. A single global override would make "save data on
the train" also apply at home, which is the opposite of what anyone means by it.
`packaging`-style copy-paste between the two rows is the plausible bug, so a test asserts
each dropdown draws its own value, and another asserts the controller asks about the
connection it is actually on, using overrides set to the *opposite* of each connection's
automatic answer. Set them the same way round and both tests pass while the feature is
inverted.

**An override beats the source-rate floor.** That is the one interaction worth stating:
`QualityPolicy.decide` returns `override` before it looks at anything else, including the
~240kbps floor below which transcoding costs more data for worse audio. An override quietly
overruled by a signal it is meant to replace would appear to do nothing on exactly the
tracks someone is trying to economise on.

**Cache budgets are pushed into the running cache, never rebuilt into a new one.** The
providers `ref.read` the stored budget at construction and `ref.listen` for changes, because
watching would replace the instance. The index that makes eviction possible lives in memory,
and for audio so does the in-use set: a fresh instance starts with an empty one, so its first
eviction pass could delete the file the engine is streaming from and stop the track mid-play
with nothing pointing at the cache as the cause.

`applyBudget` scans before it evicts. Measured against an index that has never been filled,
eviction concludes it is under budget and deletes nothing, and the settings screen is
reachable from a cold start with nothing played and no image shown, which is exactly that
case.

Null is the stored value for "automatic" and for "platform default", and the store *removes*
those keys rather than writing a sentinel. A budget of zero would be a real, valid and
catastrophic setting.

`QualityPolicy.unmetered` is now the single definition of "not paying by the megabyte";
`PlaybackController` had its own copy for deciding whether to fill the cache.

**One test was killed rather than fixed.** A widget test that tapped the quality dropdown
open never reached a quiescent frame, so `pumpAndSettle` sat for its full ten-minute timeout
on every run. What tapping added over asserting what is drawn was already covered without a
widget at all, by `qualityOverrideFor` and the controller's override tests. A ten-minute test
run is a test suite nobody runs.

---

### #34 - Packaging and release *(done, 6 August 2026)*

`tool/package.ps1` is the deliverable, not the `flutter build` lines inside it. Every check
in it stands for a mistake that produces a build working perfectly on this machine.

**Signing falls back, loudly.** Gradle uses the debug key when `android/key.properties` is
absent, so `flutter run --release` still works on a machine without the keystore. That
fallback is the dangerous one: a debug-signed APK installs and runs perfectly, and the
failure surfaces later, when a properly signed build refuses to upgrade it. So the fallback
warns, and the packaging script refuses to produce a release build that took it.

**The key itself is the user's job, and stays out of the repo.** An upload key cannot be
reissued: an install can only ever be upgraded by a build signed with the same key, so
losing it means uninstalling and losing the library cache and token with it.
`key.properties` and `*.jks` are gitignored and `packaging_test.dart` asserts they still
are, because that file holds the keystore password in plain text.

**`keytool` cannot read a modern APK, and says so misleadingly.** At minSdk 24 Gradle signs
with the v2/v3 APK schemes and leaves v1 JAR signing off, so `keytool -printcert -jarfile`
answers *"Not a signed jar file"* for a perfectly well signed APK. That reads as a broken
build rather than a limitation of the tool, and cost one wrong conclusion here already.
`apksigner verify --print-certs` is the right tool; the debug key is recognisable by
`CN=Android Debug`.

**Icons are generated, not drawn.** `tool/make_icons.py` writes the legacy mipmaps, the
adaptive foreground, the Android 13 monochrome layer and the Windows multi-size `.ico` from
one definition. The PNGs are checked in so no build needs Python, and the generator is
checked in so the accent colour has one place to change. The mark is the equaliser bars from
the sign-in screen, four rather than five: at 48px, five bars and their gaps become a smudge.
The adaptive foreground is sized against the 66dp safe circle, not the 108dp canvas, which is
why its scale factor looks so much smaller than the legacy tile's.

**One version, asserted.** `pubspec.yaml` drives the Android versionName and the Windows
file version; `PlexIdentity.version` is what Plex sees and what the About screen shows.
Neither can read the other without a plugin, so `packaging_test.dart` fails if they drift.
Set to **0.9.0**, not 1.0: the catalog tier of search, sonic radio and acquisition are
unbuilt, and a version number that claims otherwise is a lie told to future-you.

**The Windows deliverable is the folder.** `plexify.exe` is 157KB and will not start without
`flutter_windows.dll`, `libmpv-2.dll`, `sqlite3.dll` and `data/`. Windows names only the
first missing DLL it looks for, which tells you nothing about the other three, so the script
checks for them before zipping. 20.9MB zipped.

**Size guard at 25MB.** arm64 release is 22.1MB against the plan's ~20MB expectation; the
gap is libmpv and the Flutter engine, both already accounted for. The point is that the next
ten megabytes should be a decision rather than a discovery.

Two first-run fixes fell out of reading the sign-in screen as a new user would. It now says
a browser is about to open *before* the button rather than after it. And a browser that
fails to open is no longer fatal: the first cut threw, and cleared the code on the way out,
so the one message saying "type this at plex.tv/link" was also the moment the code left the
screen.

### #49 - Rate artists *(done, 6 August 2026)*

Prompted by a good question: are artist favourites local only? They are not.
`PlexArtist.fromJson` already parsed `userRating` and `LibraryWriter.writeArtists` already
stored it, so **reading** was wired. **Writing** was not, and there were no stars on the
artist page, so a rating would sync in and never out.

`rateArtist` joins `rateAlbum` and `rateTrack`, and calls `ensureArtist` first for the same
reason they do: the local write is an `UPDATE`, so without a row Plex accepts the rating
while the artist never appears in the favourites filter.

Schema **v7** rewinds the delta cursor. An earlier claim here that v6 needed no rewind was
wrong, for exactly the reason v3 already taught: a delta sync asks for rows changed since
the cursor, and an artist rated months ago has not changed. A new version rather than an
edit to v6, because v6 has already run on installs that took the previous build.

---

## Still wanting live confirmation

Done in code, and none of it confirmable from a test. Entries leave this list only when they
have actually been watched working; see [PROJECT.md](PROJECT.md#verified-against-the-real-server)
for what has.

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
- **#34**, the signed path has never run, because the keystore does not exist yet. Create it,
  then `tool/package.ps1` end to end. **The first release-signed install needs the current
  debug-signed one uninstalled first**, which wipes the library cache and the token; Android
  refuses an upgrade across a signature change, and the error names neither cause nor cure.
- **#43b**, that forcing a transcode on mobile data actually reaches the server. Plex web
  Status is the place to read it. The settings themselves were confirmed working on 6 August;
  the same gap as #23 remains, in that requested is not the same as heard.
- **#29 / #30 / #32 / #33 / #54**, the whole catalog and acquisition group, built 7 August and
  never once run against the real MusicBrainz or James's real qBittorrent. Everything below is
  a fixture, and four of the things that can go wrong are invisible from a test. That
  MusicBrainz accepts *this* user agent and *this* pace, rather than answering 503 as it does
  for a generic one. That the artist resolver picks the right person for James's actual
  library, where the interesting cases are the ambiguous names and the artists MusicBrainz has
  never heard of. That de-duplication holds against his real file tags, which is where the
  edition-word list either earns its keep or reports albums he owns as missing. And that a
  queued torrent lands, gets scanned, and appears — the one path that crosses three systems and
  is only ever end-to-end.
- **#59**, the light theme. Six surface values were invented for it and only the dark set has
  been looked at; nothing in a test can tell whether they are pleasant, only that they exist.
  Also whether the cover shadow reads at all on a light background, where it has far less to
  darken.
- **#58**, one question rather than a feature: whether the track count is short because there
  is a second music library, or because the sync is genuinely missing rows. **Sync status →
  Cached** now answers it. "Music libraries" naming more than one is the whole explanation, and
  the fix is a library picker rather than anything about counting; one library with Plex's own
  total beside a smaller cached one is a real gap and a different problem. Window geometry is
  round-tripped against the real binary, but restoring onto a second monitor and onto a monitor
  that has since been unplugged are both untested.
- **#57**, that the level actually changes on Windows. libmpv is a different engine from
  ExoPlayer and `setVolume` goes through it; a fake player answers the call and makes no
  sound either way.
- **#56**, the two things a test cannot see. That the sleeve on the expanded player is
  actually *sharp* now on James's display, which is the complaint that started it and is a
  judgement about pixels; and that the gradient picks a colour worth having across a real
  library rather than across eight synthetic covers. The pure function is well covered, and
  what it does to a shelf of real Plex artwork is not something fixtures can answer.
- **#55**, all four of the new Home rows, and the probe before them. Run **Sync status →
  Discovery probe** first: it answers in one screen whether this server publishes any music
  hubs at all, whether the genre tags are dense enough to fill a row, and whether the history
  endpoint returns anything. **Empty history is the finding to watch for.** It needs server
  owner access and hands everyone else an empty container rather than a 403, so "you have not
  listened to anything" and "you are not allowed to ask" arrive looking identical, and
  "Most played in August" would simply never appear with nothing to say why. The genre row is
  the other one: it is built on the assumption that Plex tags albums densely enough for a
  genre to have eight of them, which is true of some libraries and not others.
- **The recovery work of 9 August**, which is three fixes deep and has been wrong twice. A
  network that *fades* is the case to try — switching wifi off is carried by the OS event and
  passes even when the app's own recovery is broken, which is exactly how the one-shot
  failure report survived #53. Also worth watching: that artwork for albums synced away from
  home now arrives, and that opening the app cold with no reachable network recovers on its
  own rather than needing a restart.
- **#19**, not built yet, but noted here because it is the one task whose *test* matters more
  than its behaviour: a reconcile that treats a partial fetch as authoritative deletes a chunk
  of the library, and the first symptom is albums vanishing.
