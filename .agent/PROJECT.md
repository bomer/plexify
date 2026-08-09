# Plexify, working context for agents

Everything an agent needs that **isn't** in [docs/PLAN.md](../docs/PLAN.md). The plan covers
design, decisions and phases. This covers the environment, the conventions, and the traps
already paid for.

What is left to do lives in [TASKS.md](TASKS.md); what is already done, and why it was done
that way, lives in [CompletedTasks.md](CompletedTasks.md).

---

## What this is

A Flutter music client for a personal Plex library, targeting **Windows desktop and Android**
from one codebase. Plex is the source of truth; a local SQLite cache exists purely so
browsing is instant. Replaces Plexamp, whose UI is slow to navigate.

Single user, single server, personal project. No multi-tenancy, no auth beyond Plex's own.

---

## Environment

Everything below is verified working. Don't re-derive it.

| Thing | Location |
|---|---|
| Flutter 3.44.8 stable | `C:\Users\James\flutter-sdk\flutter` |
| Android SDK 36 | `C:\Users\James\AppData\Local\Android\Sdk` |
| adb | `C:\Users\James\AppData\Local\Android\Sdk\platform-tools\adb.exe` |
| JDK (for Gradle) | `C:\Program Files\Android\Android Studio\jbr` |
| Visual Studio 2026 | Already installed with the C++ workload and ATL |
| Test device | `3B15AJ00B2A00000`, OPPO CPH2791, Android 16 (API 36) |

### Two shell traps

**Flutter is on the user PATH but not the inherited shell environment.** Every command needs
the prefix:

```powershell
$env:PATH = "C:\Users\James\flutter-sdk\flutter\bin;$env:PATH"
```

Gradle additionally needs `$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"`.

**The shell may reset its working directory to a WSL UNC path** (`\\wsl.localhost\...`).
Flutter's CMD wrapper cannot operate from a UNC path at all, it prints
`UNC paths are not supported. Defaulting to Windows directory` and misbehaves. If a command
fails oddly, `Set-Location C:\dev\plexify` first.

---

## Commands

```powershell
flutter analyze          # must be clean before committing
flutter test             # 338 tests, no live server needed
dart format lib test     # run before committing
```

```powershell
flutter run -d windows
flutter build apk --release --target-platform android-arm64
```

Releasing goes through the script, not the build commands, because the checks are the point:

```powershell
powershell -File tool/package.ps1
```

It refuses a debug-signed APK, an APK over its size budget, and a Windows bundle missing a
DLL the exe cannot start without. See [tool/README.md](../tool/README.md), including the
one-time `keytool` command for the signing key.

Deploying to the phone, note `flutter install` does **not** build, so build first:

```powershell
adb -s 3B15AJ00B2A00000 install -r build\app\outputs\flutter-apk\app-release.apk
```

After changing anything under `lib/core/db/`:

```powershell
dart run build_runner build
```

**Test in release on Android, not debug.** Flutter injects the `INTERNET` permission into
debug manifests only, so debug builds hide manifest problems that break release.

---

## How a change reaches the screen

Worth reading before touching anything under `lib/core/sync/`. Three mechanisms deliver
library changes, and they are not interchangeable, most of the debugging so far has been
working out which one *should* have carried a given change.

| | What it catches | Latency | Filtered? |
|---|---|---|---|
| `plex_notifications.dart` → `live_sync.dart` | Items Plex finishes **scanning**: new music, deletions | Sub-second | n/a |
| `sync_scheduler.dart` 30s poll | Anything that moved the section's `updatedAt` / `scannedAt` | ≤30s | **Yes** |
| `sync_scheduler.dart` 15min sweep | Metadata edits the section clocks never announced, **ratings set in Plex** | ≤15min | **No** |

That last column is the expensive lesson. **Plex moves a row's `updatedAt` when music is
added and leaves it alone when a rating changes** (measured 6 August 2026 with the Delta
filter probe: rate an album, and Albums-changed-in-5-minutes stays at zero). So the poll can
filter, because whatever moved the section clock moved the row's timestamp too; and the sweep
cannot, because the edits it exists for move nothing. A filtered sweep is a request that
costs money and is structurally incapable of finding what it is looking for.

Playback history travels the other way. `timeline_reporter.dart` sends `/:/timeline` every
ten seconds and on every state change, and `/:/scrobble` once a track passes 90%. It also
writes `lastViewedAt` locally, because Home's "Jump back in" sorts on that column and waiting
for a sweep to bring it back from Plex would leave the shelf showing yesterday's listening
for minutes after a play. Everything there is best-effort and swallows its errors, the audio
is the point, the bookkeeping is a courtesy.

The sweep exists because the section clocks describe the library's *shape*. Rating an album
in Plex changes no files and adds no rows, so neither clock moves and the poll alone would
never fetch it. This was a real bug, not a hypothetical.

Everything writing Plex data into drift goes through **`LibraryWriter`**, the bulk sync, the
push sync, and the revalidation that happens when a screen opens. There were three
hand-maintained copies of that mapping once; a column added to one of them silently stayed
null on the other paths.

**Polling stops when the app leaves the foreground** and resumes with an immediate check.
Android keeps the isolate alive for a whole playback session, so a poll that ignored
lifecycle would run for hours down a mobile connection checking a screen nobody can see.

All three assume the server is still where discovery left it, which is why
`connection_monitor.dart` sits underneath them. It re-races LAN / remote / relay on two
triggers, the OS reporting a transport change, and a run of requests reaching nothing -
feeding one re-resolve rather than giving each its own recovery path. Invalidating
`connectServerProvider` rebuilds the client, the socket and the scheduler together, so none
of them needs to know about the network individually.

Note the division of labour: the OS signal is fast but says only that a transport appeared,
not that anything is reachable through it. The failure count is trustworthy but slower, and
on a desktop whose transport never changes it is the only signal there is. Neither is
sufficient alone.

A fourth thing now *triggers* that machinery without being part of it. `DownloadMonitor`
watches qBittorrent's Music category and, when a torrent finishes, calls exactly what the
refresh button calls — `refreshSection` then `refreshNow`. That is invariant 10 honoured
rather than bent: a download is one more trigger, not a fifth path into the cache. It polls
adaptively, every 5s with something in flight and every 60s otherwise, and it is null unless
qBittorrent is configured *and* the catalog switch is on, so a phone with the feature off never
makes a request.

Two mistakes are easy in it and neither is visible on screen: announcing everything already
complete on the first poll asks Plex to rescan the whole library on every cold start, and
announcing a finished torrent on every subsequent poll does the same continuously, because
qBittorrent keeps seeding it and it never leaves the list. Both are guarded by tests.

Its counters live on the **Downloads** screen rather than on Sync status. That screen *is* the
instrument for this mechanism — the live list, the completion count and the last error, in the
place someone already goes to ask "where is that album?" — so a duplicate row on Sync status
would be a second thing to keep in step rather than a second thing to read.

### Start here when something "didn't show up"

The **Sync status** screen (Settings → Sync, `lib/features/settings/`) reports socket
connection and frame counts, when the poll and sync last ran, the stored
section clocks beside what the server reports right now, cached row counts, and the last
error from each path. It exists because three separate mechanisms failing all look identical
from the library screen, and two rounds of diagnosis were wasted guessing before it did.

"Rows in last sync" is the one to read for cost. It is also the number that caught the
biggest sync bug in the project: near zero means Plex is honouring the `updatedAt>=` filter,
and on James's server it reported **13,704** — the whole library, on every launch. See the
trap below.

**Every background mechanism ships with a counter on that screen.** Push sync, polling, the
connection monitor and playback reporting all publish counts, timestamps and their last
error. This is not documentation-by-UI; it is the difference between a five-second answer and
an afternoon. When "plays aren't reaching Plex" was reported, one reading of "Timeline
reports: 4" ruled out the entire client side at once. Add the counter when you add the
mechanism, retrofitting it means the first real failure is diagnosed blind.

---

## Code conventions

- **Riverpod without code generation.** Providers are declared explicitly in
  `lib/core/providers.dart` so the graph reads top to bottom. Drift's codegen is the only
  generated code in the project.
- **The UI speaks domain models**, not database rows. `lib/core/db/mappers.dart` converts
  drift rows to `PlexAlbum` / `PlexTrack`. This is what let the switch from live Plex reads
  to cache reads happen without rewriting a single screen, preserve it.
- **Comments explain why, not what.** Especially for platform behaviour that looks arbitrary:
  most of the non-obvious code here exists because of a specific Android or Plex quirk, and
  without the reason recorded someone will "simplify" it back into a bug.
- Feature-first layout under `lib/features/`, shared machinery under `lib/core/`.
- `flutter analyze` must be clean. `prefer_initializing_formals` is disabled project-wide
  because Dart forbids underscore-prefixed *named* parameters, making its advice impossible
  to follow.

---

## Architecture invariants

Break these and the app regresses to the problem it was built to solve.

**1. The cache is additive, never authoritative about absence.**
Reads may consult SQLite to answer *faster*, but absence from the cache must never mean
absence from the library. Concretely: an empty cache falls through to a live Plex read;
detail views are stale-while-revalidate; search must query both and merge. Getting this
wrong recreates "I added it to Plex and it won't show up", which is the whole reason this
project exists.

**2. Audio cache entries key on `(trackId, qualityDecision)`, never `trackId` alone.**
(Mobile only in practice, see the Windows trap below, but the rule holds wherever it runs.)
The decision is binary, direct play or transcode, see [there is no bitrate
control](#there-is-no-bitrate-control), but the two are still different bytes. Key on
trackId alone and a transcoded copy cached on cellular is served forever once back on the
LAN, silently defeating the whole point of deciding. `PlaybackController` writes the
decision onto every `MediaItem` as `extras['qualityDecision']` so #24 has it to key on.

**3. All artwork goes through `Artwork` → `PlexArtwork` → `ArtworkCache`.**
`Image.network` anywhere is a bug. Three screens used it, the album header, the mini
player and Now Playing, and each was a second download of a picture the grid had already
cached, uncached itself, and blank while disconnected. The player surfaces reach it via
`MediaItem.extras['thumb']`, carried for exactly this reason: `artUri` is a URL and
therefore useless as a key. Same thumb as the grid means one cached file, not two.

**4. Cache keys never contain a URL.**
The artwork URL, and the transcode URL, and the direct-play URL, embeds the server's base
address and the `X-Plex-Token`, and both move: the token when it is refreshed, the address
every time the connection re-races between LAN, remote and relay. `ArtworkKey` is
`(thumb, size)`, and `(trackId, qualityDecision)` is the audio equivalent below. A URL-keyed
cache looks perfect on a desk and misses on everything at once the moment the phone leaves
the house, which is the exact moment it was supposed to help.

**5. Plex `ratingKey`s are unique only within a server.**
`SyncState.serverClientIdentifier` records which server the cache belongs to, and
`clearLibrary()` wipes on change. Never merge rows across servers.

**6. Nothing blocks on sync.** The first sync of a large library takes minutes. Browsing,
playback and search must all work while it runs.

**7. Anything that must survive navigation lives outside the `Navigator`.**
The mini player sits in the shell scaffold's bottom slot; Now Playing is a sibling `Stack`
layer, not a pushed route. Pushing routes over them was the original bug.

**8. Every write of Plex data into drift goes through `LibraryWriter`.**
Three copies of that mapping existed once, and a column added to one stayed null everywhere
else. `writeX` upserts; `ensureX` inserts only when absent, for callers that need a row to
exist before updating it and must not flatten a richer one.

**9. Compact layouts are decided by width, not platform.**
`lib/shell/layout.dart` holds the single breakpoint. A narrow window on the desktop has the
same problem a phone does, and a `Platform.isAndroid` check would miss it.

**10. Recovery has one path and many triggers.**
Sync has three delivery mechanisms and the connection monitor has two triggers, but each
feeds a *single* re-resolve or a single write path. The temptation each time is to give a
newly discovered failure mode its own recovery route; that is how a system becomes
untestable, and James has asked explicitly that the sync logic not grow more paths. Add a
trigger, or make an existing path observable. Do not add a fourth mechanism.

**11. Settings have one write path, and it is `SettingsController._apply`.**
`lib/core/settings/app_settings.dart` holds all three pieces: `AppSettings` (one immutable
value), `SettingsStore` (the `shared_preferences` keys), `SettingsController` (the only
mutator). Adding a setting is a field, a key, and a setter, never a `setString` at a call
site. A setter that updates the state and forgets to persist works perfectly until the next
launch, which is the hardest kind of bug to notice and the easiest to introduce one call site
at a time. The store is loaded in `main()` and read **synchronously** thereafter, so the first
frame is already correct; anything lazily loaded here paints the default and then swaps.

**12. Position is asked of `PlexifyAudioHandler`, never of `player`.**
A transcode cannot be seeked, Plex answers 200 to a ranged request and declares no length -
so `seek` restarts the stream at an `offset=` instead, and the player's clock begins again
from zero. The handler holds the difference in `_streamStartedAt` and adds it back in
`position` and in `_toPlaybackState`. Read `player.position` directly and a track two thirds
through reports as barely started: the progress bar lies, and `TimelineReporter` never
crosses the scrobble threshold, so the play silently never reaches Plex's history.

---

## Testing

- **HTTP is tested against recorded fixtures** via `package:http/testing.dart`'s `MockClient`.
  CI never needs a live Plex server. Follow this for new API surface.
- **Database code is tested against real in-memory SQLite**, `AppDatabase(NativeDatabase.memory())`.
  Not mocks; the point is catching schema and index mistakes.
- **The audio engine is faked in Dart**, `test/support/fake_just_audio.dart` installs a
  `JustAudioPlatform` that records what it was asked to load. Without it anything reaching
  `AudioPlayer.load` or `.seek` throws `MissingPluginException` and the handler's own logic
  never runs at all. It found a real bug the hour it was written: reloading a stream
  re-emits `currentIndex`, which was firing the track-change reset and wiping the seek that
  had just happened.
- **Migration tests must drop the column first.** `NativeDatabase.memory()` creates the
  schema at *head*, so running `onUpgrade` against it re-runs DDL for columns that already
  exist. `test/migration_test.dart` drops what the migration adds before calling it -
  otherwise the ALTER is never genuinely exercised. Pass the real head as `to`; the branches
  test `from`, so an install arriving from v2 runs every later body in one pass.
- Two import collisions you will hit:
  - `import 'package:drift/drift.dart' hide isNull;`, drift and matcher both export `isNull`.
  - `import 'package:drift/drift.dart' show Value;` when a test only needs `Value`.
- Tests assert *behaviour that would fail silently*, not coverage for its own sake. Each one
  carries a comment explaining what breaks if it regresses.

### Widget tests, and the four ways they lie

Every one of these cost time in a single session, and none of them presents as a failing
assertion.

**`pumpAndSettle` never returns while a `CircularProgressIndicator` is on screen.** It spins
forever by design, so settling waits out the full ten-minute timeout and is reported as a
hang rather than as a test that should be written differently. Pump explicit durations
instead. This has now cost two separate rat-holes; `test/acquire_flow_test.dart` shows the
shape.

**A pending timer fails the test, whatever the assertions said.** `just_audio` runs a
periodic position timer while playing, so a test that leaves the player going fails at the
end with a stack trace pointing at `fake_async` and nothing to do with what it was testing.
Pause before the test ends. The same rule caught a `ConnectionMonitor` heartbeat that had no
business existing.

**`playbackState` lags the engine by more than a frame.** It is fed from the player through
`pipe`, so asserting on it immediately after an action reads the state *before*. Assert
against `FakeJustAudio.player` — which is set synchronously — or the test measures the
plumbing rather than the behaviour. Note also that the fake only creates a player once a
queue is loaded, so a bare `mediaItem.add(...)` leaves `players` empty.

**Anything touching `just_audio` needs `tester.runAsync`.** It waits on locks that never
resolve inside `testWidgets`' fake-async zone. Constructing the handler, loading a queue and
pausing all have to happen there.

`simulateKeyDownEvent` returns whether the framework claimed the key, which is a precise
instrument for anything about shortcuts: it distinguishes "handled" from "deliberately
passed through" without inspecting widget state.

### When a guard's test passes with the guard removed

**The environment is doing the work, not your code.** This happened for real with the
space-to-play typing guard: a widget test asserted a space in the search box does not pause
the music, and it passed with the guard deleted, because in a test the framework stops the
key below the shell. On a device with a live text input connection it does not.

Three tests would have shipped green against code that did nothing. The rule that catches it
is already here — break what a test guards and confirm it fails — and the resolution when
the environment cannot be made to discriminate is to **extract the decision and test it
directly**, then say plainly in the higher-level test that it guards the outcome rather than
the guard. `lib/shell/typing.dart` and the two tests around it are the worked example.

---

## Reading a bug report

The single most repeated mistake on this project has been diagnosing *why* before
establishing *where*. A reported symptom names the place it was noticed, and that is
routinely not the place at fault:

| Reported | Actually |
|---|---|
| "Favourites don't show up" | Not the ratings feature. Section clocks don't move for a metadata edit, so no sync was triggered. Two wrong diagnoses were published before that one |
| "Playback stops when I go outside" | Not the audio layer. The server address resolved at startup had gone stale |
| "I can't scrub a track" | Not the seek bar, which worked. The mini player was being used, and deliberately has no scrub control |
| "Plays aren't reaching Plex" | Not the wiring, which was fine. A missing `X-Plex-Session-Identifier` header |
| "The launch sync takes five seconds" | Not the sync code. Plex had been ignoring the delta filter since #18, so every launch refetched 13,704 rows while looking healthy |
| "A favourite doesn't reach the desktop" | Not the write path. Rating moves no `updatedAt`, so the sweep that exists to catch ratings could not see one |
| "Nothing plays after wifi to 5G" | Not the audio cache, which was the guess. A sticky re-resolve counted as a success and wiped the failure streak, and the cache's own HTTP client was invisible to everything |
| "The catalog finds nothing at all" | Check the user agent before the query. MusicBrainz answers **503** both for a generic agent and for exceeding one request a second, and an empty tier looks the same either way |
| "qBittorrent says 403 but works in a browser" | Almost never the password. Either `Referer` does not match `Host` down to the port, or the address is banned for repeated failed logins — and retrying, the obvious response, is what extends the ban |
| "It spins forever and throws me back a page" | Not two bugs. `showDialog` pushes on the **root** navigator and `Navigator.of(context)` resolves the **nested** one, so dismissing popped the page and left the dialog up |
| "It said Queued and nothing downloaded" | Not the add call, which returned `Ok.` The plugin handed back a *page* URL and qBittorrent failed decoding it in its own log, where the app cannot see |
| "Clicking a song queues it but does not play" | Not the queue. `skipToQueueItem` seeked and never called `play`, so it inherited whatever state the player was in — and launch restores **paused** on purpose |
| "Wifi off recovers, walking out of range does not" | Not two symptoms of one bug. Switching wifi off is carried by the OS event; drifting out fires none and hangs instead of failing, so it needed the failure path to work — and that had been one-shot since #53 |
| "Artwork never arrived for albums synced on 5G" | Not the cache, and not the network. The transcoder was being told to fetch the image from the server's own remote address |
| "Opened it on cellular and it never connected" | Not discovery. Nothing retried, because with no server there is no client and therefore no failure for anything to notice |
| "Home does not take me home from an album" | Not the button. Each tab owns a navigator, so an album opened from a Home shelf sits on Home's stack; tapping Home changed no state, so nothing moved |

In six of the first seven, a competent-looking fix to the named component was within reach and
would have been wrong. What works instead:

- **Read the counters first.** That is what the Sync status screen is for, and it settled the
  fourth case in one reading.
- **Ask one sharp question when the symptom is ambiguous**, "does the bar not move, or does
  it snap back?" separates a disabled control from a latency problem, and they share no code.
- **Prefer a question over a plausible fix.** Shipping the wrong fix costs more than asking,
  because it also removes the evidence.
- **Build the instrument.** Three of the entries above were settled in one reading by
  something built for the purpose: the Sync status counters, and the Delta filter probe. All
  three had been guessed at wrongly first.
- **Then make the instrument answer twice.** The probe's first version asked only "does this
  filter narrow the result?", and `updatedAt>` answered zero, which reads as a perfect filter
  and is equally consistent with one that matches nothing. Adopting it would have frozen the
  library silently. A measurement with one plausible failure mode is not a measurement; ask
  the question whose wrong answer looks different.

---

## Traps already paid for

**`LockCachingAudioSource` does not work on Windows, and failing is worse than not trying.**
It downloads to `X.part`, keeps the file open to serve bytes to the engine over a local HTTP
server, then renames on completion. POSIX allows renaming a file with open handles; Windows
does not. Every completed track failed with `errno 32`, and the failure took the audio source
down with it, so the *next* skip found a dead local server and playback stopped entirely.
The cache is therefore `Platform.isAndroid || Platform.isIOS` only, which is where it earns
its keep anyway: desktop listening is on the LAN. `AudioCache.enabled` is injectable so the
keying and eviction logic is still testable on a desktop. If this is ever revisited, the
symptom to look for is `.part` files piling up under the app's support
directory, `%APPDATA%/com.jamesotoole/plexify/audio`.

**`LockCachingAudioSource` needs a cleartext exemption for 127.0.0.1 on Android.** It does not
hand the player a URL; it runs a small HTTP server on loopback and serves the bytes through
that while writing the cache file. Android has blocked cleartext since API 28, so ExoPlayer
refused to connect to just_audio's own proxy and every track died with
`CleartextNotPermittedException` before a byte of music was read. `network_security_config.xml`
permits it for `127.0.0.1` and `localhost` **only**. Never widen that to
`usesCleartextTraffic` on the application: Plex is reached over HTTPS and the token travels in
the query string, so a blanket opt-in would put it in plaintext on any network that downgraded
the connection.

**Anything that writes a file the engine is streaming must survive being read.** The same
family of bug: eviction may not delete a file backing a loaded audio source, because the
source holds the handle for the life of the queue entry. Deleting underneath it truncates the
download and the track stops mid-play with nothing pointing at the cache as the cause.
`AudioCache` tracks an in-use set for exactly this, cleared when the queue is replaced.

**Three caches, and signing out must clear all of them.** Library (drift), artwork, audio,
plus the saved playback session. Every one is keyed on data that belongs to a particular
server, so leaving any behind means one library's ratingKeys pointed at another's. The list
lives in `AccountController._leave` and is the place to add the fourth.

**The catalog cache is the deliberate exception, and the reason is the key.** `CatalogReleases`,
`CatalogQueries` and `CatalogArtists` survive a sign-out and a change of server, because
MusicBrainz ids are *global*: they mean the same record on any server and to any other tool,
so there is nothing to collide. Wiping them would cost a fresh round of rate-limited lookups
for discographies that have not changed. `clearLibrary()` does not touch them; Settings has an
explicit "Forget catalog lookups" for the one case that needs it, an artist matched to the
wrong person.

**`lastViewedAt` belongs to Plex. Do not build client behaviour on it.** "Jump back in" did,
and failed twice over: the column is rewritten by every sync, so an album Plex had stamped
server-side kept reappearing however carefully the local write was suppressed; and it was
only ever written at the 90% scrobble mark, so putting something on and leaving after two
minutes recorded nothing at all, the shelf sat on an album from half an hour earlier.
`PlaybackHistory` (schema v5) is the client-owned answer: written on playback *start*,
never touched by the sync path. Anything else that means "what this user did" belongs
there too, not in a Plex column.

**"Loading interrupted" means two queue loads overlapped, not that anything failed.**
`AudioPlayer.setAudioSources` aborts a load still in flight when a second starts, and the
abandoned one throws. Startup used to hit this every time, the restore began loading and
the connection resolved on top of it, and because both paths are fire-and-forget it
surfaced as an unhandled exception. `PlaybackController._queued` serialises them. Anything
new that rebuilds the queue must go through it.

**`MPV: [error] lavf: Failed to create file cache` is libmpv's, not ours.** Plexify sets
three mpv options and none of them is a cache path; the only disk cache in the app is
artwork. mpv is failing to create its own file-backed stream cache and falling back to the
in-memory demuxer buffer, which `audio_init.dart` sets to 8 MB. Harmless, and worth
recording because it reads like a Plexify cache error and is the sort of thing that gets
chased twice.

**Browsing a MusicBrainz discography needs `inc=artist-credits` or every row is anonymous.**
The search endpoint includes the credit; the browse endpoint does not unless asked. Without
it every release group comes back attributed to nobody, which then matches nothing in the
library and reports a complete discography as entirely missing — a wrong answer that looks
like a working feature.

**A Cover Art Archive 404 is the normal case, not a failure.** Plenty of release groups have
no uploaded art. It reaches the same placeholder as a Plex item with no thumb, and must not
be logged or retried as an error.

**Plex records a MusicBrainz id three different ways, and usually not at all.** The modern
agent puts a `Guid` array on the item with one entry per source; the legacy agent puts a
single `guid` string; most libraries have neither. `PlexAlbum._mbid` reads both shapes, and
nothing may depend on the result being present — matching falls back to normalised artist
and title, which is the path most albums take.

**MusicBrainz rejects a generic user agent with a 503, the same code it uses for rate
limiting.** Two rules, one status, and neither says which it meant. `MusicBrainzClient` names
the app and a contact URL in `userAgent`, and paces every request through one serialised chain
at 1.1s — the extra hundred milliseconds buy a limit that is never argued about for a delay
nobody perceives, since the local half of search has already rendered. A test asserts both,
because the symptom of getting either wrong is an empty section that looks like "nothing
matched".

**qBittorrent answers 403 for three unrelated things, and the obvious fix for two of them
makes the third worse.** A failed CSRF check, an expired session, and an IP banned for
repeated failed logins. `Referer` and `Origin` must equal `Host` including the port — a
trailing slash on the configured address double-slashes every path and breaks it, which is why
`SettingsController.setQbitUrl` trims. And a 403 *during login* latches `QbitClient.lockedOut`
rather than retrying: the client cannot tell a ban from a wrong password, and guessing again
is the one action that makes either worse, on a server James runs himself.

**A rejected qBittorrent password is a 200 whose body is `Fails.`** Not a 401. Reading the
status alone treats it as a successful sign-in, and every request afterwards then 403s for
what looks like a completely different reason.

**`showDialog` uses the root navigator; `Navigator.of(context)` does not.** Every
page in this app lives inside a per-tab navigator (invariant 7), so dismissing a
dialog with `Navigator.of(pageContext).pop()` pops the *page* and leaves the
dialog on screen — a spinner that never goes away, over the wrong page. Pop
through the overlay's **own** context (the builder's), or avoid the overlay: the
acquisition flow uses a snackbar now, which has no navigator to get wrong and
does not block the screen for the twenty seconds a tracker search takes.

**A sheet's `BuildContext` is dead the instant it pops, and reporting through it
fails silently.** `ScaffoldMessenger.of(deadContext)` throws or no-ops depending
on how it is guarded, so "it opened the browser and said nothing" was a
`context.mounted` check doing exactly what it was told. Capture the
`ScaffoldMessengerState` *before* closing anything and pass that.

**`CallbackShortcuts` consumes a key before the callback decides anything.** It
matched space, marked the event handled, and only then ran the toggle — and a key
the framework has marked handled is never forwarded to the text input system, so
you could not type a space in the search box. No check *inside* the callback
could have helped. The shell uses a plain `Focus(onKeyEvent:)` and returns
`KeyEventResult.ignored` when it does not want the key, which is the only thing
that lets it through as a character.

**A focused `TextField` is not an `EditableText` as far as the focus node is
concerned.** `EditableText` builds a `Focus` internally and hands it the field's
node, so `primaryFocus.context.widget is EditableText` compares against the wrong
widget and is always false. `isTypingSomewhere()` in `lib/shell/typing.dart`
walks up with `findAncestorWidgetOfExactType<EditableText>()` instead, and has
its own test because the shell-level one cannot catch it: **in a widget test the
framework stops a plain key below the shell**, so the guard never runs there and
removing it fails nothing. It only matters with a live text input connection,
which is to say only on a real device.

**Half the `fileUrl`s a search plugin returns are not torrents, and adding one
fails silently on both sides.** LimeTorrents returns the human page
(`…-torrent-273396.html`); qBittorrent accepts it, answers `Ok.`, fetches it,
tries to bencode-decode HTML and gives up in **its own log** with
`expected value (list, dict, int or string) in bencoded string [bdecode:4]`. The
API call succeeded, so there is nothing to catch and nothing to retry. Handled by
prevention rather than error handling: `TorrentLink.of` classifies by URL shape,
`RankedTorrent.linkRank` sorts magnets above torrent files above unknowns above
pages, `bestAutomaticChoice` refuses a page outright, and tapping one in the
sheet opens it in a browser instead of pretending. Classification is deliberately
lopsided — an unrecognised URL is `unknown` and allowed, because plenty of real
download links have no extension and calling them pages would rule out whole
trackers.

**A qBittorrent search that is not deleted is leaked.** The server keeps finished searches
until they are removed and caps how many may exist, so leaking them means searching stops
working after a few dozen attempts with an error naming nothing relevant. `QbitClient.search`
stops and deletes in a `finally`.

**Filenames are not normalised text, and `normalise` is the wrong tool for them.** It drops
punctuation entirely, which is right for typed queries — "dont look back" finds "Don't Look
Back" — and wrong here, because punctuation *is* the word separator: `OK_Computer` folds to
`okcomputer` and stops containing either word. `torrentTokens` splits on non-alphanumerics
instead. Two different normalisers on purpose.

**Drift singularises table names, and two of the catalog ones collided with the domain
models.** `CatalogReleases` would have generated `CatalogRelease`, which is the model in
`catalog_models.dart`. All three catalog tables carry an explicit `@DataClassName('…Row')`.

Do not rediscover these.

**Debugging on the OPPO device, filter logcat by PID, never by keyword.** ColorOS floods
the log with sensor and display noise that buries real stack traces. Three attempts were
wasted on keyword greps before this worked:

```powershell
$p = (adb -s 3B15AJ00B2A00000 shell pidof com.jamesotoole.plexify).Trim()
adb -s 3B15AJ00B2A00000 logcat -d --pid=$p
```

Also: the `media` command is **absent** on this device, so playback can't be driven from adb.
Some verification genuinely requires the user.

**`audio_service` 0.18.19 throws on Android 13+ if you pass `MediaControl.stop`.** It
converts it to a `CustomAction` needing a non-zero icon, resolves the icon by name against
the *host* package, gets `0`, and throws, killing the entire notification. Don't add it back.

**Never call `super.stop()` (or otherwise `add` to `playbackState`) in `PlexifyAudioHandler`.**
That subject is fed from the player with `pipe`, and rxdart refuses a manual `add` while a
stream is being piped in, the call throws *"You cannot add items while items are being added
from addStream"*. `BaseAudioHandler.stop` does exactly that, so `stop()` threw every time it
ran, reachable in production from the Windows media-key Stop button. It was redundant too:
stopping the player emits the idle state through the pipe on its own. The same applies to
anything else tempted to write a state the player already reports.

**`yield*` swallows error handling in `async*` functions.** It forwards inner-stream errors
straight to subscribers, bypassing the enclosing `try`. Use `await for` + `yield` when the
generator needs to catch failures. This silently broke sync error reporting.

**`permission_handler` breaks the Windows build.** Its Windows implementation uses the
deprecated `<experimental/coroutine>` header, which current MSVC rejects outright. The
notification permission goes through our own `plexify/app` platform channel instead. Don't
re-add the package for an Android-only permission.

**Windows build failing with a missing header after toolchain changes** is usually a stale
CMake cache, not a missing component. Delete `build\windows` and rebuild before concluding
something needs installing, this produced one wrong diagnosis already.

**`keytool` cannot read a modern APK, and its error is misleading.** At minSdk 24 Gradle
signs with the v2/v3 APK schemes and leaves v1 JAR signing off, so
`keytool -printcert -jarfile` answers *"Not a signed jar file"* about a perfectly well
signed APK. That reads as a broken build rather than a limitation of the tool. Use
`apksigner verify --print-certs` from `build-tools`; Google's debug key is `CN=Android Debug`.

**App icons are generated, not drawn.** `tool/make_icons.py` writes every Android density,
the adaptive foreground, the Android 13 monochrome layer and the Windows `.ico` from one
definition. Editing a PNG by hand is editing build output. The accent colour is duplicated
in three places by necessity, the Dart theme, the generator, and `values/colors.xml` for the
adaptive icon's background; change one and change all three.

**Flutter needs Windows Developer Mode** for plugin symlinks. Already enabled.

**The Windows runner builds as C++20, deliberately.** Under C++17, C++/WinRT falls back to
`<experimental/coroutine>`, which current MSVC rejects outright rather than warning about -
the same header that makes `permission_handler` unbuildable. `target_compile_features(...
cxx_std_20)` in `windows/runner/CMakeLists.txt` is load-bearing; don't "tidy" it away.

**Media keys cannot be handled in Dart.** Windows routes them to whichever app owns a media
session, not to the focused window, so no amount of key handling in Flutter will see them.
`windows/runner/media_controls.cpp` registers a System Media Transport Controls session. Its
button callback arrives on an arbitrary thread and Flutter channels are platform-thread-only,
hence the `PostMessage` bounce through the window proc.

**`RefreshIndicator` does nothing on desktop.** It needs a drag, and a mouse wheel produces
none. Any pull-to-refresh must be paired with an explicit button, which is what
`SyncActions` is.

**A rating does not move `updatedAt`; adding music does.** So the delta filter can only be
used where the trigger was the section clocks. `SyncScheduler` decides that per pass, and the
15-minute sweep and every forced refresh go unfiltered. This regressed for about an hour and
presented as a favourite set on the phone never reaching the desktop, which reads as a sync
bug anywhere but the filter.

**A fake server that answers the same however it is asked is not testing the question.** The
scheduler's `MockClient` ignored the delta filter until #52, so every test passed whether the
sweep filtered or not, including the one named "a rating set in Plex arrives". The fake
applies the filter now, and three tests fail if the sweep starts using the cursor again.

**Plex applies `updatedAt>` and ignores `updatedAt>=`.** Measured, not read: the Delta filter
probe asked all four spellings twice against the real server. `>=` and `>>=` both returned all
11,492 tracks, so both are dropped. `>` and `>>` returned 0 for the last minute and 9,988 for
the last decade, so both work. `PlexClient.deltaFilter` holds the choice; re-run the probe
after a server upgrade rather than trusting it.

**The working operator is strict, so the client asks one second earlier than the cursor.** The
cursor is the newest `updatedAt` already stored, and strictly-newer-than-it would skip a row
stamped that same second which we have never seen. A bulk edit stamps many rows with one
timestamp. The cost of the compensation is one already-cached row per pass, upserting onto
itself.

**Roughly 1,500 of 11,492 tracks have an `updatedAt` older than a decade or none at all.**
Worth knowing before writing any other `updatedAt` filter: a bounded window silently excludes
them. It is also what corrected the probe's own verdict rule, which had demanded the widening
measurement return *everything* and so reported a working filter as broken.

**Plex ignores the `updatedAt>=` filter, silently.** It accepts the parameter, answers 200,
and returns everything. There is no error to read, and an ignored filter is indistinguishable
from a library where everything changed, which is how this survived from #18 to #50 while
every launch refetched 13,704 rows. Two separate things came out of it: `SyncScheduler.start`
no longer forces a pass and the sweep clock is persisted in `SyncState.lastDeltaSweepAt`
(schema v8), so a quiet relaunch costs one small request rather than seventy; and
**Sync status → Delta filter probe** exists to find a spelling the server does act on, by
asking for a window nothing can have changed in and counting what comes back. Anything that
adds a filter parameter here should be probed rather than assumed.

**A delta sync cannot backfill a column added by a migration.** It asks Plex for rows changed
since the cursor, and a rating set months ago has not changed. The v3 migration rewinds
`lastSyncedUpdatedAt` to 0 so one full pass runs. Any future column that must be populated
from existing Plex data needs the same treatment, or it stays empty forever and looks like a
broken feature.

**Rating writes are `UPDATE ... WHERE ratingKey = ?`.** For an item the sync has not reached
they match nothing, Plex accepts the rating anyway, and it silently never appears in
Favourites. `RatingController` calls `ensureAlbum` / `ensureTrack` first. Any other
optimistic local write needs the same guard.

**Watch ordering when a list has an index.** Digits sort before letters in ASCII, so a `#`
bucket lands at the top of a list while an A–Z rail shows it at the bottom, tapping it jumps
to the wrong end. `artist_index.dart` sorts non-letters last explicitly.

**A resolved address goes stale, and it presents as a playback bug.** `connectServerProvider`
picks whichever connection wins the startup wave race. A phone that connects on the LAN and
then leaves kept aiming at the local address, every request, the notification socket, the
poll, and any audio URL already handed to `just_audio`. The symptom was "playback stops when
I go outside" while launching cold on cellular worked perfectly, which points the
investigation at the audio layer rather than the connection. Fixed in #41 by
`ConnectionMonitor`. **Anything that caches a resolved address needs an invalidation story
before it is relied on**, artwork URLs (#21) are the next one.

**Plex's dashboard needs `X-Plex-Session-Identifier`, and it must be stable.** Without the
header the server accepts timeline reports, answers 200, and lists nothing, the client looks
correct and the dashboard looks broken. With a *fresh* value per launch it lists too much:
every relaunch claims a new slot while the old one lingers until the server times it out, so
quitting and reopening shows two copies of Plexify playing at once. It is persisted
alongside the client identifier so a relaunch replaces the previous entry. That is also what
makes it self-healing after a crash or a force-quit, neither of which gets to say goodbye.
`AppLifecycleListener.onExitRequested` sends an explicit `stopped` for the clean case, and is
bounded by a timeout, an unreachable server must never be able to stop the app closing.

**A "once only" flag guarding queued work has two wrong places to be reset.** The scrobble
mark in `timeline_reporter.dart` must be cleared only if it still refers to the track being
left. Cleared synchronously when the track changes, the outgoing track loses its mark before
the queued closure evaluates it and gets counted twice. Cleared unconditionally inside that
closure, it discards a mark the *incoming* track already earned, because a queued report can
run between the event arriving and the closure executing. Both produce duplicate plays, and
neither is visible without a test that counts.

**A `FutureProvider` keeps serving its previous value while it re-resolves.** Verified, and
load-bearing: it is why invalidating `connectServerProvider` on a network change does not
flash the whole album grid to placeholders. It also means a test must `await` the rebuild
before asserting the new value, reading straight after an invalidate returns the *old* one,
which looks like the provider ignoring you.

**Side effects in a derived provider's build body only happen if something is watching.** The
first attempt at remembering the last-good server put the write in `plexServerProvider`,
which worked in the app, the widget tree watches it constantly, and failed in a test that
did not. Correctness that depends on who is subscribed is not correctness. The remembering
moved into `connectServerProvider`, where the value is produced and the write happens
whether anyone is listening or not.

**Desktop exit hooks work here without touching the C++.** `AppLifecycleListener.onExitRequested`
fires on the Windows close button because `flutter_window.cpp` already routes messages through
`HandleTopLevelWindowProc` before its own switch, and the embedder implements the exit-request
flow there. Do not go writing a `WM_CLOSE` intercept. Note `AppExitResponse` lives in
`dart:ui`, not `package:flutter/services.dart`, despite the binding that uses it living in
services.

**Anything on the exit path must be bounded.** The goodbye report to Plex has a two-second
timeout, because the case where it is slowest, a server that has stopped answering, is
exactly the case where the app must still close promptly.

**The audio cache has a third HTTP client, and nothing could see it fail.**
`LockCachingAudioSource` does not hand the engine a URL; it runs a loopback server and
fetches the bytes itself, in Dart. Those fetches reach neither `errorStream` (so not
`onPlaybackFailed`) nor `HealthReportingClient` (so not `ConnectionHealth`). Logcat shows
`Proxy request failed: SocketException ...` followed by an unhandled exception, and the app
observes neither. On a wifi to cellular handover this broke recovery outright: the engine
failed once, a reconnect ran, and from then on every failure came from the cache proxy, so
nothing triggered another attempt and playback stayed dead until a restart.
`playbackRecoveryProvider` installs a `PlatformDispatcher.instance.onError` hook that routes
a `SocketException` into `recordUnreachable`, and deliberately returns false so Flutter still
reports it. Ugly, and the only place those failures exist.

**A sticky re-resolve that lands on the same address must not count as a success.** Discovery
keeps the last address that worked when nothing answers, so `connectServerProvider.future`
completes just as happily whether it moved or not. `ConnectionMonitor` used to
`_health.reset()` on any completion, which threw away the only evidence the connection was
still dead, and the cooldown then held off the next attempt. `reconnect` now returns whether
the address actually changed, and the failure streak survives when it did not. Related to but
distinct from the trap below: that one is about never clearing the server, this one is about
not mistaking stickiness for recovery.

**A one-shot "connection lost" report is a dead end, and #53 created one.**
`ConnectionHealth` emitted once per streak and re-armed only on `reset()` — which
#53 correctly stopped calling when a re-resolve landed on the same address. Streak
preserved *and* latch preserved means the failure is never reported again, so the
second attempt never happens and recovery falls entirely to the OS volunteering a
connectivity event. It reports at 3, 6, 12, 24… failures now, capped, so a
connection that has just gone is retried promptly and a phone offline for an hour
is not re-racing LAN, remote and relay all hour.

**Switching wifi off and walking out of range are not the same test.** Switching
it off fires an OS connectivity event and a fast connection refusal; drifting out
of range often fires *no* event — Android keeps the interface associated long
after the route has gone — and requests hang rather than fail. Anything claiming
to fix reconnection has to be tried the second way, because the first way is
carried entirely by the OS signal and passes even when the app's own recovery is
broken.

**`package:http` has no default timeout, and a degrading network is what that
costs.** A wifi you are leaving accepts connections and then says nothing, so
every request hung for however long the OS eventually decided. The failure count
that drives recovery barely moved. `HealthReportingClient` bounds each request at
12s; `ArtworkCache` bounds each fetch at 15s, where it matters more than it looks
because only four run at once — four hung fetches held every slot and no image
loaded again for the rest of the session.

**The artwork URL must carry a *relative* path.** `artworkUrl` used to pass
`{baseUrl}{thumb}` as the transcoder's `url` parameter, which asks the server to
fetch the image from itself over whichever address the client happens to hold. On
the LAN that is harmless; off it, the server is told to dial its own public
address (needing hairpin NAT) or its plex.tv relay. It fails identically every
time, so artwork for anything synced while away never appeared and never appeared
after a restart either — which is what distinguishes it from a flaky network.

**A launch that never connected has nothing that can fail.** Both other recovery
triggers need something to be happening: no server means no client, no client
means no requests, no requests means no failures. A cold start with the network
still settling — a phone opened moments after wifi went off — sat disconnected
until the OS spoke up or the app was killed. `ConnectionMonitor` now retries from
a standing start, armed only while a connection is genuinely missing and backing
off while it stays that way. **Never as a standing heartbeat**: that leaked a
pending timer into every widget test building the shell, which is how the first
version was caught.

**Turning "not connected" into a state you cannot leave.** The first cut of #41 let a failed
re-resolve clear the server. That reads as honest and is a dead end: no server means no
client, no client means nothing makes requests, and no requests means `ConnectionHealth` can
never observe another failure, so nothing ever retries. Recovery depended entirely on the OS
volunteering a connectivity event. The connection is now sticky: it keeps the last address
that worked, and only signing out clears it. Generally, **a recovery mechanism driven by
failures must leave something running that can still fail.**

**A Home row seeded by `Random()` reshuffles itself under the reader's finger.** Home is
backed by four live database streams and rebuilds several times a second while a sync is
running. Any row whose order is drawn fresh on each build is unusable: the album you were
reaching for moves before you reach it. Rotation that is *meant* to happen daily has to be
seeded on the date, which is what `daySeed` is, and the test for it asserts two calls in one
day match exactly rather than merely both being shuffled.

**`List.sort` is not stable in Dart above about thirty-two elements.** Below that it is an
insertion sort and ties keep their order; above it, a dual-pivot quicksort throws that away.
A ranked shelf therefore needs an explicit tie-break or it arrives in a different order every
time it is rebuilt, on exactly the months with enough listening to be worth looking at. Note
what this does to a test: a fixture of eight albums passes with no tie-break at all and
proves nothing. The one in `discovery_test.dart` uses forty on purpose, and it was written
after the eight-album version was confirmed to pass against the broken comparator.

**An id parsed out of a Plex path must be the *last* number, not the first.** Genre keys come
back as `/library/sections/3/genre/13` on some versions and a bare `27` on others. `\d+`
matches the section id in the first case, so every genre in the library resolves to the same
wrong key and the row silently fills with whatever genre 3 happens to be. The regex is
`(\d+)(?!.*\d)` for that reason, and the test feeds it both spellings.

**Empty and forbidden look identical on `/status/sessions/history/all`.** It needs server
owner access and answers everyone else with an empty `MediaContainer` rather than a 403, so
"nothing has been played" and "you may not ask" are the same response. Nothing in the app can
tell them apart, which is why the discovery probe reports the row count rather than a verdict
and says in words what an empty one means.

**Overriding `MediaQuery` in a widget test decides the layout but does not resize the
window.** A test that hands the tree a 1200px `MediaQueryData` gets the desktop branch built
and then laid out inside the default 800x600 surface, so anything measured against the number
the test passed in is measured against a lie. The centring assertion in `mini_player_test`
caught this on its first run, reporting 400 where 600 was expected, and the code was right the
whole time. `tester.view.physicalSize` is the other half, and asserting against
`tester.getRect` of the widget rather than against a constant is better still.

**Material 3 tints your greys with the seed colour, twice, and neither is visible from
reading the code.** `ColorScheme.fromSeed` derives the surface roles from the seed's tonal
palette with chroma deliberately left in, so the "greys" are already tinted; then
`surfaceTint` — which defaults to `primary` — is blended into every surface in proportion to
its elevation. A blue seed therefore gives a blue-grey window, and no line anywhere says so.
For a media app this is actively wrong: the artwork is supposed to be the only colour on
screen. The fix is `copyWith` over the surface family plus `applyElevationOverlayColor: false`
and `surfaceTintColor: Colors.transparent` on the component themes, or the overrides are
undone the moment anything is raised. Spreading the values *apart* matters as much as
neutralising them: the generated ones sat within a few percent of each other, so sidebar,
content and transport bar read as one continuous sheet.

**Flutter's desktop runner remembers nothing about its window, and the fix belongs in C++.**
There is no cross-platform place to keep window geometry, so the runner opens at a fixed
1280x720 every launch. Doing it in Dart would mean the window appears at the default and then
jumps once the engine has started and read a preference. Three things the registry version has
to get right: `GetWindowPlacement` rather than `GetWindowRect`, or a window closed maximised
stores the screen as its *normal* size and un-maximising after a restart does nothing; the
stored frame must be applied *after* `Win32Window::Create`, because Create scales the size it
is given by the monitor DPI and a physical-pixel frame passed through it grows by the scale
factor on every launch; and the frame has to be checked against the monitors that exist now,
or a window closed on a since-unplugged screen launches somewhere nothing can display it,
which presents as the app not starting at all.

**A `Row` gives its non-flex children unbounded main-axis constraints, so a `Flexible` nested
inside one of them cannot shrink.** It resolves against infinity, takes its full width, and
overflows the parent instead, which looks exactly like the constraint having been ignored.
The volume slider hit this: `Flexible` inside a `Row` inside a `Row`, where only the inner one
was flexible. Both levels have to be, and the symptom appears only at the narrowest width the
layout is ever built at, which is why there is a test pinned to 801px.

**A background colour taken from artwork must be a histogram, not an average.** Averaging a
sleeve returns grey almost every time, because opposite hues cancel: a black metal cover and a
Motown one come out the same murk, and the feature reads as broken rather than subtle. Three
further rules, each bought by a real kind of cover: near-black and near-white are excluded,
since borders and letterboxing are often the largest single block of pixels on the image;
saturation is *weighted* rather than required, so a large muted field beats a small vivid one
and monochrome covers still get an answer; and the winning bucket's own mean is returned
rather than its centre, because 4-bit quantisation visibly misses on skin tones.

**Blurry artwork is usually an upscale, and asking for more pixels can make it worse.** The
expanded player drew the sleeve at 420 logical pixels while asking Plex for 600, which on any
2x display is 840 physical against a 600 source. The fix is a smaller draw, not a bigger
request: many covers on the server are not much above 600 to begin with, so raising the ask
just moves the upscaling into Plex's transcoder.

**Plexamp's extra rows are not hubs.** Worth writing down because it looks like an endpoint
problem and is not. Plexamp shows rows Plex Web does not, and the two disagree about their
contents, because the rows are *aggregates somebody computes* rather than lists the server
hands out: Plexamp computes its own from records it keeps locally and nobody else can read.
Chasing a hub identifier that produces "Most played in January" is chasing something that
does not exist. The server's contribution is the raw play history, and the counting is the
client's job. `DiscoveryProbe` exists to keep that conclusion re-checkable rather than
remembered.

---

## The music transcode endpoint

Measured against James's server on 5 Aug 2026 by `TranscodeProbe`, over both the LAN and the
remote route, on Windows and Android. **The two routes behaved identically in every respect**,
which is itself the finding, no route-specific handling is needed.

Re-run it from Sync status → Transcode probe whenever the server is upgraded. It is cheap and
it settles arguments.

### The working parameter set

```
{baseUrl}/music/:/transcode/universal/start.mp3
  ?path=/library/metadata/{ratingKey}
  &mediaIndex=0&partIndex=0&offset={seconds}
  &directPlay=0&directStream=0&protocol=http
  &X-Plex-Product / -Version / -Platform / -Device / -Device-Name
  &X-Plex-Session-Identifier / -Client-Identifier / -Token
  &session={uuid}
```

**The `X-Plex-*` identity must be in the query string, and this is the whole difference
between 200 and 400.** Without it the endpoint returns `400 Bad Request` with no explanation.
It is easy to assume the headers `PlexClient` already sends cover this, they do not: the URL
is handed to the audio engine, which does its own HTTP and carries none of them. This cost two
round trips to find, because a 400 says nothing about which parameter was missing.

Everything richer also works (`directStream=1`, the full web-client set with a decode
profile), so none of it is required. `TranscodeProfile.identified` is the default in
`transcodeUrl` for that reason.

### What it does and does not do

| | |
|---|---|
| Progressive, not HLS | **Yes**, `audio/mpeg`, answered directly, no redirect. Retires risk #1 in the plan: transcoded playback is cacheable. |
| Range requests | **No**, 200 for a ranged request, whole stream offered. |
| Declared length | **No**, a live transcode has no length to declare. |
| `offset=` | **Yes**, genuinely starts partway in. This is the *only* way to seek here. |
| Bitrate cap | **No.** See below. |
| `stop?session=` | **Yes**, 200 every time, for every session. |

### There is no bitrate control

`musicBitrate`, `maxAudioBitrate`, and an `add-limitation(...audio.bitrate...)` inside
`X-Plex-Client-Profile-Extra` were each asked for 128 kbps. All three returned the natural rate
unchanged, byte for byte, on both routes.

Plex's own `/transcode/sessions` record confirms it is not a misread request, `audioDecision:
transcode`, `sourceAudioCodec: flac`, `container: mp3`, and carries **no bitrate field at
all**. The output is VBR mp3 landing around 235–242 kbps depending on the material.

**So #23 is not a quality ladder.** It is one binary decision: direct-play the original, or
transcode at whatever rate Plex picks. Against a FLAC that is still a large saving; against an
mp3 already smaller than ~240 kbps, transcoding costs *more* data for *worse* audio, so a
policy that transcodes everything on cellular would be actively harmful. The probe's "Is
transcoding worth it for this track?" check measures the source rate for exactly this reason.

That decision now lives in `lib/core/audio/quality_policy.dart`, which reads three signals
and keeps them apart on purpose. **Connectivity** is what *this device* is paying for; a
laptop on a phone's hotspot reports as wifi and is still metered. **Server locality** is
what the request reaches the server through; a relay is bandwidth-limited by Plex on top of
whatever the local network is doing, so it transcodes regardless. **Source rate** is
`PlexTrack.sourceKbps`, derived from Media > Part's `size` over the duration, Plex sends no
bitrate of its own. A null source rate means "nothing measured yet", never "below the
floor": treating it as a floor would pin every not-yet-synced track to direct play on
cellular, which is the expensive direction to be wrong in.

### Two things that will mislead the next reader

- **Plex issues its own transcode session key** rather than echoing the `session` parameter, so
  a record fetched from `/transcode/sessions` cannot be matched to a request by id. The probe
  falls back to position and says so.
- **`LockCachingAudioSource` copes with all of this**, which is not obvious. It requires HTTP
  200 on its first fetch (Plex gives 200), treats a missing content-length as `null` rather
  than an error, and still renames the completed cache file. What it cannot do is seek *ahead*
  of what it has downloaded, that path issues a ranged sub-request and throws on anything but
  206. Seeking a transcode must go through `offset=` instead.
- **Seeking a transcode reuses the session id.** A new id starts a second transcode and
  abandons the first, leaving the server encoding for nobody; Plex replaces the stream for a
  session it already knows. `PlaybackController._seekUrl` rebuilds from the `MediaItem`'s
  `extras['transcodeSession']` for that reason, and the offset is always measured from the
  queue's canonical offset-zero URL, rebuilding from the *loaded* URL would compound
  offsets, so a seek to 2:00 followed by one to 0:30 would land at 2:30.

## Things only the user can do

- **Approve the Plex PIN** in a browser, sign-in cannot be automated.
- **Confirm audio actually sounds right**, gapless seams, lock-screen controls, background
  playback. Building successfully proves nothing here.
- **Run Plex's sonic analysis** (Settings → Library → Analyze). Takes hours to days and gates
  sonic radio.
- **Enter the qBittorrent username and password.** Credentials are never typed by an agent;
  the screen exists so James enters his own into his own keystore.
- **Install and enable a qBittorrent search plugin.** Without one the search endpoints answer
  200 and return nothing, which is indistinguishable from "nobody is seeding this album" for
  every album ever asked for. `hasSearchPlugins` exists to tell those apart, and Save and test
  reports it.
- **Install software or change system settings.**
- **Anything needing the real Plex library.** Tests run against fixtures, so behaviour that
  depends on what the server actually returns, whether a filter is honoured, what a
  notification frame really looks like, can only be confirmed on James's server.

### Verified against the real server

All confirmed against James's server, on the dates given. Anything not listed here is still
under [Still wanting live confirmation](CompletedTasks.md#still-wanting-live-confirmation).

- Push sync delivers a newly added album **instantly**.
- Ratings set in Plex arrive by poll, not push, and need the refresh button to appear at once.
- **Artist ratings sync both ways** (#49), 6 Aug, after the v7 cursor rewind.
- **The playback and storage settings persist and take effect** (#43b), 6 Aug.
- **`updatedAt>` is applied and `updatedAt>=` is ignored** (#51), 6 Aug, by the Delta filter
  probe. Both measured twice, narrowing and widening.
- **Adding music moves `updatedAt`; rating something does not** (#52), 6 Aug, same probe.
  This is the fact the whole sync design now rests on.
- **A rating set on the phone reaches the desktop** within the sweep interval (#51/#52),
  6 Aug. It did not, for about an hour, which is what #52 fixed.
- **A wifi to cellular handover recovers on its own**, without restarting the app (#41/#53),
  6 Aug.

### Verified without the user, where it looked impossible

Two things that seemed to need a human turned out not to:

- **Windows media keys**, by querying the OS for the registered media session
  (`GlobalSystemMediaTransportControlsSessionManager` from PowerShell) and synthesising
  `keybd_event` presses for play/pause, next and previous while watching the app's log.
- **Whether a test actually discriminates**, by temporarily breaking the code it guards and
  confirming it fails. Do this for any test asserting an ordering, a race or a "only once"
  rule.

Reach for that pattern before declaring something unverifiable.

That second one is not a confidence ritual, it has already caught a test that passed for the
wrong reason. A test named for the single-flight guard in `ConnectionMonitor` was in fact
being satisfied by the cooldown, because the fake clock never advanced; disabling the guard
left all sixteen tests green. The replacement forces both attempts past the cooldown so only
the guard can refuse the second. **A test whose name and mechanism have quietly come apart is
worse than no test**, because it is counted as coverage. Suspect any test that passes the
first time you write it against code you have not yet seen fail.

---

## Git

Every commit so far is authored `unknown <james@nomoss.co>`, `user.name` is unset globally.
Still worth setting; the history can be rewritten afterwards if it matters.

Commit messages explain *why*, and **record wrong turns explicitly**: one notes that R8
shrinking was ruled out before the real cause was found, another that a claim about delta
sync backfilling ratings was wrong and why. This has already prevented re-investigation more
than once. Keep doing it, a message that only describes the final state throws away the
expensive part.

Write the message to a file and use `git commit -F`. PowerShell here-strings mangle multi-line
`-m` arguments; that cost one confusing failure already.

Check `git status` before `git add -A`, it has already swept in a `debug.lnk` shortcut
holding an absolute path and a machine id. `*.lnk` is ignored now, but build output and
editor droppings will keep finding new ways in.

Sign commits with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```
