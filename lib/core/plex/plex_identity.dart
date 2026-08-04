import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identifies this installation to Plex.
///
/// The client identifier must be **stable across restarts**. Plex ties the PIN
/// auth flow and the resulting token to it, so regenerating it would silently
/// invalidate the login and force the user through the link flow again on every
/// launch. It is not a secret — SharedPreferences is the right home for it, not
/// secure storage.
class PlexIdentity {
  PlexIdentity._(this.clientIdentifier, this.deviceName, this.platform);

  /// Builds an identity directly, bypassing SharedPreferences.
  ///
  /// Exists so tests can construct a client without a platform channel — the
  /// alternative is mocking SharedPreferences in every API test, which tests
  /// the mock more than the code.
  @visibleForTesting
  PlexIdentity.forTesting({
    this.clientIdentifier = 'test-client-id',
    this.deviceName = 'test-device',
    this.platform = 'test',
  });

  final String clientIdentifier;
  final String deviceName;
  final String platform;

  static const _prefsKey = 'plex_client_identifier';
  static const product = 'Plexify';
  static const version = '0.1.0';

  static PlexIdentity? _cached;

  /// Loads the stored identifier, generating and persisting one on first run.
  static Future<PlexIdentity> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_prefsKey, id);
    }

    final identity = PlexIdentity._(id, _deviceName(), _platform());
    _cached = identity;
    return identity;
  }

  /// Headers Plex expects on every request, to both plex.tv and a server.
  ///
  /// `Accept: application/json` matters more than it looks — without it Plex
  /// returns XML, and every parser in this app assumes JSON.
  Map<String, String> headers({String? token}) {
    return {
      'Accept': 'application/json',
      'X-Plex-Client-Identifier': clientIdentifier,
      'X-Plex-Product': product,
      'X-Plex-Version': version,
      'X-Plex-Platform': platform,
      'X-Plex-Device': platform,
      'X-Plex-Device-Name': deviceName,
      if (token != null && token.isNotEmpty) 'X-Plex-Token': token,
    };
  }

  static String _platform() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return 'Unknown';
  }

  static String _deviceName() {
    try {
      return Platform.localHostname;
    } on Object {
      // localHostname throws on some sandboxed Android configurations.
      return 'Plexify';
    }
  }
}
