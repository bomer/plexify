import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'plex_identity.dart';

/// A pending PIN, returned by [PlexAuth.createPin].
class PlexPin {
  const PlexPin({required this.id, required this.code});

  final int id;
  final String code;
}

/// Plex authentication via the PIN link flow.
///
/// We never see or handle the user's Plex password. The flow is:
///
///   1. Ask plex.tv for a PIN, tied to our persistent client identifier.
///   2. Send the user to app.plex.tv/auth in their system browser to approve.
///   3. Poll until plex.tv hands back an auth token.
///
/// The token is long-lived and goes straight into secure storage (Android
/// Keystore / Windows DPAPI).
class PlexAuth {
  PlexAuth({
    required PlexIdentity identity,
    http.Client? httpClient,
    FlutterSecureStorage? storage,
  }) : _identity = identity,
       _http = httpClient ?? http.Client(),
       _storage = storage ?? const FlutterSecureStorage();

  final PlexIdentity _identity;
  final http.Client _http;
  final FlutterSecureStorage _storage;

  static const _tokenKey = 'plex_auth_token';
  static const _pinsUrl = 'https://plex.tv/api/v2/pins';

  /// Requests a new PIN.
  ///
  /// `strong=true` asks for a longer code; Plex's short codes are guessable
  /// enough that it recommends against them.
  Future<PlexPin> createPin() async {
    final response = await _http.post(
      Uri.parse('$_pinsUrl?strong=true'),
      headers: _identity.headers(),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw PlexAuthException(
        'Could not request a PIN from Plex (HTTP ${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final id = json['id'];
    final code = json['code'];
    if (id == null || code == null) {
      throw const PlexAuthException('Plex returned a PIN with no id or code');
    }

    return PlexPin(
      id: id is int ? id : int.parse(id.toString()),
      code: code.toString(),
    );
  }

  /// The URL the user must open to approve [pin].
  Uri authorizationUrl(PlexPin pin) {
    // Note the '#?' — these are fragment parameters, not query parameters.
    // Putting them after a plain '?' silently fails to prefill the code.
    final params = {
      'clientID': _identity.clientIdentifier,
      'code': pin.code,
      'context[device][product]': PlexIdentity.product,
      'context[device][deviceName]': _identity.deviceName,
      'context[device][platform]': _identity.platform,
    };
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return Uri.parse('https://app.plex.tv/auth#?$query');
  }

  /// Polls until the user approves the PIN, then returns the auth token.
  ///
  /// Plex expires PINs after about 15 minutes, so [timeout] defaults just under
  /// that — polling a dead PIN forever would look like a hang.
  Future<String> waitForToken(
    PlexPin pin, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 14),
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) {
        throw const PlexAuthException('Sign-in cancelled');
      }

      final token = await checkPin(pin);
      if (token != null) {
        await saveToken(token);
        return token;
      }
      await Future<void>.delayed(interval);
    }

    throw const PlexAuthException(
      'Sign-in timed out. The PIN expired before it was approved.',
    );
  }

  /// One poll. Returns the token once approved, or null while still pending.
  Future<String?> checkPin(PlexPin pin) async {
    final response = await _http.get(
      Uri.parse('$_pinsUrl/${pin.id}'),
      headers: _identity.headers(),
    );

    // 404 means the PIN expired or was consumed — not worth retrying.
    if (response.statusCode == 404) {
      throw const PlexAuthException('This PIN has expired. Please try again.');
    }
    if (response.statusCode != 200) {
      throw PlexAuthException(
        'Plex rejected the PIN check (HTTP ${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final token = json['authToken'];
    if (token == null) return null; // still waiting for approval
    final asString = token.toString();
    return asString.isEmpty ? null : asString;
  }

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> signOut() => _storage.delete(key: _tokenKey);
}

class PlexAuthException implements Exception {
  const PlexAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
