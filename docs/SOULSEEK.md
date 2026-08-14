# Soulseek, through slskd

How this app talks to the Soulseek network, what the API actually gives you, and the parts
that will mislead you. Written the same way as [PLEX-API.md](PLEX-API.md): what is sent, what
comes back, and which assumptions turned out to be wrong.

## Why slskd rather than Soulseek

Soulseek has no official API and no published protocol. What exists is
[SLSKPROTOCOL.md](https://nicotine-plus.org/doc/SLSKPROTOCOL.html), reverse engineered by the
Nicotine+ team over years of work against a proprietary client and server.

Speaking it directly from Dart was considered and rejected. It is a binary TCP protocol
against a central server, plus direct peer connections, a distributed search network and
obfuscated ports, and implementing it would make Plexify itself a Soulseek peer: holding a
connection, serving uploads, and needing to keep doing both from a phone. That is not a music
player.

[slskd](https://github.com/slskd/slskd) is a headless daemon that speaks the protocol and
exposes a REST API. Structurally it is the same arrangement as qBittorrent, a server the user
already runs and this app talks to over HTTP, which is why `lib/core/slskd/` mirrors
`lib/core/qbit/` closely enough to read one after the other.

## Authentication

One header, on every request:

```
X-API-Key: <key>
```

Keys live in `slskd.yml` under `web.authentication.api_keys`, generated with
`openssl rand -base64 48`. **It is a map of named entries, not a string**, and it needs
`role: readwrite`:

```yaml
web:
  authentication:
    api_keys:
      plexify:
        key: <16 to 255 characters>
        role: readwrite
        cidr: 0.0.0.0/0,::/0
```

Two things about this cost an evening the first time. A key pasted in as a bare value leaves
the map empty, so slskd answers 401 while looking configured, and authentication is not
reloaded on the fly, so a correct edit keeps answering 401 until slskd restarts.

The separate singular `apiKey` is a different mechanism, the "primary" key, normally set with
`--api-key` or `SLSKD_API_KEY`, and it takes a tuple like
`role=readwrite;cidr=0.0.0.0/0,::/0;<key>` rather than a bare value.

**Keys configured in YAML default to `readonly`**, which is the nastier half. A readonly key
searches perfectly and fails only on `POST /transfers/downloads`, so it presents an hour later
as a completely different bug.

This is the one place slskd is *simpler* than qBittorrent, and materially so. There is no
session to establish, no cookie to hold, no CSRF check comparing `Referer` against `Host`,
and no ban after repeated failed sign-ins. Roughly three quarters of `QbitClient` exists for
those four things and none of it was carried across.

**401 and 403 mean different things and need different fixes.**

| Status | Meaning | Fix |
|---|---|---|
| 401 | The key is wrong or missing | Check it against `slskd.yml` |
| 403 | The key is right, the *caller's address* is not | Check the key's CIDR list |

Keys can be restricted to a list of CIDRs, and the default covers only the local network.
This is the one worth naming in an error message: the key works perfectly from the machine it
was tested on and fails from the phone, or works everywhere until a reverse proxy starts
presenting its own address to slskd instead of the client's.

## What has actually been measured

Confirmed against a real slskd on 13 August 2026: a search returns responses in the shape
these models parse, the directory grouping finds real albums inside them, the ranking picks
one, and the enqueue is accepted. Everything below is therefore measured rather than read out
of the documentation, except where it says otherwise.

Still unconfirmed at that point: whether a *completed* folder triggers the Plex rescan, which
needs both a transfer to finish and slskd's downloads directory to actually reach the watch
folder. `GET /transfers/downloads` behind the Downloads screen is on the same footing.

## Endpoints, as this app uses them

Base path is `/api/v0`. Default ports are 5030 for HTTP and 5031 for HTTPS.

| Call | Purpose |
|---|---|
| `GET /application` | Version, and whether slskd is logged in to Soulseek |
| `POST /searches` | Start a search. Body carries an `id` this app chooses |
| `GET /searches/{id}` | Poll, until `state` stops containing `InProgress` |
| `GET /searches/{id}/responses` | The results, one entry per user |
| `DELETE /searches/{id}` | Always, in a `finally` |
| `POST /transfers/downloads/{username}` | Queue files. Body is `[{filename, size}]` |
| `GET /transfers/downloads` | Everything arriving, grouped by user then directory |

### The search id has to be a GUID

Measured, not documented. `POST /searches` takes an `id`, and slskd parses it into a
`Nullable<Guid>`. Anything else is a 400 naming a .NET type:

```
The JSON value could not be converted to System.Nullable`1[System.Guid].
Path: $.id | LineNumber: 0 | BytePositionInLine: 32
```

An id is an id right up until it is not, and this was the first thing the client got wrong
against a real server. `SlskdClient.startSearch` sends a v4 UUID and then prefers whatever id
comes back in the response body over the one it sent.

### Searches are deliberately *not* deleted

`QbitClient.search` deletes its own and is right to: qBittorrent caps how many it keeps, so
leaking them stops searching working after a few dozen attempts.

slskd has no such cap, and its search history is **useful**. It is where you go when this app
has not done what you wanted, and downloading from it by hand is a working fallback. Deleting
it was qBittorrent's reasoning applied without checking that it transferred. The two clients
mirror each other closely enough that this difference would otherwise read as an oversight.

### A search is not finished just because it has not started

States run **`Requested` → `InProgress` → `Completed, …`**, and the first poll lands within
milliseconds of the POST, while the state is still `Requested`.

`SlskdSearch.isComplete` was written as `!state.contains('inprogress')`, which answers *yes* to
`Requested`. The client read an empty response list about fifty milliseconds in and reported
that nobody had the record, while slskd carried on and filled the search in perfectly. It
presented as downloads failing at random, because occasionally the state had already flipped
by the time the poll arrived, and as a search sitting complete in slskd's own web UI that
downloaded fine by hand.

**Ask positively.** A negative check answers "finished" to every state it has never heard of;
a positive one answers "not yet", and the worst that costs is polling until the deadline.

### `Completed, TimedOut` is success

A Soulseek search has no natural end. Peers answer whenever they feel like it and many never
answer at all, so slskd stops waiting after `searchTimeout` and keeps whatever arrived. The
state string it then reports is `Completed, TimedOut`.

Reading that as a failure would discard **every** successful search. `SlskdSearch.isComplete`
therefore asks only whether the state has stopped being `InProgress`, and does not try to
distinguish endings.

## What will mislead you

### Paths use backslashes, whatever the peer is running

Every filename comes back in Windows form:

```
@@abcde\Music\Radiohead\Kid A\01 Everything In Its Right Place.flac
```

This holds regardless of the sharing peer's operating system. Splitting on `/` finds no
separator at all, so every file reports the whole path as its directory, every file becomes
its own group of one, and the ranking scores a hundred imaginary single-track albums instead
of the handful of real ones.

**Nothing throws. Nothing looks wrong.** The search just stops finding records. It has its
own tests in `test/slskd_models_test.dart` for that reason.

### There is no album, anywhere in the protocol

A search response is one *user* with a flat list of whatever of theirs matched. Soulseek
shares files; the idea of a record is entirely this app's inference, made by grouping files
that share a parent directory on one person's machine.

Two consequences follow, and the second is the useful one:

- Ranking works on **directories, not results**, so `torrent_ranking.dart` does not port.
  Seeder count has no analogue at all, and what replaces it is whether a transfer will ever
  start: a free upload slot, and how long the queue is.
- Matching runs against the **whole directory path**, not the last folder. The near-universal
  layout is `...\Radiohead\Kid A\`, with the artist as the parent, so matching the leaf alone
  fails the artist half of essentially every result.

That second choice buys a safety property for free. A peer who keeps every song loose in one
`Music` folder produces a single group of several thousand files whose path names no album,
so it can never match and can never be queued. Queueing it would have pulled somebody's
entire collection in answer to a request for one record.

### Bitrate is real here, and that changes the rules

`torrent_ranking.dart` refuses to rank bitrates and is right to: a number scraped out of a
filename is how a 128k rip labelled "320" wins.

slskd reports `bitRate` per file, from the sharing client rather than from the name, so it is
worth ranking on. It is used only to break ties **within** lossy, never to cross the tier
above FLAC, and it excludes nothing: a 128k rip is still queued automatically when it is the
only confident name match, because not getting the record is the worse outcome. There is no
quality floor and no user-facing bitrate control, which was a deliberate decision rather than
an omission.

### Format is decided by majority, not by presence

`AudioFormat.detect` answers lossless if *any* extension in the set is, so one stray `.wav`
interlude would label an entire MP3 rip as lossless. The folder's majority extension is what
it actually is.

## Two things this app cannot do for you

Both are invisible from inside Plexify, both present as something other than their cause, and
both are stated on the Soulseek settings screen for that reason.

**slskd has one downloads directory and no per-download category.** The entire qBittorrent
integration is `category=Music` routing to the folder Plex watches, and that mechanism does
not exist here. Either point `SLSKD_DOWNLOADS_DIR` at the watch folder, or use slskd's own
`DownloadDirectoryComplete` webhook or script hook to move finished folders there. Until that
is done, downloads succeed and land somewhere Plex never looks.

**Soulseek expects you to share.** Many people configure their queues to refuse anyone
sharing nothing. With `shares.directories` empty, availability quietly collapses to worse
than torrents, with no error anywhere saying why. Pointing slskd at the music library, read
only, is the usual answer.

## Trying it by hand

`slskd.local.example.json` at the repo root documents the shape. Copy it to
`slskd.local.json`, which is gitignored and which `test/packaging_test.dart` asserts is never
tracked, since it holds an API key in plain text. The app itself never reads that file: it
takes the address from Settings and the key from the platform keystore.
