import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The qBittorrent username and password, in the platform's keystore.
///
/// **Not in [AppSettings], and the split is deliberate.** The server address is
/// a preference and lives with the other preferences; the credentials are a
/// secret and go where the Plex token goes — Android Keystore, Windows DPAPI —
/// for the same reason. `shared_preferences` is a plaintext file on both
/// platforms, and qBittorrent's login sends the password in a form body, so
/// these are worth protecting at rest even though they are not worth protecting
/// in flight beyond HTTPS.
///
/// There is nothing to store *instead*: the WebUI API v2 documents cookie/SID
/// auth only and has no API-key mechanism, so a long-lived credential is the
/// only thing that exists to keep.
class QbitCredentials {
  QbitCredentials({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _usernameKey = 'qbit_username';
  static const _passwordKey = 'qbit_password';

  /// Both halves, or nulls. Read together because a client needs both and
  /// having one is the same as having neither.
  Future<({String? username, String? password})> read() async {
    return (
      username: await _storage.read(key: _usernameKey),
      password: await _storage.read(key: _passwordKey),
    );
  }

  Future<void> save({
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
