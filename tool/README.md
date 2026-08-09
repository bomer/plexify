# tool/

Build-time scripts. Nothing here runs as part of the app.

| | |
|---|---|
| `make_icons.py` | Regenerates every app icon from one definition. Needs Pillow. |
| `package.ps1` | Builds both release artefacts into `dist/`, and checks them. |
| `release.ps1` | Everything `package.ps1` does, then tags and publishes to GitHub. |
| `make_key.ps1` | Creates the Android upload keystore and writes `key.properties`. |

## Releasing

```powershell
powershell -File tool/release.ps1
```

Builds, tags the commit, and creates a GitHub release with both artefacts
attached. Needs the GitHub CLI: `winget install --id GitHub.cli` then
`gh auth login`.

It stops rather than publishing something wrong, and every check is for a
mistake that is quiet at the time and awkward later:

- **The tree must be clean and HEAD already on `origin/main`.** A release points
  at a tag, so a dirty tree publishes a build matching no commit, and an
  unpushed one publishes a build nobody can get the source for.
- **The tag must not exist.** Re-releasing a version replaces the files under
  anyone who already downloaded them. Bump the version instead.
- **`CHANGELOG.md` must have a section for the version**, and it becomes the
  release notes. `test/packaging_test.dart` asserts the same thing, so the
  omission surfaces during an ordinary test run rather than at the moment of
  releasing.
- Everything `package.ps1` checks, since it runs it.

`0.x` releases are marked as prereleases automatically. `-Draft` publishes
somewhere only you can see it; `-Yes` skips the confirmation prompt.

To build the artefacts without publishing:

```powershell
powershell -File tool/package.ps1
```

Produces `dist/plexify-<version>-android-arm64.apk` and
`dist/plexify-<version>-windows-x64.zip`, and refuses to produce either if the
APK is debug-signed, the APK is over its size budget, or the Windows bundle is
missing one of the DLLs the exe cannot start without.

### Cutting a version

The version lives in two places that cannot read each other, so both move
together:

1. `version:` in `pubspec.yaml` and `PlexIdentity.version` in
   `lib/core/plex/plex_identity.dart`.
2. A new heading in `CHANGELOG.md` for it.

`test/packaging_test.dart` fails on either being missed.

## Signing, and whether you need a key yet

Android requires *a* signature, not a particular one. Gradle falls back to the
debug key when `android/key.properties` is absent, and a debug-signed APK
sideloads and runs exactly like any other, so `tool/release.ps1
-AllowDebugSigning` will publish one.

What it costs is the upgrade path. **Android refuses an update signed with a
different key than the install**, so whichever key ships in the first release is
locked in for everyone who installs it. Moving to a real key later means
uninstalling first, which takes the library cache and the Plex token with it.
The debug keystore is also per-machine: lose `~/.android/debug.keystore` and you
can no longer update your own installs either.

Play Console is a separate question and rejects debug-signed uploads outright.
Play App Signing replaces the *app signing* key with a Google-managed one, which
is genuinely no longer your problem, but the *upload* key still has to be real.
It is low-stakes, though: lose it and you can ask for a reset.

Thirty seconds now against an uninstall for every user later is the trade.

## The Android signing key, once

```powershell
powershell -File tool/make_key.ps1
```

Finds keytool, creates the directory, generates a 4096-bit RSA key, and writes
`android/key.properties`. It asks for a password twice and passes it to keytool
through an environment variable rather than the command line, so it does not
land in the process list or in shell history.

**This replaces a `keytool` command that used to be written out here and could
not work.** It referenced `$env:JAVA_HOME`, which nothing sets outside
`package.ps1`, so it expanded to `\bin\keytool.exe`; and it wrote into
`~\keys`, which keytool will not create. Android Studio ships a JDK, so the
script looks there when `JAVA_HOME` is empty, which on this machine it is.

**Back the keystore up somewhere that is not this repository.** An app can only
be upgraded by a build signed with the same key; lose the file or the password
and every install has to be removed and re-added, taking the library cache and
the Plex token with it. The script refuses to overwrite an existing keystore for
the same reason.

`-validity 10000` is roughly 27 years. Google Play wants a key valid past 2033;
this is a sideloaded personal app, but a key that expires is a key that has to
be replaced, and replacing it costs the same as losing it.

Both `android/key.properties` and `*.jks` are gitignored, and
`test/packaging_test.dart` asserts they stay that way, because the first holds
the keystore password in plain text.

## Icons

```powershell
python tool/make_icons.py
```

Writes the Android mipmaps (legacy, adaptive foreground, and the Android 13
monochrome layer) and the Windows multi-size `.ico`. The generated PNGs are
checked in so the build never needs Python; the generator is checked in so the
next person to change the accent colour has something to edit.
