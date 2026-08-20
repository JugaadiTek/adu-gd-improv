#!/usr/bin/env pwsh
# Runs the automated test suite headlessly and exits with its exit code.
# Usage: pwsh tools/run_tests.ps1
# Set $env:GODOT_BIN to override the Godot executable path.

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$candidates = @(
    $env:GODOT_BIN,
    "X:\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe",
    "D:\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe"
) | Where-Object { $_ -and (Test-Path $_) }

if (-not $candidates) {
    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { $candidates = @($onPath.Source) }
}

if (-not $candidates) {
    Write-Error "Could not find a Godot 4.7 executable. Set `$env:GODOT_BIN to its path."
    exit 1
}

$godot = $candidates[0]
Write-Host "Using Godot: $godot"

& $godot --headless --path $ProjectRoot --import
& $godot --headless --path $ProjectRoot "res://scenes/tests/TestRunner.tscn"
exit $LASTEXITCODE
