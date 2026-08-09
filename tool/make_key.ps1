<#
.SYNOPSIS
    Create the Android upload keystore and wire it into the build.

.DESCRIPTION
    Replaces a keytool command in the README that could not work as written:
    it referenced $env:JAVA_HOME, which nothing sets outside package.ps1, and
    wrote into a directory keytool will not create. This finds keytool, makes
    the directory, generates the key, and writes android/key.properties.

    The password is read interactively and handed to keytool through an
    environment variable, so it is never on a command line where it would land
    in the process list, and never in shell history.

    **The keystore it makes is unrecoverable.** Android will only accept an
    update signed with the same key, so losing this file means every install
    has to be removed and re-added, taking the library cache and the Plex token
    with it. Back it up somewhere that is not this repository.

    Nothing here is required to sideload. Android wants a signature, not a
    particular one, and `tool/release.ps1 -AllowDebugSigning` will publish a
    debug-signed build. This exists because whichever key ships first is locked
    in for everyone who installs it.

.PARAMETER Path
    Where to write the keystore. Defaults to ~\keys\plexify-upload.jks, which
    is outside the repository on purpose.

.PARAMETER Alias
    Key alias. Must match keyAlias in android/key.properties, which this
    writes, so there is rarely a reason to change it.

.PARAMETER Dname
    The certificate's subject. Nothing checks it for a sideloaded app, and Play
    does not show it to anyone, so the default is fine.

.PARAMETER Force
    Overwrite an existing keystore. Almost certainly the wrong thing; see
    above.

.EXAMPLE
    powershell -File tool/make_key.ps1
#>
[CmdletBinding()]
param(
    [string]$Path = "$env:USERPROFILE\keys\plexify-upload.jks",
    [string]$Alias = 'plexify',
    [string]$Dname = 'CN=Plexify, OU=Personal, O=Plexify, C=AU',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Fail($message) {
    Write-Host ''
    Write-Host $message -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ------------------------------------------------------------------ keytool --

# JAVA_HOME is empty in an ordinary shell on this machine: package.ps1 sets it
# for its own run and nothing sets it globally, which is exactly why the
# documented command failed. Android Studio ships a JDK, so look there too.
$candidates = @()
# Skipped rather than tested when unset, or the path becomes "\bin\keytool.exe"
# and Test-Path resolves that against the current drive root instead.
if ($env:JAVA_HOME) { $candidates += "$env:JAVA_HOME\bin\keytool.exe" }
$candidates += "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe"
$candidates += "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe"

$keytool = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $keytool) {
    $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
}

if (-not $keytool) {
    Fail @"
keytool was not found. It ships with any JDK, including the one inside Android
Studio at:

    $env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe

Set JAVA_HOME to a JDK, or pass the path by editing this script.
"@
}

# --------------------------------------------------------------- guardrails --

if ((Test-Path $Path) -and -not $Force) {
    Fail @"
$Path already exists.

Overwriting it would strand every install signed with the old key: Android
refuses an update signed with a different one, so they would each have to be
uninstalled, losing the library cache and the Plex token.

If you are certain, pass -Force. If you have lost the password instead, the key
is gone and this is the same situation.
"@
}

if ((Test-Path 'android/key.properties') -and -not $Force) {
    Fail @"
android/key.properties already exists, so a key has been set up before. Look at
it before going further; this would replace it.
"@
}

# ---------------------------------------------------------------- password ---

Write-Host "Creating an Android upload key for Plexify." -ForegroundColor Cyan
Write-Host "  keytool   $keytool"
Write-Host "  keystore  $Path"
Write-Host "  alias     $Alias"
Write-Host ''
Write-Host 'The password goes into android/key.properties in plain text, which is'
Write-Host 'how Gradle reads it. That file is gitignored and a test asserts it.'
Write-Host ''

$first = Read-Host 'Choose a password (at least 6 characters)' -AsSecureString
$again = Read-Host 'Type it again' -AsSecureString

function Reveal([System.Security.SecureString]$secure) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

$password = Reveal $first
if ($password -ne (Reveal $again)) { Fail 'The two passwords do not match.' }
if ($password.Length -lt 6) { Fail 'keytool requires at least 6 characters.' }

# ------------------------------------------------------------------ generate --

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null

# Through the environment rather than -storepass, which would put the password
# in the command line for anything reading the process list, and in the shell
# history of whoever copies this out of the README next.
$env:PLEXIFY_KEYSTORE_PASS = $password
try {
    & $keytool -genkeypair -v `
        -keystore $Path `
        -storepass:env PLEXIFY_KEYSTORE_PASS `
        -keypass:env PLEXIFY_KEYSTORE_PASS `
        -keyalg RSA -keysize 4096 `
        -validity 10000 `
        -alias $Alias `
        -dname $Dname
    $generated = $LASTEXITCODE
} finally {
    Remove-Item Env:\PLEXIFY_KEYSTORE_PASS -ErrorAction SilentlyContinue
}

if ($generated -ne 0 -or -not (Test-Path $Path)) {
    Fail "keytool failed, and no keystore was written."
}

# -------------------------------------------------------------- properties ---

# Forward slashes: Gradle reads this as a Java properties file, where a
# backslash is an escape and C:\Users becomes C:Users with a tab in it.
$storeFile = $Path -replace '\\', '/'

@"
# Written by tool/make_key.ps1. Gitignored, and test/packaging_test.dart
# asserts that it stays that way, because it holds the keystore password in
# plain text.
storeFile=$storeFile
storePassword=$password
keyAlias=$Alias
keyPassword=$password
"@ | Set-Content -Path 'android/key.properties' -Encoding utf8

$password = $null

Write-Host ''
Write-Host "Done." -ForegroundColor Green
Write-Host "  keystore   $Path"
Write-Host "  properties android/key.properties"
Write-Host ''
Write-Host 'Back the keystore up somewhere that is not this repository. Losing it' -ForegroundColor Yellow
Write-Host 'means every install has to be removed and re-added.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Then: powershell -File tool/release.ps1'
