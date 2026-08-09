# tool/

Build-time scripts. Nothing here runs as part of the app.

| | |
|---|---|
| `make_icons.py` | Regenerates every app icon from one definition. Needs Pillow. |
| `package.ps1` | Builds both release artefacts into `dist/`, and checks them. |
| `release.ps1` | Everything `package.ps1` does, then tags and publishes to GitHub. |

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

## The Android signing key, once

Gradle signs release builds with the debug key when `android/key.properties` is
absent, so `flutter run --release` works on any machine. That is fine for
running and wrong for distributing, which is why `package.ps1` refuses it.

Create the real one yourself. It is a credential, it wants a password only you
know, and **it cannot be reissued**. An Android install can only ever be
upgraded by a build signed with the same key; lose it and the only route
forward is uninstalling and losing the app's data with it. Back the file up
somewhere that is not this repo.

```powershell
& "$env:JAVA_HOME\bin\keytool.exe" -genkeypair -v -keystore "$env:USERPROFILE\keys\plexify-upload.jks" -keyalg RSA -keysize 4096 -validity 10000 -alias plexify
```

Then copy `android/key.properties.example` to `android/key.properties` and fill
in the passwords you chose. Both that file and `*.jks` are gitignored.

`-validity 10000` is roughly 27 years. Google Play wants a key valid past 2033;
this is a sideloaded personal app, but a key that expires is a key that has to
be replaced, and replacing it has the same cost as losing it.

## Icons

```powershell
python tool/make_icons.py
```

Writes the Android mipmaps (legacy, adaptive foreground, and the Android 13
monochrome layer) and the Windows multi-size `.ico`. The generated PNGs are
checked in so the build never needs Python; the generator is checked in so the
next person to change the accent colour has something to edit.
