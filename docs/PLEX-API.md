# The Plex API, as Plexify actually uses it

Written for someone who has never touched the Plex API and has to change something in
`lib/core/plex/`. It covers only the endpoints this app calls, and for each one what is sent,
what comes back, and what will mislead you.

There is no official public documentation. Everything here was found by reading other
clients, by trying things, and in several cases by building an instrument because trying
things gave an answer that turned out to be a lie. Where a claim came from a measurement, the
date and the machine are named, because a Plex server upgrade can change any of it.

Two probes live in the app under **Settings → Sync status** and exist for exactly that reason:
`DeltaFilterProbe` and `DiscoveryProbe`. Re-run them before trusting anything below.

---

## The one thing to understand first

**Plex accepts query parameters it does not implement, answers `200`, and returns the wrong
set.** Not an error, not a warning, not an empty `Hub` you could notice. A perfectly ordinary
success containing data that quietly does not answer the question you asked.

This has cost this project three times:

| What was sent | What was expected | What happened |
|---|---|---|
| `updatedAt>=` on a section listing | rows changed since a timestamp | filter dropped, whole library returned, every launch refetched 13,704 tracks for thirty-odd commits |
| `type=10` on the history endpoint | track plays only | **empty container**, so a server with years of history looked like it had none |
| `musicBitrate` / `maxAudioBitrate` on a transcode | a 128kbps stream | ignored, full-rate audio returned, byte for byte identical |

The lesson is not "be careful". It is: **a parameter that filters correctly and a parameter
that filters to nothing are indistinguishable from a single measurement.** Whenever you add
one, ask twice — once where it must return almost nothing, and once where it must return
everything. Both probes are built on that shape and both found a real bug on the first run.

---

## 1. Identity

Every request to plex.tv and to a server carries the headers in `PlexIdentity.headers()`:

```
Accept: application/json
X-Plex-Client-Identifier: <uuid, persistent>
X-Plex-Product: Plexify
X-Plex-Version: 0.9.0
X-Plex-Platform: Windows | Android | ...
X-Plex-Device: <same as platform>
X-Plex-Device-Name: <hostname>
X-Plex-Session-Identifier: <uuid, persistent>
X-Plex-Provides: player
X-Plex-Token: <token>            (when authenticated)
```

Four of these are load-bearing in ways that are not obvious.

**`Accept: application/json`.** Without it Plex returns XML. Every parser in this app assumes
JSON, so omitting this turns into a parse error a long way from its cause.

**`X-Plex-Client-Identifier` must be stable across restarts.** The PIN flow ties the resulting
token to it. Regenerate it and the token silently stops working, sending the user through the
link flow on every launch.

**`X-Plex-Session-Identifier` must also be stable, and this is the counter-intuitive one.**
"Session" reads like "per run". Plex keys Now Playing entries on it alongside the client
identifier, so a fresh value each launch claims a new dashboard slot while the old one lingers
until the server times it out, and quitting and reopening shows two copies of Plexify playing
at once. Reusing it makes a relaunch *replace* the previous entry, which is self-healing after
a crash or a force-quit, neither of which gets to say goodbye.

**`X-Plex-Provides: player`.** A client that provides nothing is not a player, and a server has
no reason to list it as one.

**The token can travel two ways.** As a header for anything this app fetches itself, and as a
`X-Plex-Token` query parameter for URLs handed to something else: the audio engine and the
websocket both do their own HTTP and carry none of our headers. That is why stream URLs have
the token in the query string, and it is why those URLs must never be logged.

---

## 2. Connecting

Two steps, and they use different hosts. plex.tv knows *which* servers exist; only a server
knows its own library.

### 2.1 Signing in: the PIN flow

No password is ever handled by the app. `PlexAuth`:

```
POST https://plex.tv/api/v2/pins?strong=true
  -> { "id": 12345, "code": "ABCD" }
```

Then the user opens, in their **system browser**:

```
https://app.plex.tv/auth#?clientID=<uuid>&code=ABCD&context[device][product]=Plexify&...
```

> **The `#?` is not a typo.** Those are *fragment* parameters. Put them after a plain `?` and
> the page loads, looks correct, and silently fails to prefill the code.

Then poll until the user approves:

```
GET https://plex.tv/api/v2/pins/12345
  -> { "authToken": null }      still waiting
  -> { "authToken": "xxx" }     approved
```

Quirks: a **404 means the PIN expired or was consumed** and is not worth retrying. PINs last
about fifteen minutes, so polling is capped just under that rather than forever, or an expired
PIN looks like a hang.

The token is long-lived and goes into `flutter_secure_storage` (Android Keystore, Windows
DPAPI). Never `SharedPreferences`, which is a plaintext file on both platforms.

### 2.2 Finding a server

```
GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1
```

Returns every device on the account, not just servers. Filter on `provides` containing
`server`.

Each resource carries **several `connections`**, and they are emphatically not equivalent:

| | |
|---|---|
| `local: true` | a LAN address. Fastest, and the only one where direct play is cheap |
| neither flag | the public address. Needs port forwarding or Plex Relay's fallback |
| `relay: true` | routed through plex.tv. **Bandwidth-limited by Plex.** Last resort only |

Each resource also has its own `accessToken`, distinct from the account token. Use the
server's when it is there.

`PlexDiscovery.connect` probes in **three waves — local, then remote, then relay — returning
the first connection in a wave that answers**, with a five second timeout per wave. Within a
wave the first responder wins, which is a decent proxy for lowest latency. The probe is:

```
GET <connection.uri>/identity
```

`/identity` is the right choice because it is tiny and needs no token to prove reachability.

Trailing slashes are trimmed from the winning URI. Every path in the app is written with a
leading slash, so a trailing one gives `//library/sections`, which some Plex builds serve and
some do not.

### 2.3 One rule about losing the connection

**The connection never resolves to null once it has worked.** This looks dishonest and is
load-bearing: no server means no client, no client means no requests, and no requests means
nothing can ever observe the failure that would trigger the next attempt. The app would sit
disconnected until the OS volunteered a network change. Keeping the stale address keeps the
poll running, and the failures it produces are what drive recovery. See
`connection_monitor.dart`.

---

## 3. Reading the library

Everything in this section is one server, one token, and the `MediaContainer` envelope:

```json
{ "MediaContainer": { "size": 2, "Metadata": [ ... ] } }
```

> **An empty list is an absent key, not `[]`.** Plex omits `Metadata`, `Directory` and `Hub`
> entirely when there is nothing in them. Code that reads `container['Metadata'] as List`
> throws on a perfectly ordinary empty result. `PlexClient._listOf` returns `const []` for a
> missing key, and every caller goes through it.

> **Field types are not stable.** The same field comes back as an int or a string depending on
> the endpoint and the server version. Everything in `plex_models.dart` parses through
> tolerant `_str` / `_int` / `_bool` helpers rather than casting. A malformed field should
> degrade one value, never lose the whole response.

### 3.1 Sections

```
GET /library/sections
  -> Directory[]: { key, type, title, updatedAt, scannedAt }
```

The music section is `type == "artist"`. `key` is the bare section id, e.g. `"3"`.

`updatedAt` and `scannedAt` are the cheap change-detection tier: one tiny response tells you
whether a delta sync is worth doing at all.

> **`musicSection()` returns the *first* music section and v1 assumes there is one.** A second
> music library is invisible, and the symptom is a track count short by however much is in it,
> with nothing on screen to explain it. Sync status names every music section for this reason.

### 3.2 Listing a section

```
GET /library/sections/{key}/all?type={8|9|10}&sort=addedAt:asc
Headers: X-Plex-Container-Start: 0
         X-Plex-Container-Size: 200
```

Metadata type numbers: **8 artist, 9 album, 10 track.**

**Pagination is via headers, not query parameters.** That is what the server actually honours.
The response then carries `totalSize`, which is what makes a real progress bar possible rather
than a spinner.

`X-Plex-Container-Size: 0` asks for the count alone: `totalSize` with no metadata. One small
response whatever the library's size, and the basis of every counting query in the app.

`sort=addedAt:asc` matters for correctness, not taste. A stable order means an interrupted sync
can resume from an offset without skipping or repeating rows, which an unspecified order would
not guarantee.

### 3.3 The delta filter, and what it costs to get wrong

```
GET /library/sections/{key}/all?type=10&updatedAt>{epochSeconds}
```

Measured on James's server, 6 August 2026, by `DeltaFilterProbe`:

| Spelling | Result |
|---|---|
| `updatedAt>=` | **silently ignored**, whole section returned |
| `updatedAt>>=` | silently ignored |
| `updatedAt>` | works |
| `updatedAt>>` | works |

`PlexClient.deltaFilter` is `updatedAt>`. It is **strict**, so the client asks for one second
*earlier* than the stored cursor: the cursor is the newest `updatedAt` already held, and
strictly-newer would skip a row sharing that exact second which has not been seen. A bulk edit
stamps many rows with one timestamp, so that is real rather than theoretical. The cost of the
alternative is one already-cached row coming back per pass, which upserts to itself.

> **Plex moves `updatedAt` when music is added and leaves it alone when a rating changes.** So
> a clock-triggered pass may filter, and the slower sweep must not: a filtered sweep is a
> request that costs money and is structurally incapable of finding the edits it exists for.

### 3.4 Children, and playlists

```
GET /library/metadata/{ratingKey}/children     artist -> albums, album -> tracks
GET /library/metadata/{ratingKey}              one item, for a push notification
GET /playlists?playlistType=audio              the playlist list
GET /playlists/{ratingKey}/items               its tracks, in playlist order
```

A **404 from `/library/metadata/{key}` means the item is genuinely gone.** Every other failure
throws. That distinction matters: treating a timeout as "deleted" lets a network blip empty
the cache.

Playlist order is significant and must be preserved as returned. Playlists are *arranged*, not
sorted.

Three quirks on playlists, each of which has bitten:

**Artwork is `composite`, not `thumb`.** Plex generates a mosaic of the first few sleeves and
exposes it under a different key. Reading `thumb` yields nothing at all, silently.
`PlexPlaylist.fromJson` maps `composite ?? thumb` onto its own `thumb` field.

**Track count is `leafCount`, not `size`.**

**Smart playlists (`smart: true`) are generated from rules server-side and change without an
`updatedAt` bump.** A cached copy goes stale invisibly, so their contents are always
revalidated on open rather than served from cache.

**`lastViewedAt` on a playlist is Plex's, and this app can never move it.** Playback is
reported against the *track* (see §6), so the server never learns a playlist was involved. Any
local write is overwritten by the next sync. That is why `PlaybackHistory` exists as a
client-owned table, and why anything meaning "what did *I* put on" reads that instead. This
caught Home once and the sidebar a month later with an identical symptom: a list that looks
plausible, is ordered by something real, and never moves whatever you do.

### 3.5 Search

```
GET /hubs/search?query=...&limit=20
  -> Hub[]: { type: "album" | "track" | ..., Metadata: [...] }
```

Every media type comes back in one response; the hub's `type` says which list its items belong
in. This is consulted *alongside* the local cache, never instead of it, and it returns empty
rather than throwing: a search that works offline for the library you have is worth more than
one that errors because plex.tv was briefly unreachable.

### 3.6 Hubs, which is where the Home screen comes from

```
GET /hubs/sections/{key}?includeStations=1
```

Measured on James's server, 10 August 2026, this returned **eleven** hubs:

| Identifier | Title | Type | Size |
|---|---|---|---|
| `music.recent.played` | Recently Played Music | artist | 6 |
| `music.recent.added` | Recently Added in Music | album | 6 |
| `music.recent.artist` | More by Regina Spektor | album | 6 |
| `music.stations` | Stations | station | 4 |
| `music.top.period` | Top Albums from 2000s | album | 6 |
| `music.recent.genre` | More in Folk | album | 6 |
| `music.popular` | Most Played in November | album | 6 |
| `music.vault` | Haven't played in 5 years | artist | 0 |
| `music.recent.label` | More from Loudr | album | 1 |
| `music.touring` | Artists on Tour | artist | 0 |
| `music.videos.new` | Recently Added Music Videos | clip | 0 |

**Items arrive inline** in each hub's `Metadata`, so a hub is a finished row rather than a
reference to fetch. Verified by reporting declared `size` against parsed count side by side in
the probe.

The identifiers are suffixed with the section id (`music.popular.3`).

> **Do not key on an identifier.** What a section publishes varies by server version and by
> whether sonic analysis has run. Home renders a row because it arrived with a title and some
> albums, not because it was recognised, which means a server upgrade can only ever add rows.
>
> This app previously reimplemented `music.recent.artist`, `music.recent.genre` and
> `music.popular` by hand, on the written-down conclusion that Plex did not publish them. That
> conclusion was reasoning rather than measurement and was wrong, and both bugs found on 10
> August lived in the reimplementations.

### 3.7 Play history

```
GET /status/sessions/history/all?librarySectionID={key}&sort=viewedAt:desc
Headers: X-Plex-Container-Size: 1000
```

Every play from every client, going back years. **Requires server-owner access, and returns
an empty container to everyone else rather than a 403** — so "no plays" and "not allowed"
arrive identical. `DiscoveryProbe` exists partly to separate those.

Two traps, both measured on 10 August 2026:

**Do not send `type=10`.** It is how a *section listing* is narrowed to tracks; this endpoint
answers it with an empty container. The same request without it returned every row asked for.
Rollup rows are filtered after parsing, on the row's own `type` field, and **a row with no
type at all is kept** — discarding everything a server does not label is precisely how this
started.

**The rows name the track, not the album.** There is no `parentRatingKey`. 43 plays in a month
resolved to zero albums until the album was looked up from the synced tracks table by the
track's ratingKey. Plexamp works the same way from the other side: its "Top Albums, 11 plays"
is eleven *track* plays rolled up. There is no album-level play to find on either side of the
API.

### 3.8 Similar artists, which is where radio comes from

```
GET /library/metadata/{artistRatingKey}/similar
```

Returns the artists Plex considers similar. **This is the only sonic endpoint on this server
that returns anything**, and finding that out took four attempts, so the measurements are
worth writing down. On James's library, 12 August 2026, seeded from a real played track and
its album and its artist:

| Request | Result |
|---|---|
| `/library/metadata/{track}/nearest` | 200, empty |
| `/library/metadata/{track}/nearest?type=10` | 200, empty |
| `/library/metadata/{album}/nearest` | 200, empty |
| `/library/metadata/{artist}/nearest` | 200, empty |
| `/library/metadata/{track}/similar` | 404 |
| `/library/metadata/{track}/station/8` | 404 |
| `/library/metadata/{artist}/station/{1,8}` | 404 |
| `/library/sections/{id}/stations` | 404 |
| `/library/sections/{id}/stations/{1,2,3,8}` | 404 |
| **`/library/metadata/{artist}/similar`** | **5 rows** |

**Radio is therefore per artist.** Plexamp agrees from the other side: it greys its own sonic
radio out on a song and offers it on an artist. Everywhere Plexify offers radio it resolves to
an artist first — an album through who made it, a track and Now Playing through their album.

Filtered on each row's declared `type` rather than by asking for one, for the reason section
3.3 and section 3.7 both give: Plex drops parameters it does not implement rather than
rejecting them, so a filter that did nothing would be invisible.

**The tracks are not fetched from Plex.** The endpoint names artists; Plexify reads their
tracks out of the local cache, which is one query against a fully synced library instead of
six round trips, and means a station starts instantly and works offline.

#### Two traps this section exists to record

**A full Stations hub does not mean sonic analysis has run.** `music.stations` (section 3.6)
publishes "Library Radio", "Deep Cuts Radio", "Time Travel Radio" and "Random Album Radio" —
everything, rarely played, by era, by album. All rule-based, none needing a fingerprint.
Reading that hub as proof of analysis is what sent three rounds of work looking for a fault in
the request rather than in the data.

**The station keys those rows carry cannot be fetched.** They look like ordinary paths
(`/library/sections/3/stations/1`) and every one of them 404s on a direct GET, so they are
play-queue source URIs rather than endpoints. Playing Plex's own stations would need
`POST /playQueues`, which this app does not do.

Empty and 404 are both returned as an empty list rather than thrown. A server without the
endpoint and a library with no similarity data are ordinary states, not faults.

---

## 4. Artwork

```
GET /photo/:/transcode?width=300&height=300&minSize=1&upscale=1&url={thumb}&X-Plex-Token=...
```

A `thumb` path is not directly fetchable. It must go through the photo transcoder, which also
lets you ask for a sensible size instead of pulling full-resolution art into a list cell.

> **`url` must be the *relative* thumb path, and this is not cosmetic.** It was once absolute
> (`{baseUrl}{thumb}`), which asks the server to fetch the image *from itself over whatever
> address this client happens to be using*. On the LAN that is harmless. Off it, the server is
> told to reach its own public address, needing hairpin NAT, or its plex.tv relay address,
> which it has no business dialling. Either way the transcoder fails, and it fails identically
> every time — so artwork for anything synced while away never appeared, and never appeared
> later either, which is what distinguishes it from a flaky network.
>
> A relative path is resolved inside the server with no network hop, which is what Plex's own
> clients send.

Cache keys are `(thumb, size)` and never the URL, so a token refresh or a change of server
address is still a cache hit.

---

## 5. Playback: two entirely separate concerns

Direct play and transcoding are different endpoints with different properties. Deciding
between them is `QualityPolicy`; this section is only what each one *is*.

### 5.1 Direct play: stream the original bytes

```
GET {baseUrl}{part.key}?X-Plex-Token=...
```

`part.key` comes from the track's `Media[0].Part[0].key`, e.g.
`/library/parts/159878/1786250673/file.mp3`. Both levels are lists and either can be missing.

This is a plain static file. It seeks with byte ranges, it reports a length, it caches, and
ExoPlayer and libmpv both handle FLAC and ALAC natively. Prefer it whenever bandwidth allows.

The token is in the query string because this URL is handed to the audio engine, which does
its own HTTP and carries none of our headers.

### 5.2 Transcoding: ask the server to re-encode

```
GET /music/:/transcode/universal/start.mp3
      ?path=/library/metadata/{ratingKey}
      &mediaIndex=0&partIndex=0
      &offset={seconds}
      &directPlay=0&directStream=0
      &protocol=http
      &session={stable id}
      &X-Plex-Client-Identifier=...&X-Plex-Token=...
      + the X-Plex-* identity, in the query string
```

Measured by `TranscodeProbe` on 5 August 2026, and every clause below is a finding:

**`start.mp3`, not `start.m3u8`.** Both forms exist and both play. `LockCachingAudioSource`
caches progressive HTTP only, so choosing HLS would mean transcoded playback could never be
cached — precisely the listening, cellular and remote, that most needs it.

**`directPlay=0` and `directStream=0` are required to force an actual transcode.** Without
them Plex is free to decide the original is fine and hand back the source file, so a bitrate
cap can appear to work while doing nothing.

**The identity must be in the query string.** The audio engine sends no headers, and the
endpoint needs to know what the client is before it will form a decision.

**`session` must be stable for the life of one playback.** A new value mid-track starts a
second transcode and abandons the first.

**There is no bitrate control. This is a measurement, not an omission.** Three documented
mechanisms were tried — `musicBitrate`, `maxAudioBitrate`, and a limitation inside
`X-Plex-Client-Profile-Extra` — and all three returned the natural rate byte for byte. So the
only lever that exists is *whether* transcoding happens, which is why `QualityDecision` is
binary and why a separate "data saver" setting would be a second name for the same switch.

**A transcode declares no length and answers 200 to a ranged request**, offering the whole
stream from the start. There is nothing for the player to seek *within*: the only handle on
the middle of a transcode is `offset=`, which means reloading the source. `PlaybackHandler`
holds that difference.

**Always stop the session when playback ends:**

```
GET /music/:/transcode/universal/stop?session={id}
```

Abandoned sessions do not stop promptly on their own. The server keeps transcoding into a
buffer nobody is reading, and several at once is the difference between an idle NAS and a
pegged one.

---

## 6. Writing back: ratings, timeline, scrobble

### 6.1 Ratings

```
PUT /:/rate?identifier=com.plexapp.plugins.library&key={ratingKey}&rating={0-10}
```

One endpoint for artists, albums and tracks. The scale is **0 to 10**, where 10 is five stars,
and Plex permits half-star values, so ratings set by other clients may be odd numbers and must
not be discarded.

> **`-1` removes a rating. `0` does not.** Zero stores an explicit zero-star rating, which is a
> different state and still matches rating filters. `PlexRating.clear` is `-1`.

There is no separate "favourite" concept for music. A favourite is an item rated four stars or
better, which is `userRating >= 8`.

Ratings are written locally first so the star fills instantly, then pushed; the caller reverts
on failure. A rating that only appears after a round trip feels broken, and it is a gesture
people repeat quickly.

### 6.2 Timeline

```
GET /:/timeline?identifier=com.plexapp.plugins.library
      &ratingKey={key}
      &key=/library/metadata/{key}
      &state={playing|paused|stopped}
      &time={ms}&duration={ms}
```

> **Both `ratingKey` and the full `key` path are required.** Sending only one gets a 200 that
> quietly does nothing.

This is what puts Plexify in the server's Now Playing list and what keeps `viewOffset` current
so a track abandoned halfway can be resumed from any client. Plex expects these every few
seconds during playback and treats their absence as the session having ended. `TimelineReporter`
sends one every 10 seconds and on every state change.

### 6.3 Scrobble

```
GET /:/scrobble?identifier=com.plexapp.plugins.library&key={ratingKey}
```

Sent once past 90% of a track. **Plex does not derive a play from timeline events** — a track
can be reported to the very end without ever counting as listened to — so this is a separate
call and skipping it means the play is never recorded and cannot be recovered later.

Note what this means for §3.7: the scrobble names the *track*. The server never learns which
album or playlist it came from.

### 6.4 Asking for a scan

```
GET /library/sections/{key}/refresh
```

Returns as soon as the scan is queued, not when it finishes; results arrive later over the
notification socket or on the next poll. The body is empty on success, so this deliberately
does not go through the `MediaContainer` parser.

---

## 7. Push notifications

```
wss://{host}/:/websockets/notifications?X-Plex-Token=...
```

`ws://` when the connection is plain HTTP. **The token goes in the query string as well as the
headers**, because websocket handshake headers are not carried reliably on every platform, and
this is what Plex's own clients do.

Frames are JSON. Modern servers wrap everything in `NotificationContainer`; older ones send the
payload bare, so fall back to the root rather than dropping the frame.

Only `type == "timeline"` frames concern the library. Within them, `TimelineEntry[]`:

| Field | Meaning |
|---|---|
| `identifier` | other plugins share this socket; only `com.plexapp.plugins.library` matters |
| `itemID` | the ratingKey. `"0"` is noise and must be skipped |
| `state` | **5 means the scan of that item is complete. 9 means deleted.** Anything else is an intermediate step and should be ignored, or you fetch an item Plex has not finished writing |
| `metadataState` | `"deleted"` is the other way a deletion arrives |
| `type` | metadata type number |
| `sectionID` | which library |

The frame carries no metadata, only an id and a type, so applying a change means fetching
`/library/metadata/{itemID}` afterwards.

Parsing is pure and total: anything unrecognised yields an empty list rather than throwing.
This is a long-lived connection carrying several unrelated plugins' traffic, and one
unexpected frame must not take the socket down.

---

## 8. Things that are true of everything here

**401 means the token is bad.** Treat it as "sign in again", not as a transient failure.

**Anything user-facing that can fail must degrade, not error.** Search, hubs, genres and
history all return empty rather than throwing, because a Home row showing an error is worse
than a Home row that is not there. The corollary is that those methods are *useless for
diagnosis*, which is why `playHistoryRaw` exists alongside `playHistory` and does not swallow.
If you add an endpoint on a rendering path, add both.

**Every HTTP client needs a request timeout.** A server that is simply not there — wrong
address, asleep, off the LAN — accepts nothing and says nothing, and `package:http` waits for
ever. This has been found three separate times in this codebase. Wrap the client once rather
than applying a timeout per call, so the next endpoint is covered by construction.

**The cache is additive and never authoritative about absence.** Reads may consult drift to
answer *faster*, but absence from it must never be the reason something appears missing. The
one place that deliberately breaks this is deletion reconcile, which is why it needs the
strongest guard in the codebase.
