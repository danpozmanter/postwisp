# build.ps1 — Windows twin of build.sh: release binary + deployable dist/.
#
# dist/ ends up containing everything you copy to your server:
#   postwisp          the release binary
#   templates/        index.html post.html list.html about.html (inline CSS)
#   web/              built-in admin/editor/setup pages the binary serves
#   scripts/setup.sh  first-run walkthrough (run it ON THE SERVER)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

gos build --release

# project.toml's `output` (target/debug/postwisp) governs where the
# toolchain links the binary, release included.
$binOut = "target/debug/postwisp"

if (Test-Path dist) { Remove-Item -Recurse -Force dist }
New-Item -ItemType Directory dist | Out-Null
New-Item -ItemType Directory dist/scripts | Out-Null
Copy-Item $binOut dist/postwisp
Copy-Item templates dist/templates
Copy-Item web dist/web
Copy-Item scripts/setup.sh dist/scripts/setup.sh

Write-Host ""
Write-Host "dist/ is ready:"
Get-ChildItem -Recurse dist | ForEach-Object { $_.FullName.Replace($PSScriptRoot, "") }
Write-Host ""
Write-Host "Next: copy the CONTENTS of dist/ to your server, then run"
Write-Host "  ./scripts/setup.sh"
Write-Host "from that directory."
