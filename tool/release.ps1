<#
.SYNOPSIS
    Publish a GitHub release for the version in pubspec.yaml.

.DESCRIPTION
    Builds the artefacts through tool/package.ps1, tags the commit, and creates
    a GitHub release with the Windows zip and the Android APK attached.

    A release is public and awkward to take back, so this refuses to run rather
    than publishing something wrong. Each check exists because the mistake it
    catches is quiet:

      * The working tree must be clean, and HEAD must already be on
        origin/main. A release points at a tag; a tag on an unpushed commit
        publishes a build nobody can get the source for, and a dirty tree
        publishes a build that does not match any commit at all.

      * CHANGELOG.md must have a section for this version, and it becomes the
        release notes. Without this the easy path is a release with an empty
        body, which is indistinguishable from a broken one a month later.

      * The tag must not exist. Re-releasing a version silently replaces what
        people already downloaded. Bump pubspec.yaml (and PlexIdentity.version
        with it, which test/packaging_test.dart enforces) instead.

      * Everything package.ps1 checks: real signing key, size budget, and a
        Windows bundle that actually contains its DLLs.

    While the major version is 0 the release is marked as a prerelease, which
    is what 0.9.x is.

.PARAMETER Yes
    Skip the confirmation prompt. For when you have run this enough times.

.PARAMETER Draft
    Create the release as a draft, so it can be looked at before anyone sees
    it. The tag is still created and pushed.

.PARAMETER SkipBuild
    Use whatever is already in dist/. Only sensible immediately after a run
    that failed at the publishing step, since nothing then re-checks the
    artefacts.

.EXAMPLE
    powershell -File tool/release.ps1

.EXAMPLE
    powershell -File tool/release.ps1 -Draft
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$Draft,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Fail($message) { throw $message }

# ------------------------------------------------------------------- gh ------

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Fail @"
The GitHub CLI is not installed, and this script does the whole release through
it.

    winget install --id GitHub.cli
    gh auth login

Then run this again.
"@
}

# `gh auth status` writes to stderr on success as well as failure, so the exit
# code is the only thing worth reading here.
& gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail "The GitHub CLI is not signed in. Run: gh auth login"
}

# --------------------------------------------------------------- version -----

$pubspec = Get-Content pubspec.yaml -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\S+)\s*$') {
    Fail "Could not read 'version:' from pubspec.yaml"
}
$versionName = $Matches[1].Split('+')[0]
$tag = "v$versionName"

# -------------------------------------------------------------- git state ----

$dirty = git status --porcelain
if ($dirty) {
    Fail @"
The working tree has uncommitted changes, so this release would not correspond
to any commit. Commit or stash first.

$dirty
"@
}

git fetch origin --quiet
if ($LASTEXITCODE -ne 0) { Fail "git fetch failed" }

# --is-ancestor answers with the exit code and prints nothing.
git merge-base --is-ancestor HEAD origin/main
if ($LASTEXITCODE -ne 0) {
    Fail @"
HEAD is not on origin/main yet, so the tag would point at a commit that only
exists on this machine. Push first:

    git push origin main
"@
}

$existing = git tag --list $tag
if ($existing) {
    Fail @"
Tag $tag already exists, so $versionName has been released before. Replacing it
would swap the files under anyone who already downloaded them.

Bump 'version:' in pubspec.yaml and PlexIdentity.version together, add a
CHANGELOG.md section for the new version, and run this again.
"@
}

# ------------------------------------------------------------- changelog -----

if (-not (Test-Path 'CHANGELOG.md')) { Fail "CHANGELOG.md is missing" }
$changelog = Get-Content CHANGELOG.md -Raw

# Everything between this version's heading and the next one. The heading may
# be written as `## [0.9.0]` or `## 0.9.0`, optionally followed by a date.
$escaped = [regex]::Escape($versionName)
$section = [regex]::Match(
    $changelog,
    "(?ms)^##\s+\[?$escaped\]?.*?$\r?\n(.*?)(?=^##\s|\z)"
)
if (-not $section.Success) {
    Fail @"
CHANGELOG.md has no section for $versionName.

Add one before releasing:

    ## [$versionName]

    ### Added
    - ...
"@
}

$notes = $section.Groups[1].Value.Trim()
if (-not $notes) {
    Fail "The CHANGELOG.md section for $versionName is empty. Say what changed."
}

# ----------------------------------------------------------------- build -----

$dist = Join-Path $repo 'dist'
$apk = Join-Path $dist "plexify-$versionName-android-arm64.apk"
$zip = Join-Path $dist "plexify-$versionName-windows-x64.zip"

if ($SkipBuild) {
    Write-Host "Skipping the build; using what is already in dist/." -ForegroundColor Yellow
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'package.ps1')
    if ($LASTEXITCODE -ne 0) { Fail "tool/package.ps1 failed, so nothing is being released" }
}

foreach ($artefact in @($apk, $zip)) {
    if (-not (Test-Path $artefact)) {
        Fail "Expected $artefact to exist. Run without -SkipBuild."
    }
}

# --------------------------------------------------------------- confirm -----

$prerelease = $versionName -match '^0\.'

Write-Host ""
Write-Host "About to publish:" -ForegroundColor Cyan
Write-Host "  tag        $tag  ->  $(git rev-parse --short HEAD)"
Write-Host "  repo       $(gh repo view --json nameWithOwner -q .nameWithOwner)"
Write-Host "  prerelease $prerelease"
Write-Host "  draft      $([bool]$Draft)"
foreach ($artefact in @($zip, $apk)) {
    "  file       {0} ({1:N1} MB)" -f (Split-Path $artefact -Leaf), ((Get-Item $artefact).Length / 1MB) | Write-Host
}
Write-Host ""
Write-Host "Release notes, from CHANGELOG.md:" -ForegroundColor Cyan
Write-Host $notes
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Publish this? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "Nothing published." -ForegroundColor Yellow
        return
    }
}

# --------------------------------------------------------------- publish -----

# Tagged only once the artefacts exist and have passed their checks, so a failed
# build does not leave a tag behind claiming a release that never happened.
git tag -a $tag -m "Plexify $versionName"
if ($LASTEXITCODE -ne 0) { Fail "Could not create tag $tag" }

git push origin $tag
if ($LASTEXITCODE -ne 0) {
    git tag -d $tag | Out-Null
    Fail "Could not push tag $tag, so the local tag has been removed again"
}

$notesFile = Join-Path ([System.IO.Path]::GetTempPath()) "plexify-$versionName-notes.md"
Set-Content -Path $notesFile -Value $notes -Encoding utf8

$arguments = @(
    'release', 'create', $tag,
    $zip, $apk,
    '--title', "Plexify $versionName",
    '--notes-file', $notesFile
)
if ($prerelease) { $arguments += '--prerelease' }
if ($Draft) { $arguments += '--draft' }

& gh @arguments
$published = $LASTEXITCODE
Remove-Item $notesFile -ErrorAction SilentlyContinue

if ($published -ne 0) {
    Fail @"
gh release create failed. The tag $tag has been pushed, so fix whatever it
reported and either retry with -SkipBuild, or delete the tag first:

    git push origin :refs/tags/$tag
    git tag -d $tag
"@
}

Write-Host "`nPublished $tag" -ForegroundColor Green
gh release view $tag --web
