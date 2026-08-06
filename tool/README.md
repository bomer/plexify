# tool/

Build-time scripts. Nothing here runs as part of the app.

| | |
|---|---|
| `make_icons.py` | Regenerates every app icon from one definition. Needs Pillow. |
| `package.ps1` | Builds both release artefacts into `dist/`, and checks them. |

## Releasing

```powershell
powershell -File tool/package.ps1
```

Produces `dist/plexify-<version>-android-arm64.apk` and
`dist/plexify-<version>-windows-x64.zip`, and refuses to produce either if the
APK is debug-signed, the APK is over its size budget, or the Windows bundle is
missing one of the DLLs the exe cannot start without. The version comes from
`pubspec.yaml`; bump it there.

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
