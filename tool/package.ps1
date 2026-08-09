<#
.SYNOPSIS
    Build Plexify's release artefacts and check them before they leave.

.DESCRIPTION
    Produces, under dist/:

      plexify-<version>-android-arm64.apk
      plexify-<version>-windows-x64.zip

    and refuses to produce either if something is wrong with it. The checks are
    the point of the script; `flutter build` on its own is one command.

      * The APK must be signed with the real upload key, unless
        -AllowDebugSigning says otherwise. Gradle falls back to the debug key
        so `flutter run --release` works without a keystore, and a debug-signed
        APK installs perfectly; the failure only shows up later, when a
        properly signed build will not upgrade it.

      * The APK must be under the size budget. This is a lightweightness
        regression guard: being smaller than Plexamp is a reason this project
        exists, and a dependency that quietly adds ten megabytes should be a
        decision rather than a discovery.

      * The Windows zip must contain the whole runner directory. plexify.exe is
        about 150KB and will not start without its sibling DLLs and data/;
        shipping the exe alone is an easy and completely silent mistake.

.PARAMETER AllowDebugSigning
    Build the APK with Gradle's debug-key fallback instead of refusing.

    Sideloading does not care: Android wants a signature, not a particular one,
    and a debug-signed APK installs and runs. What it costs is the upgrade
    path. Android refuses an update signed with a different key than the
    install, so whatever key ships first is locked in, and moving to a real one
    later means every user uninstalling and losing the library cache and their
    Plex token with it. The debug keystore is also per-machine, so losing it
    ends your ability to update your own installs.

    Play Console is a separate matter and rejects debug-signed uploads outright,
    Play App Signing or not: that replaces the *app signing* key, not the upload
    key.

.PARAMETER SkipAndroid
    Build Windows only.

.PARAMETER SkipWindows
    Build Android only.

.EXAMPLE
    powershell -File tool/package.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$AllowDebugSigning
)

$ErrorActionPreference = 'Stop'

# The arm64 APK was 22.1MB when this budget was set, against the ~20MB the plan
# expected. The gap is libmpv and the Flutter engine, both already accounted
# for. Raise this deliberately, with a note saying what earned the space.
$ApkBudgetMb = 25

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$env:PATH = "C:\Users\James\flutter-sdk\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"

# ---------------------------------------------------------------- version ----

$pubspec = Get-Content pubspec.yaml -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\S+)\s*$') {
    throw "Could not read 'version:' from pubspec.yaml"
}
$version = $Matches[1]
$versionName = $version.Split('+')[0]
Write-Host "Packaging Plexify $version" -ForegroundColor Cyan

$dist = Join-Path $repo 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# ---------------------------------------------------------------- android ----

if (-not $SkipAndroid) {
    if (-not (Test-Path 'android/key.properties') -and -not $AllowDebugSigning) {
        throw @"
android/key.properties is missing, so this build would be signed with the debug
key. Copy android/key.properties.example and fill it in. See tool/README.md
for the keytool command that creates the keystore.

If you meant to ship a debug-signed build, pass -AllowDebugSigning. Sideloading
works fine that way; what it costs is that a later switch to a real key means
every install has to be removed and re-added, cache and Plex token with it.
"@
    }

    Write-Host "`nBuilding Android (arm64)..." -ForegroundColor Cyan
    flutter build apk --release --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }

    $apk = 'build/app/outputs/flutter-apk/app-release.apk'
    if (-not (Test-Path $apk)) { throw "Expected $apk to exist" }

    # apksigner, not keytool. At minSdk 24+ Gradle signs with the v2/v3 APK
    # schemes and leaves v1 JAR signing off, so `keytool -printcert -jarfile`
    # answers "Not a signed jar file" for a perfectly well signed APK, which
    # reads as a broken build rather than a limitation of the tool.
    #
    # Google's own debug key is issued to CN=Android Debug, and that is all
    # this needs to recognise.
    $sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { "$env:LOCALAPPDATA\Android\Sdk" }
    # Preview build-tools are named like "32.1.0-rc1", which [version] refuses
    # to parse, hence the filter before the sort rather than a try/catch after.
    $apksigner = Get-ChildItem "$sdk\build-tools\*\apksigner.bat" -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -match '^\d+(\.\d+)*$' } |
        Sort-Object { [version]$_.Directory.Name } |
        Select-Object -Last 1
    if (-not $apksigner) { throw "apksigner not found under $sdk\build-tools" }

    # Verified even when debug signing is allowed. "Signed with something" and
    # "signed with the key you meant" are different questions, and only the
    # second one is being waived here.
    $certs = & $apksigner.FullName verify --print-certs $apk | Out-String
    if ($LASTEXITCODE -ne 0) { throw "apksigner could not verify the APK:`n$certs" }

    $debugSigned = $certs -match 'CN=Android Debug'
    if ($debugSigned -and -not $AllowDebugSigning) {
        throw "The APK is signed with the debug key. Check android/key.properties."
    }
    if ($debugSigned) {
        Write-Host ""
        Write-Host "This APK is signed with the DEBUG key." -ForegroundColor Yellow
        Write-Host "It will sideload, and it can never be upgraded by a build signed with a real key." -ForegroundColor Yellow
        Write-Host ""
    }

    $sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
    Write-Host "APK is $sizeMb MB (budget $ApkBudgetMb MB)"
    if ($sizeMb -gt $ApkBudgetMb) {
        throw @"
The APK is $sizeMb MB, over the $ApkBudgetMb MB budget.

Find what grew before raising the budget:
    flutter build apk --release --target-platform android-arm64 --analyze-size
"@
    }

    Copy-Item $apk (Join-Path $dist "plexify-$versionName-android-arm64.apk") -Force
}

# ---------------------------------------------------------------- windows ----

if (-not $SkipWindows) {
    Write-Host "`nBuilding Windows (x64)..." -ForegroundColor Cyan
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

    $runner = 'build/windows/x64/runner/Release'
    if (-not (Test-Path $runner)) { throw "Expected $runner to exist" }

    # The exe is a stub. Without these next to it Windows reports a missing DLL
    # on launch and names only the first one it happens to look for, which
    # tells you nothing about the other three.
    foreach ($required in @('plexify.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'data')) {
        if (-not (Test-Path (Join-Path $runner $required))) {
            throw "$required is missing from the Windows build. Do not ship this."
        }
    }

    $zip = Join-Path $dist "plexify-$versionName-windows-x64.zip"
    Remove-Item $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $runner '*') -DestinationPath $zip
    $zipMb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host "Windows bundle is $zipMb MB zipped"
}

Write-Host "`nIn dist/:" -ForegroundColor Green
Get-ChildItem $dist | ForEach-Object {
    "{0,-44} {1,6:N1} MB" -f $_.Name, ($_.Length / 1MB)
}
