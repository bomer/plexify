import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/plex/plex_identity.dart';

/// Guards on the release configuration itself, rather than on any code.
///
/// Everything here reads a file in the repository and asserts something about
/// its contents. That is unusual, and it is deliberate: each of these is a
/// mistake that produces a **build that works perfectly on this machine** and
/// fails somewhere else, or fails for someone else, or leaks. None of them is
/// reachable by exercising the app.
void main() {
  group('release configuration', () {
    test('the version Plex is told matches the version that is built', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\S+)$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match, isNotNull, reason: 'pubspec.yaml has no version:');
      final declared = match!.group(1)!.split('+').first;

      // Two versions live in this repo and neither can read the other:
      // pubspec's drives the Android versionName and the Windows file version,
      // while PlexIdentity's is what goes out in X-Plex-Version and shows on
      // the About screen. Reading pubspec from Dart at runtime needs a plugin,
      // so they are kept in step by hand, and by hand means until someone
      // forgets, at which point the app reports a version that was never
      // released and every bug report cites the wrong build.
      expect(
        PlexIdentity.version,
        declared,
        reason:
            'pubspec.yaml says $declared, PlexIdentity.version says '
            '${PlexIdentity.version}. Bump both.',
      );
    });

    test('the changelog has something to say about this version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*(\S+)$', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!
          .split('+')
          .first;

      final changelog = File('CHANGELOG.md').readAsStringSync();

      // `tool/release.ps1` publishes this section as the release notes and
      // refuses to run without it. Asserting it here means the omission is
      // caught by the ordinary test run rather than at the moment of
      // releasing, when the build has already been made and the impulse is to
      // write two words and move on.
      final heading = RegExp(
        r'^##\s+\[?' + RegExp.escape(version) + r'\]?',
        multiLine: true,
      );

      expect(
        heading.hasMatch(changelog),
        isTrue,
        reason:
            'CHANGELOG.md has no section for $version. Add one before the '
            'release, not during it.',
      );
    });

    test('the signing key and its passwords cannot be committed', () {
      final ignore = File('.gitignore').readAsStringSync();

      // key.properties holds the keystore password in plain text and *.jks is
      // the key itself. Committing either is unrecoverable in the way that
      // matters: the fix is issuing a new key, and a new key cannot upgrade an
      // install signed with the old one.
      expect(ignore, contains('key.properties'));
      expect(ignore, contains('*.jks'));

      // And the mistake has not already been made.
      expect(File('android/key.properties').existsSync(), isFalse);
    });

    test('the release manifest declares INTERNET', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      // Flutter injects this permission into the debug and profile manifests
      // only. Without it here, a release build has no network access at all:
      // it installs, opens, and can never reach Plex. Debug builds hide it
      // completely, which is why it was shipped broken once already.
      expect(manifest, contains('android.permission.INTERNET'));
    });

    test('cleartext is permitted for loopback only', () {
      final config = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();

      // just_audio's caching source serves bytes to the player over a local
      // HTTP server, so loopback has to be exempt or every cached track dies
      // with CleartextNotPermittedException. The tempting wider fix is
      // usesCleartextTraffic on the application, which would also put the
      // X-Plex-Token, which travels in the query string, in plaintext on any
      // network that managed to downgrade the connection.
      expect(config, contains('127.0.0.1'));
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        isNot(contains('usesCleartextTraffic')),
      );
    });
  });
}
