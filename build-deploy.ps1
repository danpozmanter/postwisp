#!/usr/bin/env pwsh
# build-deploy.ps1 — cross-build postwisp for a deployment target and
# assemble a deployable directory (dist/ by default).
#
# For a build that runs on THIS machine, use build-local.ps1 instead.

param(
    [string]$Target = 'linux-x64',
    [string]$Dir = 'dist',
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

function Show-Usage {
    $lines = @(
        'build-deploy.ps1 — cross-build postwisp for a deployment target.'
        ''
        'Usage: .\build-deploy.ps1 [TARGET] [-Dir DIR]'
        ''
        'Targets:'
        '  linux-x64     x86_64 Linux, static musl (default; the typical server)'
        '  linux-arm64   aarch64 Linux, static musl (ARM servers, Raspberry Pi)'
        '  macos-arm64   Apple Silicon macOS — requires building ON a Mac'
        '  macos-x64     Intel macOS — requires building ON a Mac'
        '  win-x64       Windows x86_64 — requires building ON Windows'
        ''
        'The script sets up cross-build prerequisites itself (rustup target,'
        'the gossamer runtime archive from the pinned toolchain release).'
        ''
        'Options:'
        '  -Dir DIR      build into DIR instead of dist/ (also: --dir DIR, --dir=DIR)'
        '  -Help         show this help'
        ''
        'The target directory is emptied first if it has anything in it, then'
        'filled with everything you run postwisp from: the binary, templates/,'
        'web/, scripts/setup.sh, and README-env.md.'
    )
    $lines -join "`n"
}

# --- argument handling --------------------------------------------------
# -Target, -Dir and -Help bind natively; the --dir=... / --dir ...
# spellings (and anything else) are parsed from the raw argument list.
$validTargets = @('linux-x64', 'linux-arm64', 'macos-arm64', 'macos-x64', 'win-x64')
$script:RuntimeTmp = $null
$targetSet = $false
$rawArgs = [System.Collections.Generic.List[string]]$args
for ($i = 0; $i -lt $rawArgs.Count; $i++) {
    $a = $rawArgs[$i]
    if ($a -eq '--help' -or $a -eq '-h' -or $a -eq '--help') { Show-Usage; exit 0 }
    elseif ($a -like '--dir=*') { $Dir = $a.Substring('--dir='.Length) }
    elseif ($a -eq '--dir' -or $a -eq '-Dir') {
        if ($i + 1 -ge $rawArgs.Count) {
            [Console]::Error.WriteLine('error: --dir needs a value')
            exit 1
        }
        $Dir = $rawArgs[$i + 1]
        $i++
    }
    elseif ($validTargets -contains $a) {
        if ($targetSet) {
            [Console]::Error.WriteLine("error: TARGET given twice ('$Target' and '$a')")
            exit 1
        }
        $Target = $a
        $targetSet = $true
    }
    elseif ($a -eq '-Target') {
        if ($i + 1 -ge $rawArgs.Count) {
            [Console]::Error.WriteLine('error: -Target needs a value')
            exit 1
        }
        if ($targetSet) {
            [Console]::Error.WriteLine("error: TARGET given twice ('$Target' and '$($rawArgs[$i + 1])')")
            exit 1
        }
        $Target = $rawArgs[$i + 1]
        $targetSet = $true
        $i++
    }
    else {
        [Console]::Error.WriteLine("error: unknown target or argument: $a")
        [Console]::Error.WriteLine('valid targets: linux-x64 linux-arm64 macos-arm64 macos-x64 win-x64')
        exit 1
    }
}

if ($Help) { Show-Usage; exit 0 }

# Validate the target BEFORE any build or prerequisite work.
if ($validTargets -notcontains $Target) {
    [Console]::Error.WriteLine("error: unknown target: $Target")
    [Console]::Error.WriteLine('valid targets: linux-x64 linux-arm64 macos-arm64 macos-x64 win-x64')
    exit 1
}

$triple = @{
    'linux-x64'   = 'x86_64-unknown-linux-musl'
    'linux-arm64' = 'aarch64-unknown-linux-musl'
    'macos-arm64' = 'aarch64-apple-darwin'
    'macos-x64'   = 'x86_64-apple-darwin'
    'win-x64'     = 'x86_64-pc-windows-msvc'
}[$Target]

# --- cross-build prerequisites -------------------------------------------
# The gossamer toolchain needs, per target: a rustup target (the musl
# cross link drives the rustup linker component), and — where the local
# toolchain install does not ship it — the runtime archive from the same
# pinned gossamer release (keep in step with `gossamer-version` in
# project.toml).
$gossamerVersion = $null
$inProject = $false
foreach ($line in (Get-Content -LiteralPath 'project.toml')) {
    if ($line -match '^\[project\]') { $inProject = $true; continue }
    if ($line -match '^\[') { $inProject = $false; continue }
    if ($inProject -and $line -match '^\s*gossamer-version\s*=\s*"([^"]+)"') {
        $gossamerVersion = $Matches[1]
        break
    }
}
if (-not $gossamerVersion) {
    [Console]::Error.WriteLine('error: could not read gossamer-version from project.toml')
    exit 1
}

if ($triple -like '*-linux-musl') {
    if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
        [Console]::Error.WriteLine("error: rustup not found — it provides the cross linker for $triple")
        exit 1
    }
    rustup target add $triple 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $arch = ($triple -split '-')[0]   # x86_64 or aarch64
    # Env var the toolchain reads: the triple with '-' as '_',
    # uppercased (GOS_RUNTIME_LIB_AARCH64_UNKNOWN_LINUX_MUSL).
    $envVar = 'GOS_RUNTIME_LIB_' + ($triple -replace '-', '_').ToUpper()
    $hostArch = (uname -m).Trim()
    if ($hostArch -notin @('x86_64', 'aarch64')) {
        $hostArch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
            .Replace('X64', 'x86_64').Replace('Arm64', 'aarch64')
    }
    $current = [System.Environment]::GetEnvironmentVariable($envVar, 'Process')
    if ([string]::IsNullOrEmpty($current) -and $arch -ne $hostArch) {
        # The runtime archive must ABI-match the gos compiler doing
        # the link. Try the installed toolchain's own release first;
        # if none is published for it, fall back to the release
        # workflow's known-good pin.
        $gosVersion = $null
        if ((gos --version) -match '^gos\s+(\S+)') { $gosVersion = $Matches[1] }
        $versions = @()
        if ($gosVersion) { $versions += "v$gosVersion" }
        $versions += 'v0.64.0'
        $versions += 'v0.61.1'
        $script:RuntimeTmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:RuntimeTmp -Force | Out-Null
        $runtimeLib = $null
        foreach ($v in $versions) {
            $verNum = $v.TrimStart('v')
            Write-Host "Fetching the gossamer $arch runtime archive ($v)..."
            $url = "https://github.com/gossamer-lang/gossamer/releases/download/$v/gos-$verNum-linux-$arch.tar.gz"
            $tgz = Join-Path $script:RuntimeTmp "gos-$arch.tar.gz"
            $ok = $true
            try {
                Invoke-WebRequest -Uri $url -OutFile $tgz -MaximumRedirection 5 -ErrorAction Stop
            }
            catch {
                $ok = $false
            }
            if ($ok) {
                tar -xzf $tgz -C $script:RuntimeTmp
                if ($LASTEXITCODE -ne 0) { $ok = $false }
            }
            if ($ok) {
                $found = Get-ChildItem -LiteralPath $script:RuntimeTmp -Recurse -Filter 'libgossamer_runtime-musl.a' |
                    Where-Object { $_.FullName -match '/gos-[^/]*/' } |
                    Select-Object -First 1
                if ($found) { $runtimeLib = $found.FullName; break }
            }
            Write-Host "  ...no archive for $v; trying the next known-good release"
            Remove-Item -LiteralPath $script:RuntimeTmp -Recurse -Force
            New-Item -ItemType Directory -Path $script:RuntimeTmp -Force | Out-Null
        }
        if (-not $runtimeLib) {
            Remove-Item -LiteralPath $script:RuntimeTmp -Recurse -Force -ErrorAction SilentlyContinue
            [Console]::Error.WriteLine("error: no matching libgossamer_runtime-musl.a release found (tried: $($versions -join ' '))")
            exit 1
        }
        # Export it for the gos build (the .sh uses `export`); the temp
        # dir must outlive the build, so it is cleaned up below it.
        Set-Item -Path "Env:$envVar" -Value $runtimeLib
    }
}

gos build --release --target $triple
$buildRc = $LASTEXITCODE
if ($script:RuntimeTmp -and (Test-Path -LiteralPath $script:RuntimeTmp)) {
    Remove-Item -LiteralPath $script:RuntimeTmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($buildRc -ne 0) { exit $buildRc }

# project.toml's `output` (target/debug/postwisp) governs where the
# toolchain links the binary, --target included. Windows links it as
# postwisp.exe instead — pick whichever exists.
$binOut = Join-Path 'target' 'debug' 'postwisp'
if (-not (Test-Path -LiteralPath $binOut)) {
    $binOut = Join-Path 'target' 'debug' 'postwisp.exe'
}
if (-not (Test-Path -LiteralPath $binOut)) {
    [Console]::Error.WriteLine("error: built binary not found (tried target/debug/postwisp and target/debug/postwisp.exe)")
    exit 1
}
$binIsExe = (Split-Path -Leaf $binOut) -eq 'postwisp.exe'

# --- populate the target directory --------------------------------------
if ((Test-Path -LiteralPath $Dir) -and (Get-ChildItem -LiteralPath $Dir -Force | Select-Object -First 1)) {
    Write-Host "Cleaning $Dir ..."
    $removed = (Get-ChildItem -LiteralPath $Dir -Force | Measure-Object).Count
    Remove-Item -LiteralPath $Dir -Recurse -Force
    Write-Host "  removed $removed item(s) from $Dir"
}
New-Item -ItemType Directory -Path (Join-Path $Dir 'scripts') -Force | Out-Null

$binName = if ($binIsExe -or $Target -eq 'win-x64') { 'postwisp.exe' } else { 'postwisp' }
Copy-Item -Path $binOut -Destination (Join-Path $Dir $binName)
Copy-Item -Path 'templates' -Destination (Join-Path $Dir 'templates') -Recurse
Copy-Item -Path 'web' -Destination (Join-Path $Dir 'web') -Recurse
Copy-Item -Path 'scripts/setup.sh' -Destination (Join-Path $Dir 'scripts' 'setup.sh')
Copy-Item -Path 'scripts/README-env.md' -Destination (Join-Path $Dir 'README-env.md')

Write-Host ''
Write-Host "$Dir/ is ready (target: $Target / $triple):"
Get-ChildItem -LiteralPath $Dir -Recurse | ForEach-Object { $_.FullName.Substring((Get-Item -LiteralPath $Dir).FullName.Length + 1) }
Write-Host ''
Write-Host "Next: copy the CONTENTS of $Dir/ to your server, then run"
Write-Host '  ./scripts/setup.sh'
Write-Host 'from that directory.'
