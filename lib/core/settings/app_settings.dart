import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

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
  }) => AppSettings(
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
      other.artworkCacheMaxBytes == artworkCacheMaxBytes;

  @override
  int get hashCode => Object.hash(
    themeMode,
    preferredServerId,
    qualityUnmetered,
    qualityMetered,
    audioCacheMaxBytes,
    artworkCacheMaxBytes,
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

  AppSettings read() => AppSettings(
    themeMode: _themeMode(),
    preferredServerId: _prefs.getString(_preferredServerKey),
    qualityUnmetered: _quality(_qualityUnmeteredKey),
    qualityMetered: _quality(_qualityMeteredKey),
    audioCacheMaxBytes: _prefs.getInt(_audioCacheMaxKey),
    artworkCacheMaxBytes: _prefs.getInt(_artworkCacheMaxKey),
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

  void _apply(AppSettings next) {
    if (next == state) return;
    state = next;
    // Not awaited: the UI has already changed, and a preference that lands a
    // few milliseconds later is not something anyone can observe.
    unawaited(ref.read(settingsStoreProvider).write(next));
  }
}
