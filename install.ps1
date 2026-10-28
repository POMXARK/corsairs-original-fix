<#
Fixes the original «Корсары» (Sea Dogs, 2000, ENGINE.exe) on Windows 10/11: wraps its DirectDraw into Direct3D with
DDrawCompat and sets engine.ini (32-bit colour). Nothing of the game is stored here: the wrapper is downloaded from its official
release (version and SHA-256 are pinned below), the game files stay where they are; every file that is changed is saved as <name>.orig.

  powershell -ExecutionPolicy Bypass -File install.ps1                   # find the game, install, fullscreen 1280x960
  powershell -ExecutionPolicy Bypass -File install.ps1 -Windowed         # a window instead of fullscreen
  powershell -ExecutionPolicy Bypass -File install.ps1 -GameDir "D:\Games\Корсары" -Width 1600 -Height 1200
  powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall        # the originals back
#>
param(
    [string]$GameDir,
    [switch]$Windowed,
    [int]$Width = 1280,
    [int]$Height = 960,
    [switch]$Uninstall
)
$ErrorActionPreference = "Stop"
$DdVersion = "0.5.4"   # 0.5.2 is slow on loading screens; dgVoodoo2 2.87 hangs on the intro videos of this game
$DdUrl = "https://github.com/narzoul/DDrawCompat/releases/download/v$DdVersion/DDrawCompat-v$DdVersion.zip"
$DdSha256 = "569c7e0095de0909d31107f370cbd30a904e53c765333e2aff172bac82438137"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Game {
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "C:\Games", "D:\Games")) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Recurse -Filter ENGINE.exe -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.DirectoryName "MODULES\CORE.dll") } | Select-Object -First 1
        if ($hit) { return $hit.DirectoryName }
    }
    throw "ENGINE.exe of the game is not found: pass -GameDir <folder>"
}

function Save-Original($path) {
    if ((Test-Path $path) -and -not (Test-Path "$path.orig")) { Copy-Item $path "$path.orig" }
}

function Set-IniKey($path, $key, $value) {
    # engine.ini is "KEY value" per line (CRLF, cp1251): only the value of the key changes
    $enc = [Text.Encoding]::GetEncoding(1251)
    $found = $false
    $lines = [IO.File]::ReadAllLines($path, $enc) | ForEach-Object { if ($_ -match "^$key\s") { $found = $true; "$key $value" } else { $_ } }
    if (-not $found) { $lines += "$key $value" }
    [IO.File]::WriteAllLines($path, $lines, $enc)
}

if (-not $GameDir) { $GameDir = Find-Game }
if (-not (Test-Path (Join-Path $GameDir "ENGINE.exe"))) { throw "no ENGINE.exe in $GameDir" }
Write-Host "game: $GameDir"
$ini = Join-Path $GameDir "engine.ini"
$dll = Join-Path $GameDir "ddraw.dll"

if ($Uninstall) {
    foreach ($p in @($dll, $ini)) {
        if (Test-Path "$p.orig") { Move-Item "$p.orig" $p -Force; Write-Host "restored $(Split-Path -Leaf $p)" }
        elseif ($p -eq $dll -and (Test-Path $p)) { Remove-Item $p; Write-Host "removed ddraw.dll" }
    }
    return
}

$zip = Join-Path $env:TEMP "DDrawCompat-v$DdVersion.zip"
if (-not (Test-Path $zip) -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $DdSha256.ToUpper()) {
    Write-Host "downloading DDrawCompat $DdVersion ..."
    Invoke-WebRequest $DdUrl -OutFile $zip -UseBasicParsing
}
if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $DdSha256.ToUpper()) { throw "DDrawCompat archive: wrong SHA-256, not installed" }
$tmp = Join-Path $env:TEMP "DDrawCompat_$DdVersion"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive $zip $tmp

Save-Original $dll
Copy-Item (Join-Path $tmp "ddraw.dll") $dll -Force

Save-Original $ini
Set-IniKey $ini "BPP" 32   # BPP 16 is the cause of the purple/green colours: the game reads the 16-bit pixel format wrong
Set-IniKey $ini "WINDOW_WIDTH" $Width
Set-IniKey $ini "WINDOW_HEIGHT" $Height
Set-IniKey $ini "WINDOW_MODE" ($(if ($Windowed) { 1 } else { 0 }))
Write-Host "done: DDrawCompat $DdVersion, engine.ini BPP 32, $Width x $Height" ($(if ($Windowed) { "windowed" } else { "fullscreen" }))
