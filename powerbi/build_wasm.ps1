# Build doomgeneric (+ doomgeneric_pbi.c) -> single-file WASM/JS bundle for the
# Power BI visual. Windows equivalent of `make -f Makefile.pbi install`.
#
#   .\build_wasm.ps1                      # uses $env:EMSDK_ROOT, or ..\emsdk
#   $env:EMSDK_ROOT = "D:\tools\emsdk"; .\build_wasm.ps1
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Src      = Join-Path $RepoRoot "doomgeneric"
$Out      = Join-Path $PSScriptRoot "src\doom.js"

# Emscripten SDK: honor $env:EMSDK_ROOT if set, else <repo>\emsdk.
$emsdkRoot = if ($env:EMSDK_ROOT) { $env:EMSDK_ROOT } else { Join-Path $RepoRoot "emsdk" }
$emsdkEnv  = Join-Path $emsdkRoot "emsdk_env.ps1"
if (-not (Test-Path $emsdkEnv)) {
  throw "Emscripten activation script not found at '$emsdkEnv'. Install emsdk (or set `$env:EMSDK_ROOT) - see powerbi/README.md."
}
& $emsdkEnv | Out-Null

# Verify the shareware WAD before embedding it. This exact file ships in the .pbiviz.
$wad       = Join-Path $Src "doom1.wad"
$wadSha256 = "1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771"
$wadBytes  = 4196020
if (-not (Test-Path $wad)) {
  throw "Shareware WAD not found at '$wad'. Download doom1.wad - see powerbi/README.md."
}
$actualSha = (Get-FileHash -Algorithm SHA256 $wad).Hash
$actualLen = (Get-Item $wad).Length
if (($actualSha -ne $wadSha256) -or ($actualLen -ne $wadBytes)) {
  throw "doom1.wad integrity check FAILED. Expected SHA-256 $wadSha256 ($wadBytes bytes); got $actualSha ($actualLen bytes). Refusing to embed an unverified WAD."
}
Write-Host "doom1.wad verified (SHA-256 $wadSha256, $wadBytes bytes)."

# Everything the generic Makefile builds, minus the other platforms' backends
# and the SDL/Allegro sound modules. Keep in sync with SRC_DOOM in Makefile.pbi.
$exclude = @(
  "doomgeneric_allegro.c","doomgeneric_emscripten.c","doomgeneric_linuxvt.c",
  "doomgeneric_sdl.c","doomgeneric_soso.c","doomgeneric_sosox.c",
  "doomgeneric_win.c","doomgeneric_xlib.c",
  "i_allegromusic.c","i_allegrosound.c","i_sdlmusic.c","i_sdlsound.c",
  "mus2mid.c","gusconf.c","icon.c"
)
Push-Location $Src
try {
  $files = Get-ChildItem -Filter *.c | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object { $_.Name }
  Write-Host "Compiling $($files.Count) source files..."

  $emccArgs = @(
    $files
    "-O2","-Wall","-DNORMALUNIX","-DLINUX","-I."
    "-s","SINGLE_FILE=1"
    "-s","MODULARIZE=1"
    "-s","EXPORT_NAME=createDoom"
    "-s","ENVIRONMENT=web"
    "-s","ALLOW_MEMORY_GROWTH=1"
    "-s","INITIAL_MEMORY=67108864"
    "-s","EXIT_RUNTIME=0"
    "-s","EXPORTED_RUNTIME_METHODS=['callMain','HEAPU8']"
    "-s","EXPORTED_FUNCTIONS=['_main','_dg_add_key','_doomgeneric_Tick']"
    "--embed-file","doom1.wad@/doom1.wad"
    "-o",$Out
  )
  & emcc @emccArgs
  if ($LASTEXITCODE -ne 0) { throw "emcc failed with exit $LASTEXITCODE" }
} finally { Pop-Location }

Write-Host "BUILD_OK -> $Out"
Get-Item $Out | Select-Object Name, Length
