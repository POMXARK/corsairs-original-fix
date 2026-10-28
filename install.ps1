<#
Fixes the original «Корсары» (Sea Dogs, 2000, ENGINE.exe) on Windows 10/11: wraps its DirectDraw into Direct3D with
DDrawCompat and sets engine.ini and DDrawCompat.ini (16-bit colour kept). Nothing of the game is stored here: the wrapper is downloaded from its official
release (version and SHA-256 are pinned below), the game files stay where they are; every file that is changed is saved as <name>.orig.

  powershell -ExecutionPolicy Bypass -File install.ps1                   # find the game, install, fullscreen in the resolution of the desktop
  powershell -ExecutionPolicy Bypass -File install.ps1 -Windowed         # a window instead of fullscreen
  powershell -ExecutionPolicy Bypass -File install.ps1 -GameDir "D:\Games\Корсары" -Width 1920 -Height 1080   # any resolution, also above 1280x1024 that Config.exe lists
  powershell -ExecutionPolicy Bypass -File install.ps1 -Wasd             # walking in towns on W A S D, as in the new engine
  powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall        # the originals back
#>
param(
    [string]$GameDir,
    [switch]$Windowed,
    [int]$Width = 0,    # 0 = the resolution of the desktop
    [int]$Height = 0,
    [switch]$Wasd,      # walking in towns on W A S D (the original: arrows and the mouse)
    [double]$FontScale = 0,   # 0 = Height / 960 (not below 1); 1 leaves the fonts as they are
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

function Set-FontScale($path, $k) {
    # fonts.ini: "name = scale,weight,italic,face" in [english]/[russian]; the scale is taken from the saved original
    $enc = [Text.Encoding]::GetEncoding(1251)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $lines = [IO.File]::ReadAllLines("$path.orig", $enc) | ForEach-Object {
        if ($_ -match '^(\w+\s*=\s*)([0-9.]+)(,.*)$') { $Matches[1] + ([double]::Parse($Matches[2], $inv) * $k).ToString("0.00", $inv) + $Matches[3] } else { $_ }
    }
    [IO.File]::WriteAllLines($path, $lines, $enc)
}

function Set-Walk($path, [bool]$wasd) {
    # controls.ini: controlN=group,key1,key2,current1,current2; group 1 is the walking in towns: 24 forward, 25 back, 38 left, 39 right
    # (virtual-key codes: W 87, S 83, A 65, D 68; the second key is the mouse button / arrow of the original)
    $enc = [Text.Encoding]::GetEncoding(1251)
    $new = @{ "control24" = "1,87,1,87,1"; "control25" = "1,83,2,83,2"; "control38" = "1,65,37,65,37"; "control39" = "1,68,39,68,39" }
    $src = "$path.orig"   # always from the saved original: a rebind of the last run does not stay
    if (-not (Test-Path $src)) { return }
    $lines = [IO.File]::ReadAllLines($src, $enc) | ForEach-Object {
        if ($wasd -and $_ -match "^(control\d+)=" -and $new.ContainsKey($Matches[1])) { "$($Matches[1])=" + $new[$Matches[1]] } else { $_ }
    }
    [IO.File]::WriteAllLines($path, $lines, $enc)
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
    $cfg = Join-Path $GameDir "DDrawCompat.ini"
    if (Test-Path $cfg) { Remove-Item $cfg; Write-Host "removed DDrawCompat.ini" }
    foreach ($p in @($dll, $ini, (Join-Path $GameDir "RESOURCE\INI\fonts.ini"), (Join-Path $GameDir "RESOURCE\INI\controls.ini"))) {
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

$new = Join-Path $tmp "ddraw.dll"
# an already installed DDrawCompat is not an original
if (-not (Test-Path $dll) -or (Get-FileHash $dll).Hash -ne (Get-FileHash $new).Hash) { Save-Original $dll }
Copy-Item $new $dll -Force
Copy-Item (Join-Path $Here "DDrawCompat.ini") (Join-Path $GameDir "DDrawCompat.ini") -Force

if (-not $Width -or -not $Height) {
    $v = Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
    $Width = if ($v) { [int]$v.CurrentHorizontalResolution } else { 1280 }
    $Height = if ($v) { [int]$v.CurrentVerticalResolution } else { 960 }
}
Save-Original $ini
Set-IniKey $ini "BPP" 16   # the game is 16-bit; DDrawCompat.ini (DesktopColorDepth=16) keeps it so on a 32-bit desktop
Set-IniKey $ini "WINDOW_WIDTH" $Width
Set-IniKey $ini "WINDOW_HEIGHT" $Height
Set-IniKey $ini "WINDOW_MODE" ($(if ($Windowed) { 1 } else { 0 }))
if (-not $FontScale) { $FontScale = [Math]::Max(1.0, [Math]::Floor($Height / 96.0 + 0.5) / 10.0) }
$fonts = Join-Path $GameDir "RESOURCE\INI\fonts.ini"
Save-Original $fonts
Set-FontScale $fonts $FontScale
Write-Host "fonts x$FontScale"
$ctl = Join-Path $GameDir "RESOURCE\INI\controls.ini"
Save-Original $ctl
Set-Walk $ctl ([bool]$Wasd)
if ($Wasd) { Write-Host "walking: W A S D" }
# the settings window next to the game (the repository folder can be deleted) and a shortcut on the desktop
$tools = Join-Path $GameDir "fix"
if ($Here -ne $tools) {
    New-Item $tools -ItemType Directory -Force | Out-Null
    foreach ($n in "install.ps1", "settings.ps1", "settings.cmd", "capture.ps1", "overlay.bin", "play.cmd", "DDrawCompat.ini") { Copy-Item (Join-Path $Here $n) $tools -Force }
}
$lnk = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Корсары - настройки.lnk"
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sc.TargetPath = Join-Path $tools "settings.cmd"; $sc.WorkingDirectory = $tools
$sc.IconLocation = (Join-Path $GameDir "ENGINE.exe") + ",0"; $sc.Save()
$lnk2 = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Корсары - игра (F8 F9 FPS).lnk"
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk2)
$sc.TargetPath = Join-Path $tools "play.cmd"; $sc.WorkingDirectory = $tools
$sc.IconLocation = (Join-Path $GameDir "ENGINE.exe") + ",0"; $sc.Save()
Write-Host "settings: $tools\settings.cmd, shortcut on the desktop"
Write-Host "done: DDrawCompat $DdVersion, engine.ini BPP 16, $Width x $Height" ($(if ($Windowed) { "windowed" } else { "fullscreen" }))
