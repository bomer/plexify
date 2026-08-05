import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the user has chosen, as one immutable value.
///
/// One object rather than a provider per setting, so a screen that shows six
/// controls rebuilds once and the persisted shape is visible in a single place.
///
/// **Adding a setting is three edits and no more:** a field here, a key in
/// [SettingsStore], and a setter on [SettingsController]. That is deliberate —
/// the tasks that follow this one (quality policy, cache sizes, data saver)
/// each add settings, and none of them should have to think about persistence.
@immutable
class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.dark});

  /// Dark by default, because the app is designed dark-first and following the
  /// system would put most users in a theme that was never the intent.
  final ThemeMode themeMode;

  AppSettings copyWith({ThemeMode? themeMode}) =>
      AppSettings(themeMode: themeMode ?? this.themeMode);

  @override
  bool operator ==(Object other) =>
      other is AppSettings && other.themeMode == themeMode;

  @override
  int get hashCode => themeMode.hashCode;
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

  AppSettings read() => AppSettings(themeMode: _themeMode());

  Future<void> write(AppSettings settings) async {
    await _prefs.setString(_themeModeKey, settings.themeMode.name);
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

  void _apply(AppSettings next) {
    if (next == state) return;
    state = next;
    // Not awaited: the UI has already changed, and a preference that lands a
    // few milliseconds later is not something anyone can observe.
    unawaited(ref.read(settingsStoreProvider).write(next));
  }
}
