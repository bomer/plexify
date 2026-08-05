# Plexify — working context for agents

Everything an agent needs that **isn't** in [docs/PLAN.md](../docs/PLAN.md). The plan covers
design, decisions and phases. This covers the environment, the conventions, and the traps
already paid for.

Current progress lives in [TASKS.md](TASKS.md).

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
| Test device | `3B15AJ00B2A00000` — OPPO CPH2791, Android 16 (API 36) |

### Two shell traps

**Flutter is on the user PATH but not the inherited shell environment.** Every command needs
the prefix:

```powershell
$env:PATH = "C:\Users\James\flutter-sdk\flutter\bin;$env:PATH"
```

Gradle additionally needs `$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"`.

**The shell may reset its working directory to a WSL UNC path** (`\\wsl.localhost\...`).
Flutter's CMD wrapper cannot operate from a UNC path at all — it prints
`UNC paths are not supported. Defaulting to Windows directory` and misbehaves. If a command
fails oddly, `Set-Location C:\dev\plexify` first.

---

## Commands

```powershell
flutter analyze          # must be clean before committing
flutter test             # 171 tests, no live server needed
dart format lib test     # run before committing
```

```powershell
flutter run -d windows
flutter build apk --release --target-platform android-arm64
```

Deploying to the phone — note `flutter install` does **not** build, so build first:

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
library changes, and they are not interchangeable — most of the debugging so far has been
working out which one *should* have carried a given change.

| | What it catches | Latency |
|---|---|---|
| `plex_notifications.dart` → `live_sync.dart` | Items Plex finishes **scanning**: new music, deletions | Sub-second |
| `sync_scheduler.dart` 30s poll | Anything that moved the section's `updatedAt` / `scannedAt` | ≤30s |
| `sync_scheduler.dart` 5min sweep | Metadata edits the section clocks never announced — **ratings set in Plex** | ≤5min |

Playback history travels the other way. `timeline_reporter.dart` sends `/:/timeline` every
ten seconds and on every state change, and `/:/scrobble` once a track passes 90%. It also
writes `lastViewedAt` locally, because Home's "Jump back in" sorts on that column and waiting
for a sweep to bring it back from Plex would leave the shelf showing yesterday's listening
for minutes after a play. Everything there is best-effort and swallows its errors — the audio
is the point, the bookkeeping is a courtesy.

The sweep exists because the section clocks describe the library's *shape*. Rating an album
in Plex changes no files and adds no rows, so neither clock moves and the poll alone would
never fetch it. This was a real bug, not a hypothetical.

Everything writing Plex data into drift goes through **`LibraryWriter`** — the bulk sync, the
push sync, and the revalidation that happens when a screen opens. There were three
hand-maintained copies of that mapping once; a column added to one of them silently stayed
null on the other paths.

**Polling stops when the app leaves the foreground** and resumes with an immediate check.
Android keeps the isolate alive for a whole playback session, so a poll that ignored
lifecycle would run for hours down a mobile connection checking a screen nobody can see.

All three assume the server is still where discovery left it, which is why
`connection_monitor.dart` sits underneath them. It re-races LAN / remote / relay on two
triggers — the OS reporting a transport change, and a run of requests reaching nothing —
feeding one re-resolve rather than giving each its own recovery path. Invalidating
`connectServerProvider` rebuilds the client, the socket and the scheduler together, so none
of them needs to know about the network individually.

Note the division of labour: the OS signal is fast but says only that a transport appeared,
not that anything is reachable through it. The failure count is trustworthy but slower, and
on a desktop whose transport never changes it is the only signal there is. Neither is
sufficient alone.

### Start here when something "didn't show up"

The **Sync status** screen (ℹ️ in the Home or Library app bar, `lib/features/settings/`)
reports socket connection and frame counts, when the poll and sync last ran, the stored
section clocks beside what the server reports right now, cached row counts, and the last
error from each path. It exists because three separate mechanisms failing all look identical
from the library screen — and two rounds of diagnosis were wasted guessing before it did.

"Rows in last sync" is the one to read for cost: near zero on a routine sweep means Plex is
honouring the `updatedAt>=` filter.

**Every background mechanism ships with a counter on that screen.** Push sync, polling, the
connection monitor and playback reporting all publish counts, timestamps and their last
error. This is not documentation-by-UI; it is the difference between a five-second answer and
an afternoon. When "plays aren't reaching Plex" was reported, one reading of "Timeline
reports: 4" ruled out the entire client side at once. Add the counter when you add the
mechanism — retrofitting it means the first real failure is diagnosed blind.

---

## Code conventions

- **Riverpod without code generation.** Providers are declared explicitly in
  `lib/core/providers.dart` so the graph reads top to bottom. Drift's codegen is the only
  generated code in the project.
- **The UI speaks domain models**, not database rows. `lib/core/db/mappers.dart` converts
  drift rows to `PlexAlbum` / `PlexTrack`. This is what let the switch from live Plex reads
  to cache reads happen without rewriting a single screen — preserve it.
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
Quality adapts to network. Key on trackId alone and a 320k copy cached on cellular is served
forever once back on the LAN, silently defeating adaptive quality.

**3. Plex `ratingKey`s are unique only within a server.**
`SyncState.serverClientIdentifier` records which server the cache belongs to, and
`clearLibrary()` wipes on change. Never merge rows across servers.

**4. Nothing blocks on sync.** The first sync of a large library takes minutes. Browsing,
playback and search must all work while it runs.

**5. Anything that must survive navigation lives outside the `Navigator`.**
The mini player sits in the shell scaffold's bottom slot; Now Playing is a sibling `Stack`
layer, not a pushed route. Pushing routes over them was the original bug.

**6. Every write of Plex data into drift goes through `LibraryWriter`.**
Three copies of that mapping existed once, and a column added to one stayed null everywhere
else. `writeX` upserts; `ensureX` inserts only when absent, for callers that need a row to
exist before updating it and must not flatten a richer one.

**7. Compact layouts are decided by width, not platform.**
`lib/shell/layout.dart` holds the single breakpoint. A narrow window on the desktop has the
same problem a phone does, and a `Platform.isAndroid` check would miss it.

**8. Recovery has one path and many triggers.**
Sync has three delivery mechanisms and the connection monitor has two triggers, but each
feeds a *single* re-resolve or a single write path. The temptation each time is to give a
newly discovered failure mode its own recovery route; that is how a system becomes
untestable, and James has asked explicitly that the sync logic not grow more paths. Add a
trigger, or make an existing path observable. Do not add a fourth mechanism.

**9. Settings have one write path, and it is `SettingsController._apply`.**
`lib/core/settings/app_settings.dart` holds all three pieces: `AppSettings` (one immutable
value), `SettingsStore` (the `shared_preferences` keys), `SettingsController` (the only
mutator). Adding a setting is a field, a key, and a setter — never a `setString` at a call
site. A setter that updates the state and forgets to persist works perfectly until the next
launch, which is the hardest kind of bug to notice and the easiest to introduce one call site
at a time. The store is loaded in `main()` and read **synchronously** thereafter, so the first
frame is already correct; anything lazily loaded here paints the default and then swaps.

---

## Testing

- **HTTP is tested against recorded fixtures** via `package:http/testing.dart`'s `MockClient`.
  CI never needs a live Plex server. Follow this for new API surface.
- **Database code is tested against real in-memory SQLite** — `AppDatabase(NativeDatabase.memory())`.
  Not mocks; the point is catching schema and index mistakes.
- Two import collisions you will hit:
  - `import 'package:drift/drift.dart' hide isNull;` — drift and matcher both export `isNull`.
  - `import 'package:drift/drift.dart' show Value;` when a test only needs `Value`.
- Tests assert *behaviour that would fail silently*, not coverage for its own sake. Each one
  carries a comment explaining what breaks if it regresses.

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

In three of those four, a competent-looking fix to the named component was within reach and
would have been wrong. What works instead:

- **Read the counters first.** That is what the Sync status screen is for, and it settled the
  fourth case in one reading.
- **Ask one sharp question when the symptom is ambiguous** — "does the bar not move, or does
  it snap back?" separates a disabled control from a latency problem, and they share no code.
- **Prefer a question over a plausible fix.** Shipping the wrong fix costs more than asking,
  because it also removes the evidence.

---

## Traps already paid for

Do not rediscover these.

**Debugging on the OPPO device — filter logcat by PID, never by keyword.** ColorOS floods
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
the *host* package, gets `0`, and throws — killing the entire notification. Don't add it back.

**Never call `super.stop()` (or otherwise `add` to `playbackState`) in `PlexifyAudioHandler`.**
That subject is fed from the player with `pipe`, and rxdart refuses a manual `add` while a
stream is being piped in — the call throws *"You cannot add items while items are being added
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
something needs installing — this produced one wrong diagnosis already.

**Flutter needs Windows Developer Mode** for plugin symlinks. Already enabled.

**The Windows runner builds as C++20, deliberately.** Under C++17, C++/WinRT falls back to
`<experimental/coroutine>`, which current MSVC rejects outright rather than warning about —
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
bucket lands at the top of a list while an A–Z rail shows it at the bottom — tapping it jumps
to the wrong end. `artist_index.dart` sorts non-letters last explicitly.

**A resolved address goes stale, and it presents as a playback bug.** `connectServerProvider`
picks whichever connection wins the startup wave race. A phone that connects on the LAN and
then leaves kept aiming at the local address — every request, the notification socket, the
poll, and any audio URL already handed to `just_audio`. The symptom was "playback stops when
I go outside" while launching cold on cellular worked perfectly, which points the
investigation at the audio layer rather than the connection. Fixed in #41 by
`ConnectionMonitor`. **Anything that caches a resolved address needs an invalidation story
before it is relied on** — artwork URLs (#21) are the next one.

**Plex's dashboard needs `X-Plex-Session-Identifier`, and it must be stable.** Without the
header the server accepts timeline reports, answers 200, and lists nothing — the client looks
correct and the dashboard looks broken. With a *fresh* value per launch it lists too much:
every relaunch claims a new slot while the old one lingers until the server times it out, so
quitting and reopening shows two copies of Plexify playing at once. It is persisted
alongside the client identifier so a relaunch replaces the previous entry. That is also what
makes it self-healing after a crash or a force-quit, neither of which gets to say goodbye.
`AppLifecycleListener.onExitRequested` sends an explicit `stopped` for the clean case, and is
bounded by a timeout — an unreachable server must never be able to stop the app closing.

**A "once only" flag guarding queued work has two wrong places to be reset.** The scrobble
mark in `timeline_reporter.dart` must be cleared only if it still refers to the track being
left. Cleared synchronously when the track changes, the outgoing track loses its mark before
the queued closure evaluates it and gets counted twice. Cleared unconditionally inside that
closure, it discards a mark the *incoming* track already earned — because a queued report can
run between the event arriving and the closure executing. Both produce duplicate plays, and
neither is visible without a test that counts.

**A `FutureProvider` keeps serving its previous value while it re-resolves.** Verified, and
load-bearing: it is why invalidating `connectServerProvider` on a network change does not
flash the whole album grid to placeholders. It also means a test must `await` the rebuild
before asserting the new value — reading straight after an invalidate returns the *old* one,
which looks like the provider ignoring you.

**Side effects in a derived provider's build body only happen if something is watching.** The
first attempt at remembering the last-good server put the write in `plexServerProvider`,
which worked in the app — the widget tree watches it constantly — and failed in a test that
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
timeout, because the case where it is slowest — a server that has stopped answering — is
exactly the case where the app must still close promptly.

**Turning "not connected" into a state you cannot leave.** The first cut of #41 let a failed
re-resolve clear the server. That reads as honest and is a dead end: no server means no
client, no client means nothing makes requests, and no requests means `ConnectionHealth` can
never observe another failure — so nothing ever retries. Recovery depended entirely on the OS
volunteering a connectivity event. The connection is now sticky: it keeps the last address
that worked, and only signing out clears it. Generally, **a recovery mechanism driven by
failures must leave something running that can still fail.**

---

## The music transcode endpoint

Measured against James's server on 5 Aug 2026 by `TranscodeProbe`, over both the LAN and the
remote route, on Windows and Android. **The two routes behaved identically in every respect**,
which is itself the finding — no route-specific handling is needed.

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
It is easy to assume the headers `PlexClient` already sends cover this — they do not: the URL
is handed to the audio engine, which does its own HTTP and carries none of them. This cost two
round trips to find, because a 400 says nothing about which parameter was missing.

Everything richer also works (`directStream=1`, the full web-client set with a decode
profile), so none of it is required. `TranscodeProfile.identified` is the default in
`transcodeUrl` for that reason.

### What it does and does not do

| | |
|---|---|
| Progressive, not HLS | **Yes** — `audio/mpeg`, answered directly, no redirect. Retires risk #1 in the plan: transcoded playback is cacheable. |
| Range requests | **No** — 200 for a ranged request, whole stream offered. |
| Declared length | **No** — a live transcode has no length to declare. |
| `offset=` | **Yes** — genuinely starts partway in. This is the *only* way to seek here. |
| Bitrate cap | **No.** See below. |
| `stop?session=` | **Yes** — 200 every time, for every session. |

### There is no bitrate control

`musicBitrate`, `maxAudioBitrate`, and an `add-limitation(...audio.bitrate...)` inside
`X-Plex-Client-Profile-Extra` were each asked for 128 kbps. All three returned the natural rate
unchanged, byte for byte, on both routes.

Plex's own `/transcode/sessions` record confirms it is not a misread request — `audioDecision:
transcode`, `sourceAudioCodec: flac`, `container: mp3` — and carries **no bitrate field at
all**. The output is VBR mp3 landing around 235–242 kbps depending on the material.

**So #23 is not a quality ladder.** It is one binary decision: direct-play the original, or
transcode at whatever rate Plex picks. Against a FLAC that is still a large saving; against an
mp3 already smaller than ~240 kbps, transcoding costs *more* data for *worse* audio, so a
policy that transcodes everything on cellular would be actively harmful. The probe's "Is
transcoding worth it for this track?" check measures the source rate for exactly this reason.

### Two things that will mislead the next reader

- **Plex issues its own transcode session key** rather than echoing the `session` parameter, so
  a record fetched from `/transcode/sessions` cannot be matched to a request by id. The probe
  falls back to position and says so.
- **`LockCachingAudioSource` copes with all of this**, which is not obvious. It requires HTTP
  200 on its first fetch (Plex gives 200), treats a missing content-length as `null` rather
  than an error, and still renames the completed cache file. What it cannot do is seek *ahead*
  of what it has downloaded — that path issues a ranged sub-request and throws on anything but
  206. Seeking a transcode must go through `offset=` instead.

## Things only the user can do

- **Approve the Plex PIN** in a browser — sign-in cannot be automated.
- **Confirm audio actually sounds right** — gapless seams, lock-screen controls, background
  playback. Building successfully proves nothing here.
- **Run Plex's sonic analysis** (Settings → Library → Analyze). Takes hours to days and gates
  sonic radio.
- **Install software or change system settings.**
- **Anything needing the real Plex library.** Tests run against fixtures, so behaviour that
  depends on what the server actually returns — whether a filter is honoured, what a
  notification frame really looks like — can only be confirmed on James's server.

### Verified against the real server

- Push sync delivers a newly added album **instantly**.
- Ratings set in Plex arrive by poll, not push, and need the refresh button to appear at once.

### Verified without the user, where it looked impossible

Two things that seemed to need a human turned out not to:

- **Windows media keys**, by querying the OS for the registered media session
  (`GlobalSystemMediaTransportControlsSessionManager` from PowerShell) and synthesising
  `keybd_event` presses for play/pause, next and previous while watching the app's log.
- **Whether a test actually discriminates**, by temporarily breaking the code it guards and
  confirming it fails. Do this for any test asserting an ordering, a race or a "only once"
  rule.

Reach for that pattern before declaring something unverifiable.

That second one is not a confidence ritual — it has already caught a test that passed for the
wrong reason. A test named for the single-flight guard in `ConnectionMonitor` was in fact
being satisfied by the cooldown, because the fake clock never advanced; disabling the guard
left all sixteen tests green. The replacement forces both attempts past the cooldown so only
the guard can refuse the second. **A test whose name and mechanism have quietly come apart is
worse than no test**, because it is counted as coverage. Suspect any test that passes the
first time you write it against code you have not yet seen fail.

---

## Git

Every commit so far is authored `unknown <james@nomoss.co>` — `user.name` is unset globally.
Still worth setting; the history can be rewritten afterwards if it matters.

Commit messages explain *why*, and **record wrong turns explicitly**: one notes that R8
shrinking was ruled out before the real cause was found, another that a claim about delta
sync backfilling ratings was wrong and why. This has already prevented re-investigation more
than once. Keep doing it — a message that only describes the final state throws away the
expensive part.

Write the message to a file and use `git commit -F`. PowerShell here-strings mangle multi-line
`-m` arguments; that cost one confusing failure already.

Check `git status` before `git add -A` — it has already swept in a `debug.lnk` shortcut
holding an absolute path and a machine id. `*.lnk` is ignored now, but build output and
editor droppings will keep finding new ways in.

Sign commits with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```
