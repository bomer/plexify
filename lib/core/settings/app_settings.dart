import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../acquire/download_source.dart';
import '../audio/quality_policy.dart';

/// Everything the user has chosen, as one immutable value.
///
/// One object rather than a provider per setting, so a screen that shows six
/// controls rebuilds once and the persisted shape is visible in a single place.
///
/// **Adding a setting is three edits and no more:** a field here, a key in
/// [SettingsStore], and a setter on [SettingsController]. That is deliberate,
/// and it has now been paid off twice: the quality overrides and both cache
/// budgets landed without any of them having to think about persistence.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.preferredServerId,
    this.qualityUnmetered,
    this.qualityMetered,
    this.audioCacheMaxBytes,
    this.artworkCacheMaxBytes,
    this.catalogEnabled = false,
    this.autoplayRadio = true,
    this.qbitUrl,
    this.slskdUrl,
    this.downloadSource = DownloadSourceKind.qbittorrent,
    this.volume = 1,
    this.sidebarPlaylists = 12,
  });

  /// How many playlists the sidebar lists directly.
  ///
  /// Twelve rather than the eight it was. The sidebar exists so a playlist is
  /// one click away, and eight was chosen before there was any evidence about
  /// how many people actually keep; a list long enough to scroll past is a
  /// smaller cost than a playlist that is not on it.
  ///
  /// A setting rather than a constant because the right number depends on the
  /// window: the same list that fits comfortably on a desktop pushes the
  /// destinations off a laptop screen.
  final int sidebarPlaylists;

  /// Output level, 0 to 1.
  ///
  /// Persisted because the alternative is a slider that reads full every launch
  /// while the last thing you did was turn it down, and the first track of the
  /// morning is then as loud as the engine can make it.
  ///
  /// **Desktop only, and that is a decision rather than an omission.** On a
  /// phone the hardware keys and the OS mixer already own this, and every
  /// competent player leaves them to it; a second, app-local level to get out
  /// of step with them is a way to have the volume be wrong in a place nobody
  /// thinks to look. The setting is stored on both platforms because it costs
  /// nothing and one number that means the same thing everywhere is simpler
  /// than one that only exists sometimes.
  final double volume;

  /// Whether a finished queue continues into music that sounds like it.
  ///
  /// On by default, because the alternative is silence at the end of every
  /// album and the whole point of a station is that you did not have to ask for
  /// it. Off is for people who put a record on and want it to end.
  ///
  /// Only ever extends a queue that ran to its end on its own. Stopping,
  /// clearing or replacing a queue ends the station with it.
  final bool autoplayRadio;

  /// Whether to look up records the library does not hold.
  ///
  /// Off by default, and off is a real answer rather than a soft launch. It
  /// turns on a third-party lookup on the search path and an extra section on
  /// every artist page, and on a phone that is noise: what you want there is
  /// the music you have. On the desktop, where acquisition actually happens, it
  /// is the point. Settings are per-device, so one switch gives both.
  ///
  /// Gates the catalog tier of search *and* the missing-albums list, because
  /// they are the same question asked from two places, and a build where one
  /// appeared without the other would be harder to explain than either.
  final bool catalogEnabled;

  /// Scheme, host and port of the qBittorrent WebUI — `https://box.local:8080`.
  ///
  /// The address is a preference and lives here; the username and password are
  /// secrets and live in [QbitCredentials], which is the platform keystore. The
  /// split is not decoration: `shared_preferences` is a plaintext file on both
  /// platforms.
  final String? qbitUrl;

  /// Scheme, host and port of slskd, `https://nas.local:5031`.
  ///
  /// Same split as [qbitUrl] for the same reason: the address is a preference,
  /// and the API key is a secret living in `SlskdCredentials`.
  final String? slskdUrl;

  /// Which server downloads things.
  ///
  /// **Only one is consulted, ever.** Searching both and merging was considered
  /// and rejected: they rank on entirely different evidence, so a combined list
  /// would be sorted by a number meaning different things in each half.
  ///
  /// Defaults to qBittorrent so that an existing install does not silently
  /// change where its downloads come from on upgrade.
  final DownloadSourceKind downloadSource;

  /// Dark by default, because the app is designed dark-first and following the
  /// system would put most users in a theme that was never the intent.
  final ThemeMode themeMode;

  /// Forces direct play or transcode on wifi and ethernet. Null decides
  /// automatically, which is the default and almost always right.
  final QualityDecision? qualityUnmetered;

  /// The same for mobile data.
  ///
  /// **This is the data-saver control**, under its honest name. #8 established
  /// that Plex's music transcoder ignores every documented way of asking for a
  /// lower bitrate, so there is no quality ladder to descend: the only lever is
  /// whether transcoding happens, and forcing it on mobile data is exactly what
  /// a "data saver" switch would have done. A second toggle spelling the same
  /// setting differently would be worse than not having one.
  final QualityDecision? qualityMetered;

  /// Bytes the audio cache may hold, or null for the platform default.
  ///
  /// Null rather than a number so the default follows the platform, which
  /// differs by an order of magnitude between a phone and a desktop.
  final int? audioCacheMaxBytes;

  /// Bytes the artwork cache may hold, or null for the platform default.
  final int? artworkCacheMaxBytes;

  /// The `clientIdentifier` of the server the user picked, or null to take
  /// whichever answers first.
  ///
  /// Null is the normal state and the original behaviour. It is only set by
  /// choosing a server explicitly, and once set it is binding — see
  /// `connectServerProvider` for why falling back to a different server would
  /// be worse than not connecting at all.
  final String? preferredServerId;

  /// The override that applies to the connection this device is on right now.
  ///
  /// Lives here rather than in [QualityPolicy] because it is a preference, not
  /// a policy: the policy decides what is *sensible*, this says what the user
  /// asked for instead.
  QualityDecision? qualityOverrideFor({required bool unmetered}) =>
      unmetered ? qualityUnmetered : qualityMetered;

  /// Every nullable field here is meaningfully null, which `??` cannot express,
  /// hence the sentinels. Null means "let any server answer", "decide quality
  /// automatically" and "use the platform's default budget" respectively, and a
  /// copyWith that could not restore those would make them unreachable once
  /// set.
  AppSettings copyWith({
    ThemeMode? themeMode,
    Object? preferredServerId = _unchanged,
    Object? qualityUnmetered = _unchanged,
    Object? qualityMetered = _unchanged,
    Object? audioCacheMaxBytes = _unchanged,
    Object? artworkCacheMaxBytes = _unchanged,
    bool? catalogEnabled,
    bool? autoplayRadio,
    Object? qbitUrl = _unchanged,
    Object? slskdUrl = _unchanged,
    DownloadSourceKind? downloadSource,
    double? volume,
    int? sidebarPlaylists,
  }) => AppSettings(
    volume: volume ?? this.volume,
    sidebarPlaylists: sidebarPlaylists ?? this.sidebarPlaylists,
    catalogEnabled: catalogEnabled ?? this.catalogEnabled,
    autoplayRadio: autoplayRadio ?? this.autoplayRadio,
    qbitUrl: identical(qbitUrl, _unchanged) ? this.qbitUrl : qbitUrl as String?,
    slskdUrl: identical(slskdUrl, _unchanged)
        ? this.slskdUrl
        : slskdUrl as String?,
    downloadSource: downloadSource ?? this.downloadSource,
    themeMode: themeMode ?? this.themeMode,
    preferredServerId: identical(preferredServerId, _unchanged)
        ? this.preferredServerId
        : preferredServerId as String?,
    qualityUnmetered: identical(qualityUnmetered, _unchanged)
        ? this.qualityUnmetered
        : qualityUnmetered as QualityDecision?,
    qualityMetered: identical(qualityMetered, _unchanged)
        ? this.qualityMetered
        : qualityMetered as QualityDecision?,
    audioCacheMaxBytes: identical(audioCacheMaxBytes, _unchanged)
        ? this.audioCacheMaxBytes
        : audioCacheMaxBytes as int?,
    artworkCacheMaxBytes: identical(artworkCacheMaxBytes, _unchanged)
        ? this.artworkCacheMaxBytes
        : artworkCacheMaxBytes as int?,
  );

  static const _unchanged = Object();

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.preferredServerId == preferredServerId &&
      other.qualityUnmetered == qualityUnmetered &&
      other.qualityMetered == qualityMetered &&
      other.audioCacheMaxBytes == audioCacheMaxBytes &&
      other.artworkCacheMaxBytes == artworkCacheMaxBytes &&
      other.catalogEnabled == catalogEnabled &&
      other.autoplayRadio == autoplayRadio &&
      other.qbitUrl == qbitUrl &&
      other.slskdUrl == slskdUrl &&
      other.downloadSource == downloadSource &&
      other.volume == volume &&
      other.sidebarPlaylists == sidebarPlaylists;

  @override
  int get hashCode => Object.hash(
    themeMode,
    preferredServerId,
    qualityUnmetered,
    qualityMetered,
    audioCacheMaxBytes,
    artworkCacheMaxBytes,
    catalogEnabled,
    autoplayRadio,
    qbitUrl,
    slskdUrl,
    downloadSource,
    volume,
    sidebarPlaylists,
  );
}

/// Reads and writes [AppSettings].
///
/// Settings are read synchronously so the first frame is already correct —
/// loading them asynchronously would paint the default theme and then swap,
/// which is visible as a flash on every cold start. The async part happens once
/// in `main()`, alongside the other startup loads.
class SettingsStore {
  @visibleForTesting
  const SettingsStore(this._prefs);

  static Future<SettingsStore> load() async =>
      SettingsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _themeModeKey = 'settings_theme_mode';
  static const _preferredServerKey = 'settings_preferred_server';
  static const _qualityUnmeteredKey = 'settings_quality_unmetered';
  static const _qualityMeteredKey = 'settings_quality_metered';
  static const _audioCacheMaxKey = 'settings_audio_cache_max_bytes';
  static const _artworkCacheMaxKey = 'settings_artwork_cache_max_bytes';
  static const _catalogEnabledKey = 'settings_catalog_enabled';
  static const _autoplayRadioKey = 'settings_autoplay_radio';
  static const _qbitUrlKey = 'settings_qbit_url';
  static const _slskdUrlKey = 'settings_slskd_url';
  static const _downloadSourceKey = 'settings_download_source';
  static const _volumeKey = 'settings_volume';
  static const _sidebarPlaylistsKey = 'settings_sidebar_playlists';

  AppSettings read() => AppSettings(
    catalogEnabled:
        _prefs.getBool(_catalogEnabledKey) ??
        const AppSettings().catalogEnabled,
    autoplayRadio:
        _prefs.getBool(_autoplayRadioKey) ?? const AppSettings().autoplayRadio,
    qbitUrl: _prefs.getString(_qbitUrlKey),
    slskdUrl: _prefs.getString(_slskdUrlKey),
    // By name rather than by index, so reordering the enum cannot silently
    // change which source an existing install downloads from.
    downloadSource: DownloadSourceKind.byName(
      _prefs.getString(_downloadSourceKey),
    ),
    themeMode: _themeMode(),
    preferredServerId: _prefs.getString(_preferredServerKey),
    qualityUnmetered: _quality(_qualityUnmeteredKey),
    qualityMetered: _quality(_qualityMeteredKey),
    audioCacheMaxBytes: _prefs.getInt(_audioCacheMaxKey),
    artworkCacheMaxBytes: _prefs.getInt(_artworkCacheMaxKey),
    // Clamped on the way in as well as on the way out. This file is plain text
    // on both platforms, and a hand-edited 40 would be a very loud surprise.
    volume: (_prefs.getDouble(_volumeKey) ?? const AppSettings().volume).clamp(
      0.0,
      1.0,
    ),
    sidebarPlaylists:
        _prefs.getInt(_sidebarPlaylistsKey) ??
        const AppSettings().sidebarPlaylists,
  );

  Future<void> write(AppSettings settings) async {
    await _prefs.setString(_themeModeKey, settings.themeMode.name);
    // Removed rather than stored empty or as a sentinel, so every "no
    // preference" reads back as null on the next launch instead of as a server
    // whose identifier is '', a quality decision nobody chose, or a cache
    // budget of zero.
    await _write(_preferredServerKey, settings.preferredServerId);
    await _write(_qualityUnmeteredKey, settings.qualityUnmetered?.name);
    await _write(_qualityMeteredKey, settings.qualityMetered?.name);
    await _writeInt(_audioCacheMaxKey, settings.audioCacheMaxBytes);
    await _writeInt(_artworkCacheMaxKey, settings.artworkCacheMaxBytes);
    await _prefs.setBool(_catalogEnabledKey, settings.catalogEnabled);
    await _prefs.setBool(_autoplayRadioKey, settings.autoplayRadio);
    await _write(_qbitUrlKey, settings.qbitUrl);
    await _write(_slskdUrlKey, settings.slskdUrl);
    await _prefs.setString(_downloadSourceKey, settings.downloadSource.name);
    await _prefs.setDouble(_volumeKey, settings.volume);
    await _prefs.setInt(_sidebarPlaylistsKey, settings.sidebarPlaylists);
  }

  Future<void> _write(String key, String? value) async =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);

  Future<void> _writeInt(String key, int? value) async =>
      value == null ? _prefs.remove(key) : _prefs.setInt(key, value);

  /// Stored by name, like the theme mode and for the same reason: an enum's
  /// declaration order is not ours to rely on.
  QualityDecision? _quality(String key) {
    final stored = _prefs.getString(key);
    for (final decision in QualityDecision.values) {
      if (decision.name == stored) return decision;
    }
    return null;
  }

  /// Stored by name rather than by index.
  ///
  /// [ThemeMode]'s declaration order is not ours to rely on, and an index that
  /// shifted under an SDK upgrade would silently change everyone's theme.
  ThemeMode _themeMode() {
    final stored = _prefs.getString(_themeModeKey);
    for (final mode in ThemeMode.values) {
      if (mode.name == stored) return mode;
    }
    return const AppSettings().themeMode;
  }
}

/// The loaded store. Overridden in `main()`, like the identity and the audio
/// handler, because it is only available after an await.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) =>
      throw StateError('settingsStoreProvider must be overridden in main()'),
);

/// The current settings, and the only way to change them.
final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Changes settings and persists them.
///
/// Every mutation goes through [_apply], so there is exactly one place that
/// writes to disk. A setter that updated the state and forgot to persist would
/// work perfectly until the next launch, which is the hardest kind of bug to
/// notice and the easiest kind to introduce one call site at a time.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsStoreProvider).read();

  void setThemeMode(ThemeMode mode) => _apply(state.copyWith(themeMode: mode));

  /// Binds the app to one server, or releases it with null.
  ///
  /// Changing this re-resolves the connection on its own — `connectServerProvider`
  /// watches it — so callers do not invalidate anything themselves.
  void setPreferredServer(String? clientIdentifier) =>
      _apply(state.copyWith(preferredServerId: clientIdentifier));

  /// Null restores automatic. Takes effect on the next queue that is built,
  /// never on the one already playing — see [QualityPolicy.decide].
  void setQualityUnmetered(QualityDecision? decision) =>
      _apply(state.copyWith(qualityUnmetered: decision));

  void setQualityMetered(QualityDecision? decision) =>
      _apply(state.copyWith(qualityMetered: decision));

  /// Null restores the platform default. The live cache picks this up through
  /// `audioCacheProvider`, which listens rather than rebuilding.
  void setAudioCacheMaxBytes(int? bytes) =>
      _apply(state.copyWith(audioCacheMaxBytes: bytes));

  void setArtworkCacheMaxBytes(int? bytes) =>
      _apply(state.copyWith(artworkCacheMaxBytes: bytes));

  /// Turns the catalog tier of search and the missing-albums list on or off
  /// together. See [AppSettings.catalogEnabled] for why they share a switch.
  void setCatalogEnabled(bool enabled) =>
      _apply(state.copyWith(catalogEnabled: enabled));

  void setAutoplayRadio(bool enabled) =>
      _apply(state.copyWith(autoplayRadio: enabled));

  /// Sets the qBittorrent address, or clears it with null.
  ///
  /// Trailing slashes are removed here rather than at the call site: they make
  /// every request path double-slashed, which breaks qBittorrent's CSRF check
  /// specifically — the `Referer` stops matching — and produces a 403 that
  /// reads as a wrong password.
  void setQbitUrl(String? url) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _apply(state.copyWith(qbitUrl: null));
      return;
    }
    var cleaned = trimmed;
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    _apply(state.copyWith(qbitUrl: cleaned));
  }

  /// Sets the slskd address, or clears it with null.
  ///
  /// Trailing slashes are removed for a related but different reason to
  /// qBittorrent's: slskd itself tolerates a doubled slash, but a reverse proxy
  /// in front of it very often does not, and the resulting 404 names nothing
  /// useful.
  void setSlskdUrl(String? url) =>
      _apply(state.copyWith(slskdUrl: _cleanUrl(url)));

  /// Chooses which server downloads things. Only the chosen one is ever asked.
  void setDownloadSource(DownloadSourceKind source) =>
      _apply(state.copyWith(downloadSource: source));

  static String? _cleanUrl(String? url) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    var cleaned = trimmed;
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  /// Sets the output level, 0 to 1.
  ///
  /// Clamped rather than asserted: this is driven by a slider whose bounds are
  /// set elsewhere, and a rounding error at the end of a drag should not be
  /// able to hand the engine a number outside its range.
  void setVolume(double volume) =>
      _apply(state.copyWith(volume: volume.clamp(0.0, 1.0)));

  /// How many playlists the sidebar lists.
  ///
  /// Clamped to something a sidebar can hold. Zero is allowed and means the
  /// section disappears, which is a reasonable thing to want; the upper bound
  /// exists because past a certain length the list stops being a shortcut and
  /// becomes the Playlists screen with worse scrolling.
  void setSidebarPlaylists(int count) =>
      _apply(state.copyWith(sidebarPlaylists: count.clamp(0, 30)));

  void _apply(AppSettings next) {
    if (next == state) return;
    state = next;
    // Not awaited: the UI has already changed, and a preference that lands a
    // few milliseconds later is not something anyone can observe.
    unawaited(ref.read(settingsStoreProvider).write(next));
  }
}
