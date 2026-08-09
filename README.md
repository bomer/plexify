# Plexify

A fast, clean and simple music client for a Plex library. Windows desktop and Android, one codebase.

The full build plan (decisions, phases, API details and known risks) is in
[docs/PLAN.md](docs/PLAN.md). This README covers architecture and how to run things.

Built because Plexamp's UI basically just a mobile wrapped experience. I wanted something more
akin to Spotify with playlist on the left and easily jumping between playlists, searching, and
moving between "now playing" and "finding something else" without losing your place.
Plex is the source of truth and your plays filter back, whilst handling transcoding on Mobile.

This was coded entirely with Claude (and potentially other AI Agents in future ) to test their capability
in building custom software for me.

As a developer, I really wanted a better experience but it would have taken me weeks to learn
dart and this weeks to build. I'm a bit worried it did too much work under the hood handling
streams that it might make it's own issues. We'll find out.

![Plexify on Windows](https://github.com/bomer/plexify/blob/main/docs/windows.png?raw=true)

## Requirements

- **Flutter** 3.44+ (`C:\Users\James\flutter-sdk\flutter`)
- **Visual Studio 2026** with Desktop development with C++, for the Windows target
- **Android SDK** 36 with cmdline-tools, for the Android target
- **Windows Developer Mode enabled**, Flutter needs symlink support to build with plugins.
  `start ms-settings:developers`. Builds fail without it.

Verify with `flutter doctor`; it should report no issues.

## Running

```
flutter run -d windows
flutter run -d android
```

Drift generates database code. After changing anything under `lib/core/db/`:

```
dart run build_runner build --delete-conflicting-outputs
```

## Putting a build on the phone

Two commands, in this order.

```
flutter build apk --release --target-platform android-arm64
```

```
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**`flutter install` does not build.** It pushes whatever APK is already on disk,
so skipping the first command silently installs a stale one. That is a
frustrating five minutes if you are trying to confirm a fix.

Add `-s <device-id>` to the install if more than one device is attached;
`adb devices` lists them.

**Test in release on Android, not debug.** Flutter injects the `INTERNET`
permission into debug manifests only, so a debug build hides manifest problems
that break release entirely. `arm64` because it is the only architecture the
test device needs, and building all three roughly triples the time.

Until a signing key exists these builds are signed with the debug key. That is
fine for running and wrong for distributing, which is why the release script
refuses to do it.

## Releasing

```
powershell -File tool/package.ps1
```

Builds both targets into `dist/` and checks them before they leave: the APK must
be signed with the real upload key rather than the debug one, it must be under
its size budget, and the Windows bundle must contain the DLLs the exe cannot
start without. [tool/README.md](tool/README.md) covers creating the signing key,
which is a one-time job and has to be done by hand.

The Windows deliverable is the **whole** `Release` folder, not just
`plexify.exe`. The exe is about 150KB and will not start on its own.

## Architecture

Feature-first. The UI never talks to Plex directly. It reads from a local SQLite cache
(drift) that a background sync keeps current. This is what makes browsing feel instant
rather than network-bound.

```
lib/
  core/
    plex/       Plex auth, server discovery, API client, models
    catalog/    MusicBrainz, albums you DON'T own, for search + acquisition
    qbit/       qBittorrent WebUI API client, ranking, download monitor
    db/         drift schema: cached library, play history  [codegen]
    audio/      playback handler, queue, cache policy, quality policy
    source/     SourceProvider interface, the seam for future sources
  features/
    auth/       PIN link flow, server picker
    library/    artists, albums, playlists (read-only in v1)
    search/     unified search
    player/     now playing + mini player
    radio/      sonic radio + autoplay
    acquire/    qBittorrent search / add / monitor
  shell/        navigation scaffold, sidebar, routing
```

**State:** Riverpod, no code generation, providers are declared explicitly so the graph is
readable without understanding build*runner. (Drift \_does* use codegen; that's unavoidable
and is the only generated code in the project.)

**Storage:** drift (SQLite) for the library cache. `flutter_secure_storage` for the Plex
token and qBittorrent credentials (Android Keystore and Windows DPAPI respectively). Never
plain SharedPreferences for secrets.

### The two rules that matter

**1. The cache is additive, never authoritative about absence.**

Search queries the local database _and_ Plex in parallel, merging results. Detail views
render from cache instantly, then revalidate and patch in differences. The cache can only
ever make things appear _faster_; it must never be the reason something appears missing.
Violating this reintroduces exactly the "I added it to Plex and it won't show up" problem
this app exists to avoid.

Sync has three tiers:

1. **Websocket push.** `/:/websockets/notifications` emits a `TimelineEntry` the moment
   Plex finishes scanning an item. Sub-second, and the primary mechanism.
2. **Cheap change detection.** `/library/sections` returns `updatedAt`/`scannedAt` per
   section in one tiny response. Polled every ~30s foreground and on resume/reconnect, to
   catch anything the websocket missed while backgrounded.
3. **Delta sync.** Fetch only `updatedAt > lastSync`, paginated. Never a full re-sync.

Deletions don't appear in an `updatedAt` delta, so a periodic ratingKey-set reconcile
handles those separately.

**The delta filter is only used where it can work.** Plex moves a row's `updatedAt` when
music is added and leaves it alone when a rating changes, so a clock-triggered pass filters
and the slower sweep does not. Getting that wrong makes ratings set elsewhere unreachable
while still costing the requests.

**2. Cache entries are keyed by `(trackId, qualityDecision)`, never `trackId` alone.**

Quality adapts to the network: direct-play the original at home, ask Plex to transcode over
mobile data. If the cache key ignored quality, a transcoded copy made on the train would be
served forever once you're back on the LAN, silently defeating the point of deciding.

**There is no bitrate in that decision, and that is a measured finding.** Plex's music
transcoder was asked for 128kbps three documented ways and returned the natural rate each
time, so the only lever that exists is whether transcoding happens at all. Against a FLAC
that is still a large saving; against an mp3 already smaller than the transcoder's own
output it costs more data for worse audio, which is why the policy has a floor.

The audio cache is **mobile only**. `LockCachingAudioSource` renames its part-file on
completion while still holding it open, which POSIX allows and Windows does not, and the
failure took the audio source down with it.

## Albums you don't own

Off by default, and one switch turns on both halves: a **Not in your library** tier under
search, and a **missing albums** grid on every artist page. Settings are per device, which is
exactly the granularity wanted — on a phone this is noise, and on the desktop, where
downloads actually happen, it is the point.

The catalog is **MusicBrainz**: free, no API key, and the same ids Lidarr, Picard and beets
use. Two of its rules are enforced with the same status code and neither is guessable —
roughly one request per second, and a `User-Agent` naming the application and a contact. It
answers **503** for either, which reads as the service being down. Answers are cached in
drift for a week and are _not_ cleared on sign-out: MBIDs are global, unlike Plex's
server-scoped `ratingKey`s.

**De-duplication is the part that fails quietly.** An album you own appearing in the list of
albums you don't is noise you can see; a record you're missing silently never appearing is
not. Matching prefers the MBID where Plex recorded one — it usually hasn't, since that
depends on the agent and the file tags — and otherwise compares normalised artist and title
with _edition_ qualifiers removed. `Nevermind (Deluxe Edition)` is the same record as
`Nevermind`; `Greatest Hits (Volume 1)` is not the same record as `(Volume 2)`, so only
recognised edition words are stripped and never every bracket.

Acquisition hands off to **qBittorrent**, adding with `category=Music` so existing automation
routes it to the folder Plex watches. Nothing is renamed, retagged or post-processed. When a
download finishes, Plex is asked to rescan and the library syncs on its own — that is a new
_trigger_ on the existing refresh path, not a fourth sync mechanism.

**The one-click button never queues on seeder count alone.** Torrent search matches
filenames, so the most popular hit for an album is routinely a different record that shares a
word. A result is only added unasked when its filename actually names this artist and this
album; otherwise the ranked list opens instead. One tap in the common case, never one tap
away from the wrong album.

**Nor does it queue something that is not a torrent.** Search plugins are inconsistent about
what goes in `fileUrl`: some return a magnet, some a `.torrent`, and some the human page you
would click the magnet on. qBittorrent accepts that page, answers `Ok.`, and fails decoding
HTML in its own log where nothing here can read it — so results are sorted magnets first,
then torrent files, with pages last and labelled, and tapping a page opens it in a browser
rather than pretending to queue it.

Two qBittorrent traps are handled up front, and both answer 403 against a WebUI that works
perfectly in a browser: `Referer`/`Origin` must match `Host` exactly _including the port_,
and 403 **also** means "this address is banned for repeated failed logins" — so the client
makes one attempt and then stops rather than making a ban worse.

## Platform notes

**Android:** `audio_service` runs playback in a foreground service for background playback
and lock-screen controls. Requires the service and `POST_NOTIFICATIONS` permission declared
in `AndroidManifest.xml`.

**Windows:** `just_audio` has no native Windows backend; `just_audio_media_kit` (libmpv)
provides one and must be initialised at startup before any player is constructed.

## Out of scope for v1

Playlist editing (read-only), YouTube playback, explicit offline downloads, cross-device
handoff, Last.fm, iOS, multi-user, Cast.

Torrent _management_ too. The Downloads screen is read-only: pausing, reprioritising and
deleting all exist perfectly well in qBittorrent's own interface, and a second copy here
would be one more thing to keep in step.
