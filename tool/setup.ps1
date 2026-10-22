# Generates the platform folders around the hand-written code, then fetches packages.
# flutter create never overwrites existing files, so lib/, the Android manifest/Kotlin
# files and the macOS entitlements in this repo are kept.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

flutter create --org com.gshare --project-name gshare --platforms android,ios,windows,macos,linux .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter analyze

Write-Host ''
Write-Host 'Done. Run on a device:  flutter run'
Write-Host 'iOS/macOS must be built on a Mac: run  bash tool/setup.sh  there.'
