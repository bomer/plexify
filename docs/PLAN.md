# Plexify — a fast, clean Plex music client for Windows + Android

## Context

The music library now lives on Plex, but Plexamp's UI is mediocre for how it actually gets
used: reaching recent playlists quickly, searching artists/albums, and moving between "now
playing" and "finding something else" without losing your place.

This replaces it with a purpose-built client that is fast, minimal, and Spotify-informed in
its navigation model. Plex is the source of truth — including scrobbling plays back so
history stays in one place. When an album isn't in the library, the app hands off to
qBittorrent to fetch it.

Target: cold start to audible playback under 2 seconds, no perceptible frame drops while
browsing, and browsing that never feels network-bound.

## Decisions (all confirmed)

| Area | Decision |
|---|---|
| Stack | Flutter — `just_audio` + `audio_service`; `just_audio_media_kit` on Windows |
| Targets | Windows desktop `.exe` + Android APK |
| Project location | **Move to `C:\dev\plexify`** (see Prerequisites) |
| Library scale | ~5k–50k tracks — paginated background sync, lazy artwork |
| Network | Used both on LAN and remotely |
| Quality | Adaptive: LAN direct-play FLAC → remote wifi probe → cellular 320k AAC |
| Cache | Bounded LRU, ~2GB Android / ~10GB desktop, **fills on wifi/LAN only** |
| Queue | Play replaces the queue; single flat list, no separate manual-queue tier |
| Autoplay | Sonic radio continues when the queue runs dry, on by default |
| Playlists | **Read-only** in v1 |
| Sonic radio | **In scope** |
| Catalog | MusicBrainz + Cover Art Archive — for albums you *don't* own |
| Search | Unified: library instantly from drift, "Not in your library" below |
| Acquisition | qBittorrent only — add with `category=Music`, no post-processing |
| YouTube | Out of v1 (provider seam built, nothing more) |
| Offline | Streaming + smart cache; no explicit download UI |
| Visual | Clean and minimal, Spotify-informed navigation |
| Code style | Conventional and documented — Riverpod **without** code generation, README included |
| Sequencing | Thin vertical slice through all layers, both platforms, first |

Explicitly out: playlist editing, cross-device handoff, Last.fm, iOS, multi-user, Cast.

## Prerequisites (before Phase 0)

Verified state: Flutter is **not installed** on Windows or in WSL. Android SDK **is**
present at `C:\Users\James\AppData\Local\Android\Sdk`. `vswhere` finds **no** Visual Studio
instance. Java is present on both.

1. Install the **Flutter SDK for Windows**.
2. Install **Visual Studio 2022** with the *Desktop development with C++* workload —
   required for the Windows desktop target; the build fails without it.
3. Move the project to `C:\dev\plexify`. It currently sits on the WSL filesystem while
   the Android SDK is on Windows — Gradle across the 9p boundary is punishingly slow and
   Flutter's Windows tooling handles `\\wsl.localhost\` UNC paths badly. The additional
   working directory `\\wsl.localhost\ubuntu\home\james\dev\music-player` becomes obsolete.
4. **Start Plex's sonic analysis now** (Settings → Library → Analyze). It takes hours to
   days on a library this size and is a hard prerequisite for sonic radio in Phase 6.
   Starting it today means it's done before the code needs it.
5. Confirm `flutter doctor` is clean for both `windows` and `android`.

## Architecture

Feature-first, thin UI over a repository layer, all playback behind one interface.

```
lib/
  core/
    plex/          PlexAuth, PlexServer, PlexClient, models
    catalog/       MusicBrainzClient + Cover Art Archive — albums you don't own
    qbit/          QbitClient (WebUI API v2)
    db/            drift schema — cached library, play history
    audio/         PlaybackHandler (audio_service), queue, cache policy, quality policy
    source/        SourceProvider interface  ← YouTube would slot in here
  features/
    auth/          PIN link flow, server picker
    library/       artists, albums, playlists (read-only)
    search/        unified search
    player/        now-playing + mini player
    radio/         sonic radio + autoplay
    acquire/       qBittorrent search / add / monitor
  shell/           navigation scaffold, sidebar, routing
```

**State:** Riverpod, no codegen, explicit providers. **DB:** `drift`. **Secrets:**
`flutter_secure_storage` (Android Keystore / Windows DPAPI).

### The sync design

This is the part most likely to go wrong — a cache layer that makes newly-added music take
*longer* to appear would defeat the point. Three tiers:

1. **Websocket push (primary).** Connect to `/:/websockets/notifications` with the Plex
   token while foregrounded. Plex emits a `TimelineEntry` the moment it finishes scanning an
   item; we delta-sync just that item. Sub-second, and *faster* than Plexamp reflecting the
   change. (Confirmed against Tautulli's `web_socket.py`, which uses exactly this.)
2. **Cheap change detection (safety net).** `GET /library/sections` returns `updatedAt` and
   `scannedAt` per section — one tiny response. Polled ~30s foreground, plus on every app
   resume and network reconnect. Catches whatever the websocket missed while backgrounded.
3. **Delta sync.** Fetch only `updatedAt >= lastSync`, paginated with
   `X-Plex-Container-Start` / `X-Plex-Container-Size`. Never a full re-sync.

**The rule that makes this safe: the cache is additive, never authoritative about absence.**
Search queries drift *and* fires `/hubs/search` in parallel, merging results. Detail views
render from cache instantly, then revalidate and patch. The cache can only make things
appear faster; it is structurally incapable of being the reason something is missing.

Pull-to-refresh triggers `/library/sections/{id}/refresh` **and** a delta sync, so the
manual scan-then-check-then-wait dance becomes one gesture.

Deletions are the real gap — they don't appear in an `updatedAt` delta. Handled by a
periodic ratingKey-set reconcile (keys only, no metadata) plus websocket delete events.

## Plex integration

**Auth — PIN link flow**, no password ever handled by the app:
`POST plex.tv/api/v2/pins?strong=true` with a persistent `X-Plex-Client-Identifier` → open
`app.plex.tv/auth#?clientID=…&code=…` in the system browser → poll
`GET plex.tv/api/v2/pins/{id}` until `authToken` appears → store in secure storage.

**Server discovery:** `plex.tv/api/v2/resources?includeHttps=1&includeRelay=1`. Race all
connections (local → remote → relay), keep the fastest that answers.

**Endpoints** (`X-Plex-Token` header on every request):

- `/library/sections` → the `type="artist"` section
- `/library/sections/{id}/all?type=8|9|10` → artists / albums / tracks
- `/library/metadata/{ratingKey}/children` → artist→albums, album→tracks
- `/playlists?playlistType=audio`, `/playlists/{id}/items`
- `/hubs/search?query=…` (fallback alongside local search)
- `/photo/:/transcode?width=&height=&url=…` for artwork, disk-cached
- `/library/sections/{id}/all?type=10&sort=lastViewedAt:desc` and
  `/status/sessions/history/all?librarySectionID={id}&sort=viewedAt:desc` for recent plays
- `/library/metadata/{ratingKey}/nearest?limit=50` → sonic radio
- `/:/timeline` during playback, `/:/scrobble` on completion

*Assumes you are the server owner/admin* — `/status/sessions/history/all` requires it.

### Playback, quality and cache

Direct-play by default: resolve `Media > Part` `key` and stream the original. ExoPlayer
handles FLAC/ALAC natively on Android; libmpv covers everything on Windows.

Quality policy: LAN → direct play original. Remote wifi → bandwidth probe, direct play if it
holds, else 320k. Cellular → 320k AAC. Data-saver → 128k. Overridable per network.

**Two traps this creates, both must be handled from the start:**

- **Cache keys must be `(trackId, qualityDecision)`, not `trackId`.** Otherwise a 320k copy
  cached on cellular gets served forever once you're back on LAN, and the fidelity that
  adaptive quality exists to protect silently never arrives.
- `LockCachingAudioSource` caches **progressive HTTP only, not HLS**. Plex's transcode
  endpoint has both an HLS (`start.m3u8`) and progressive (`start.mp3`) form. If the
  progressive form can't be made to work, transcoded playback cannot be cached at all.

Cache: bounded LRU, 2GB Android / 10GB desktop, configurable, **fills on wifi/LAN only** so
it never burns cellular in the background. This layer is what later becomes explicit
offline downloads.

Queue: playing anything replaces the queue with a new flat list. When it empties, sonic
radio seeds from what just played and continues (toggleable).

## Unified search and acquisition

qBittorrent search returns *torrent filenames*, not a music catalog — so on its own the app
could never tell you an album exists, only that someone is seeding something matching your
string. **MusicBrainz** supplies the catalog: free, no API key, and the canonical choice
(Lidarr, Picard and beets all use it). Cover art comes from Cover Art Archive on the same
MBIDs.

One search box, two tiers rendered as separate sections:

```
IN YOUR LIBRARY        drift, instant, every keystroke
NOT IN YOUR LIBRARY    MusicBrainz, debounced ~400ms, cached
```

**MusicBrainz rate-limits to ~1 request/second and returns 503 for generic User-Agents.**
So: a descriptive `User-Agent` with contact info, a single-flight debounced queue (never
per-keystroke), and aggressive caching of results in drift. Local results always land first
and independently, which is what makes the limit invisible in practice — the app never
appears to wait on it.

De-duplication matters: MusicBrainz results already present in your library must be filtered
out of the lower section, matched on MBID where Plex has one and normalised artist+title
where it doesn't. Getting this wrong means every album you own appears twice.

Acquisition flow: tap a "not in library" album → tracklist and art from MusicBrainz →
**Find download** → `QbitClient` searches with a query built from the *structured* metadata
(artist + album + year) rather than the raw typed string → results ranked by seeders and
format → add with `category=Music`.

## qBittorrent integration

Internet-accessible, authenticated by **qBittorrent's own web login form** — which is the
native `/api/v2/auth/login` SID cookie flow. One auth layer, no HTTP Basic. The 5.0 WebUI
API documents cookie/SID auth only; there is no API key mechanism, so the app stores the
username and password in secure storage.

- `POST /api/v2/auth/login`, form-encoded, → `SID` cookie held for the session
- **`Referer` or `Origin` must exactly match the `Host` header, including port.** This is
  qBittorrent's CSRF protection and is the most common cause of unexplained 403s.
- **403 also means "IP banned for too many failed logins."** The client must make a single
  attempt then back off with a clear error state — a naive reconnect loop would get the
  phone's IP banned by your own server.
- `/api/v2/search/*` for search (requires qBittorrent's search plugins enabled server-side;
  detect and warn if not)
- `/api/v2/torrents/add` with `category=Music` — your existing automation routes it to the
  Plex-watched folder, so **no renaming, retagging or post-processing is needed**
- `/api/v2/torrents/info?category=Music` polled for progress
- On completion → `/library/sections/{id}/refresh`, then delta sync

Worth confirming that endpoint is HTTPS: the form login sends the password as plaintext in
the request body, and those credentials will be stored on your phone.

## UI

Clean and minimal, Spotify-informed navigation. Dark base, restrained chrome, content-first.

- **Persistent left sidebar** — Home, Search, Library, with recent playlists listed directly
  beneath so they're always one click away. Collapses to a bottom nav bar on Android.
- **Persistent mini-player**; tapping expands Now Playing as an overlay that slides over the
  current view **without unmounting it**, so dismissing returns you exactly where you were
  mid-browse. This drives the routing design and must be right from Phase 4 — it cannot be
  retrofitted.
- **Home** — recently played, recently added, jump back in.

## Phases

**Phase 1 — vertical slice (the priority).** Log in, list albums, tap one, hear it play on
*both* Windows and Android with working lock-screen controls. No cache, no search, no
styling. Proves Plex PIN auth, server discovery, direct play, `audio_service` on Android and
the `media_kit` backend on Windows — the four riskiest assumptions — in ~1-2 weeks.
Runs alongside a **transcode spike**: establish working parameters for
`/music/:/transcode/universal/start`, confirm the progressive form works and caches. This is
the least-documented part of the Plex API and everything about remote listening depends on
it, so it must not be deferred.

**Phase 2 — data layer.** drift schema, paginated background initial sync, websocket +
delta sync, artwork cache. *Milestone: library browsable instantly, offline, from cache.*

**Phase 3 — playback hardening.** Queue, shuffle/repeat, gapless, adaptive quality, LRU
disk cache, Plex timeline + scrobble.

**Phase 4 — UI shell.** Sidebar, recent playlists, mini player, Now Playing overlay, Home.

**Phase 5 — search.** Local drift-backed instant search merged with `/hubs/search`, plus the
"Not in your library" tier from MusicBrainz: debounced single-flight queue, result caching,
and MBID/normalised-title de-duplication against the library.

**Phase 6 — sonic radio.** `/nearest`, radio seeding, autoplay-when-dry, plus a clear
"sonic analysis incomplete" state rather than silently returning nothing.

**Phase 7 — acquisition.** Album detail for non-owned releases, "Find download" →
qBittorrent search seeded from structured MusicBrainz metadata, ranked results, add with
`category=Music`, progress monitoring, Plex refresh on completion. Reachability-aware UI
that degrades cleanly rather than hanging.

**Phase 8 — packaging.** Signed APK, Windows bundle, icons, first-run flow, README.

## Verification

Every phase demonstrated on **both** targets before moving on — desktop-only verification
hides every mobile audio problem, which is the exact failure mode this stack was chosen to
avoid.

```bash
flutter run -d windows
```

```bash
flutter run -d android
```

- **Unit tests** for `PlexClient` and `QbitClient` against recorded HTTP fixtures, so CI
  needs no live server.
- **Widget test** that the Now Playing overlay preserves underlying navigation state.
- **Sync tests** proving the additive-cache rule: an item present on the server but absent
  from drift must still surface in search.
- **De-duplication test**: an album present in the library must never also appear in the
  "Not in your library" section, matched by MBID and by normalised artist+title.
- **Manual checks** automation can't cover: background playback survives screen-lock and
  backgrounding on Android; lock-screen transport controls work; gapless between consecutive
  album tracks has no audible seam; a track added to Plex appears in-app within seconds
  without a manual refresh; plays appear in Plex's own history; remote/off-LAN works;
  quality actually switches between LAN and cellular.
- `flutter build apk --release` and `flutter build windows --release` succeed; APK size
  checked against the ~20MB expectation as a lightweightness regression guard.

## Known risks

1. **Plex music transcode endpoint** — poorly documented, known to be fiddly. Retired early
   by the Phase 1 spike. If the progressive form can't be made to work, remote listening
   falls back to direct-play-only and cellular use becomes expensive.
2. **Sonic analysis may not be complete** on the library. Start it now.
3. **MusicBrainz is a third-party dependency on the search path.** Mitigated by the two-tier
   design — if it's slow, rate-limited or down, local search is entirely unaffected and the
   lower section simply doesn't appear. It must never be able to block or degrade searching
   your own library.
4. **Flutter is new to you** — hence conventional patterns, explicit structure, and a README.
   Expect Phase 1 to take longer than its size suggests, and to be the phase where most of
   the learning happens.
