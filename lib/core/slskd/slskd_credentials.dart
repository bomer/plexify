import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The slskd API key, in the platform's keystore.
///
/// **Not in `AppSettings`, and the split is the same one qBittorrent uses.**
/// The server address is a preference and lives with the other preferences; the
/// key is a secret and goes where the Plex token goes, Android Keystore and
/// Windows DPAPI. `shared_preferences` is a plaintext file on both platforms.
///
/// Unlike qBittorrent there is a real choice here, and this is the better half
/// of it. The WebUI API has no key mechanism at all, so a username and password
/// is the only thing that exists to store. slskd does, so the app never holds
/// the Soulseek account password, and a leaked key can be revoked by deleting
/// one line from slskd.yml without changing the account it belongs to.
class SlskdCredentials {
  SlskdCredentials({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _apiKeyKey = 'slskd_api_key';

  Future<String?> read() => _storage.read(key: _apiKeyKey);

  Future<void> save(String apiKey) =>
      _storage.write(key: _apiKeyKey, value: apiKey);

  Future<void> clear() => _storage.delete(key: _apiKeyKey);
}
