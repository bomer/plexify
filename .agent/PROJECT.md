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
flutter test             # 133 tests, no live server needed
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

**Turning "not connected" into a state you cannot leave.** The first cut of #41 let a failed
re-resolve clear the server. That reads as honest and is a dead end: no server means no
client, no client means nothing makes requests, and no requests means `ConnectionHealth` can
never observe another failure — so nothing ever retries. Recovery depended entirely on the OS
volunteering a connectivity event. The connection is now sticky: it keeps the last address
that worked, and only signing out clears it. Generally, **a recovery mechanism driven by
failures must leave something running that can still fail.**

---

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
  confirming it fails. Worth doing for any test asserting an ordering or a race.

Reach for that pattern before declaring something unverifiable.

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

Sign commits with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```
