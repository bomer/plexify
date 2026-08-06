import '../db/normalise.dart';
import 'catalog_models.dart';
import 'catalog_store.dart';
import 'musicbrainz_client.dart';

/// The catalog, cache first.
///
/// Sits between [MusicBrainzClient] and everything that wants to know what
/// records exist. The client paces requests and the store remembers answers;
/// this decides when to ask at all, which is the part with judgement in it.
///
/// **Stale beats empty, every time.** Every read here returns whatever the cache
/// holds before deciding whether to refresh, and a refresh that fails leaves the
/// stale answer in place. A discography that blanked for a second on every visit
/// while a rate-limited request was paced would be worse than one that is
/// occasionally a week out of date — and this is the *lower* tier of the app,
/// which must never be able to make the library feel slower.
class CatalogService {
  CatalogService({
    required MusicBrainzClient client,
    required CatalogStore store,
  }) : _client = client,
       _store = store;

  final MusicBrainzClient _client;
  final CatalogStore _store;

  /// Release groups matching a free-text query.
  Future<List<CatalogRelease>> search(String query) async {
    final key = CatalogStore.searchKey(query);
    final cached = await _store.answerFor(key);
    if (cached != null && cached.fresh) return cached.releases;

    final fresh = await _client.searchReleaseGroups(query);
    if (fresh.isEmpty) {
      // An empty result from the network is ambiguous: nothing matched, or the
      // request failed and the client swallowed it. Anything already cached is
      // the better answer either way, and *not* saving the empty one is what
      // stops a single 503 poisoning the cache for a week.
      if (cached != null) return cached.releases;
      if (_client.lastError != null) return const [];
    }

    await _store.saveAnswer(key, fresh);
    return fresh;
  }

  /// Everything an artist has released.
  ///
  /// [libraryName] is the name as the library spells it, which is the only
  /// thing an artist page has. Resolving it to an id is cached separately from
  /// the discography, because the id never changes and the discography does.
  Future<Discography> discographyFor(String libraryName) async {
    final resolved = await resolveArtist(libraryName);
    if (resolved == null) return const Discography.unknownArtist();

    final key = CatalogStore.artistKey(resolved.mbid);
    final cached = await _store.answerFor(key);
    if (cached != null && cached.fresh) {
      return Discography(
        artistMbid: resolved.mbid,
        artistName: resolved.name,
        releases: cached.releases,
      );
    }

    final fresh = await _client.releaseGroupsForArtist(resolved.mbid);
    if (fresh.isEmpty && cached != null) {
      return Discography(
        artistMbid: resolved.mbid,
        artistName: resolved.name,
        releases: cached.releases,
      );
    }
    if (fresh.isEmpty && _client.lastError != null) {
      return const Discography.unknownArtist();
    }

    await _store.saveAnswer(key, fresh);
    return Discography(
      artistMbid: resolved.mbid,
      artistName: resolved.name,
      releases: fresh,
    );
  }

  /// Turns a library artist name into a MusicBrainz id, or null.
  ///
  /// **A name is not a key, and taking the top hit is a real bug rather than a
  /// rough edge.** Searching "Genesis" returns the band, a Japanese metal group
  /// and several others; "Nirvana" returns the Seattle band and a 1960s British
  /// one that MusicBrainz happens to score higher. Attaching the wrong
  /// discography to an artist page reports fifteen albums as missing that the
  /// artist never made, and offers to download them.
  ///
  /// So: an exact name match wins outright, and without one the top hit is only
  /// accepted at high confidence. Everything else resolves to null and is
  /// *cached* as null, so an artist MusicBrainz does not know is asked about
  /// once rather than on every visit.
  Future<({String mbid, String? name})?> resolveArtist(
    String libraryName,
  ) async {
    final cached = await _store.artistFor(libraryName);
    if (cached != null && cached.fresh) {
      final mbid = cached.mbid;
      return mbid == null ? null : (mbid: mbid, name: cached.name);
    }

    final candidates = await _client.searchArtists(libraryName);
    if (candidates.isEmpty) {
      // Only remembered as "nothing there" when the lookup actually ran. A
      // failed request must not be cached as an absent artist for a week.
      if (_client.lastError == null) await _store.saveArtist(libraryName);
      return cached?.mbid == null
          ? null
          : (mbid: cached!.mbid!, name: cached.name);
    }

    final wanted = normalise(libraryName);
    final exact = candidates.where((c) => normalise(c.name) == wanted);
    final chosen = exact.isNotEmpty
        ? exact.first
        : (candidates.first.score >= _confidentScore ? candidates.first : null);

    await _store.saveArtist(
      libraryName,
      mbid: chosen?.mbid,
      resolvedName: chosen?.name,
    );
    return chosen == null ? null : (mbid: chosen.mbid, name: chosen.name);
  }

  /// MusicBrainz's own 0–100 match score, above which an inexact name is
  /// believed.
  ///
  /// High deliberately. Below this the honest answer is "we do not know which
  /// artist this is", and saying so costs an empty section, while guessing
  /// costs a page of albums attributed to the wrong person.
  static const _confidentScore = 90;
}

/// An artist's records, or the fact that we could not work out who they are.
class Discography {
  const Discography({
    required this.artistMbid,
    required this.artistName,
    required this.releases,
  });

  const Discography.unknownArtist()
    : artistMbid = null,
      artistName = null,
      releases = const [];

  final String? artistMbid;

  /// The name MusicBrainz matched, which may differ from the library's. Shown
  /// when it does, so an obviously wrong match is visible rather than silent.
  final String? artistName;

  final List<CatalogRelease> releases;

  bool get resolved => artistMbid != null;
}
