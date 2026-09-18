#!/usr/bin/env pwsh
# build-local.ps1 — build postwisp for THIS machine and assemble a
# deployable directory (dist/ by default).
#
# For a build that targets a server (different OS/architecture), use
# build-deploy.ps1 instead.
#
# The target directory is emptied first if it has anything in it, then
# filled with everything you run postwisp from:
#   postwisp          the release binary
#   templates/        index.html post.html list.html about.html (inline CSS)
#   web/              built-in admin/editor/setup pages the binary serves
#   scripts/setup.sh  first-run walkthrough (run it ON THE SERVER)
#   README-env.md     environment variables the server reads at boot

param(
    [string]$Dir = 'dist',
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

function Show-Usage {
    $lines = @(
        'build-local.ps1 — build postwisp for THIS machine and assemble a'
        'deployable directory (dist/ by default).'
        ''
        'For a build that targets a server (different OS/architecture), use'
        'build-deploy.ps1 instead.'
        ''
        'Usage: .\build-local.ps1 [-Dir DIR]'
        ''
        '  -Dir DIR    build into DIR instead of dist/ (also: --dir DIR, --dir=DIR)'
        '  -Help       show this help'
        ''
        'The target directory is emptied first if it has anything in it, then'
        'filled with everything you run postwisp from:'
        '  postwisp          the release binary'
        '  templates/        index.html post.html list.html about.html (inline CSS)'
        '  web/              built-in admin/editor/setup pages the binary serves'
        '  scripts/setup.sh  first-run walkthrough (run it ON THE SERVER)'
        '  README-env.md     environment variables the server reads at boot'
    )
    $lines -join "`n"
}

# --- argument handling --------------------------------------------------
# -Dir and -Help bind natively; the --dir=... / --dir ... spellings (and
# anything else) are parsed from the raw argument list.
$rawArgs = [System.Collections.Generic.List[string]]$args
for ($i = 0; $i -lt $rawArgs.Count; $i++) {
    $a = $rawArgs[$i]
    if ($a -eq '--help' -or $a -eq '-h') { Show-Usage; exit 0 }
    elseif ($a -like '--dir=*') { $Dir = $a.Substring('--dir='.Length) }
    elseif ($a -eq '--dir' -or $a -eq '-Dir') {
        if ($i + 1 -ge $rawArgs.Count) {
            [Console]::Error.WriteLine('error: --dir needs a value')
            exit 1
        }
        $Dir = $rawArgs[$i + 1]
        $i++
    }
    elseif ($a -eq '--help') { Show-Usage; exit 0 }
    elseif ($a -like '-*') {
        [Console]::Error.WriteLine("error: unknown argument: $a (try --help)")
        exit 1
    }
    else {
        [Console]::Error.WriteLine("error: unknown argument: $a (try --help)")
        exit 1
    }
}

if ($Help) { Show-Usage; exit 0 }

# --- build --------------------------------------------------------------
gos build --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# project.toml's `output` (target/debug/postwisp) governs where the
# toolchain links the binary, release included. On Windows it may land
# as postwisp.exe instead — pick whichever exists.
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

$binName = if ($binIsExe) { 'postwisp.exe' } else { 'postwisp' }
Copy-Item -Path $binOut -Destination (Join-Path $Dir $binName)
Copy-Item -Path 'templates' -Destination (Join-Path $Dir 'templates') -Recurse
Copy-Item -Path 'web' -Destination (Join-Path $Dir 'web') -Recurse
Copy-Item -Path 'scripts/setup.sh' -Destination (Join-Path $Dir 'scripts' 'setup.sh')
Copy-Item -Path 'scripts/README-env.md' -Destination (Join-Path $Dir 'README-env.md')

Write-Host ''
Write-Host "$Dir/ is ready:"
Get-ChildItem -LiteralPath $Dir -Recurse | ForEach-Object { $_.FullName.Substring((Get-Item -LiteralPath $Dir).FullName.Length + 1) }
Write-Host ''
Write-Host "Next: to deploy, copy the CONTENTS of $Dir/ to your server, then run"
Write-Host '  ./scripts/setup.sh'
Write-Host 'from that directory.'
