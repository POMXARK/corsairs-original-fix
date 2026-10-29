<#
Fixes the original «Корсары» (Sea Dogs, 2000, ENGINE.exe) on Windows 10/11: wraps its DirectDraw into Direct3D with
DDrawCompat and sets engine.ini and DDrawCompat.ini (16-bit colour kept). Nothing of the game is stored here: the wrapper is downloaded from its official
release (version and SHA-256 are pinned below), the game files stay where they are; every file that is changed is saved as <name>.orig.

  powershell -ExecutionPolicy Bypass -File install.ps1                   # find the game, install, fullscreen in the resolution of the desktop
  powershell -ExecutionPolicy Bypass -File install.ps1 -Windowed         # a window instead of fullscreen
  powershell -ExecutionPolicy Bypass -File install.ps1 -GameDir "D:\Games\Корсары" -Width 1920 -Height 1080   # any resolution, also above 1280x1024 that Config.exe lists
  powershell -ExecutionPolicy Bypass -File install.ps1 -Wasd             # walking in towns on W A S D, as in the new engine
  powershell -ExecutionPolicy Bypass -File install.ps1 -Windowed -Width 1920 -Height 1080 -Supersample 3 -UiScale   # supersampling: buttons, frames and fonts of the menus enlarged to the render size
  powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall        # the originals back
#>
param(
    [string]$GameDir,
    [switch]$Windowed,
    [int]$Width = 0,    # 0 = the resolution of the desktop
    [int]$Height = 0,
    [switch]$Wasd,      # walking in towns on W A S D (the original: arrows and the mouse)
    [double]$Supersample = 1,   # the game renders at Width*k x Height*k: DDrawCompat shrinks it to the screen (fullscreen), overlay.c averages it down to the window (windowed)
    [double]$FontScale = 0,   # 0 = Height / 960 (not below 1); 1 leaves the fonts as they are
    [switch]$UiScale,   # with -Supersample: sprites of the menus (RESOURCE\IMAGES) are enlarged by the font scale and the fonts of the menus lose the "fixed size" quirk; without it the originals come back
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
        if ($_ -match '^((?!rgb_)\w+\s*=\s*)([0-9.]+)(,.*)$') { $Matches[1] + ([double]::Parse($Matches[2], $inv) * $k).ToString("0.00", $inv) + $Matches[3] } else { $_ }
    }
    [IO.File]::WriteAllLines($path, $lines, $enc)
}

$UiDirs = "BUTTONS", "FRAMES", "MENU", "SCROLLS", "STATUS", "RANSACK"   # sprites are drawn in their own pixels: at a render k times larger they look k times smaller
$UiInis = "menu.ini", "map.ini", "town.ini", "status.ini", "ransack.ini"

Add-Type -TypeDefinition @"
using System;
using System.IO;
public static class TgaScale {
    static double L(double x) { x = Math.Abs(x); if (x < 1e-9) return 1; if (x >= 3) return 0; double p = Math.PI * x; return 3 * Math.Sin(p) * Math.Sin(p / 3) / (p * p); }
    static float[] Resize(float[] s, int w, int h, int W, int H) {
        float[] t = new float[W * h];
        double sx = (double)w / W; double fx = Math.Max(1.0, sx);
        for (int X = 0; X < W; X++) {
            double c = (X + 0.5) * sx - 0.5; int a = (int)Math.Floor(c - 3 * fx), b = (int)Math.Ceiling(c + 3 * fx);
            double[] wt = new double[b - a + 1]; double sum = 0;
            for (int i = a; i <= b; i++) { wt[i - a] = L((i - c) / fx); sum += wt[i - a]; }
            for (int y = 0; y < h; y++) { double v = 0; for (int i = a; i <= b; i++) v += wt[i - a] * s[y * w + Math.Min(w - 1, Math.Max(0, i))]; t[y * W + X] = (float)(v / sum); }
        }
        float[] o = new float[W * H]; double sy = (double)h / H; double fy = Math.Max(1.0, sy);
        for (int Y = 0; Y < H; Y++) {
            double c = (Y + 0.5) * sy - 0.5; int a = (int)Math.Floor(c - 3 * fy), b = (int)Math.Ceiling(c + 3 * fy);
            double[] wt = new double[b - a + 1]; double sum = 0;
            for (int i = a; i <= b; i++) { wt[i - a] = L((i - c) / fy); sum += wt[i - a]; }
            for (int x = 0; x < W; x++) { double v = 0; for (int i = a; i <= b; i++) v += wt[i - a] * t[Math.Min(h - 1, Math.Max(0, i)) * W + x]; o[Y * W + x] = (float)(v / sum); }
        }
        return o;
    }
    static int Cl(double v, int m) { return (int)Math.Min(m, Math.Max(0, Math.Round(v))); }
    // uncompressed TGA, 16 bit (rgb555 + 1 bit of alpha) or 32 bit; colour and alpha are resampled apart, so transparent pixels do not darken the edges
    public static bool Scale(string src, string dst, double k) {
        byte[] d = File.ReadAllBytes(src); int off = 18 + d[0]; int w = d[12] | (d[13] << 8), h = d[14] | (d[15] << 8), bpp = d[16];
        if (d[1] != 0 || d[2] != 2 || (bpp != 16 && bpp != 32)) return false;
        int W = (int)Math.Round(w * k), H = (int)Math.Round(h * k), n = w * h, bp = bpp / 8;
        float[][] ch = new float[4][]; for (int c = 0; c < 4; c++) ch[c] = new float[n];
        for (int i = 0; i < n; i++) {
            if (bpp == 16) { int v = d[off + i * 2] | (d[off + i * 2 + 1] << 8); ch[0][i] = ((v >> 10) & 31) * 255f / 31; ch[1][i] = ((v >> 5) & 31) * 255f / 31; ch[2][i] = (v & 31) * 255f / 31; ch[3][i] = (v >> 15) * 255f; }
            else { ch[0][i] = d[off + i * 4 + 2]; ch[1][i] = d[off + i * 4 + 1]; ch[2][i] = d[off + i * 4]; ch[3][i] = d[off + i * 4 + 3]; }
        }
        float[][] r = new float[4][]; for (int c = 0; c < 4; c++) r[c] = Resize(ch[c], w, h, W, H);
        byte[] o = new byte[off + W * H * bp]; Array.Copy(d, o, off);
        o[12] = (byte)(W & 255); o[13] = (byte)(W >> 8); o[14] = (byte)(H & 255); o[15] = (byte)(H >> 8);
        for (int i = 0; i < W * H; i++) {
            if (bpp == 16) { int v = (Cl(r[0][i] * 31 / 255, 31) << 10) | (Cl(r[1][i] * 31 / 255, 31) << 5) | Cl(r[2][i] * 31 / 255, 31) | (r[3][i] >= 128 ? 0x8000 : 0); o[off + i * 2] = (byte)(v & 255); o[off + i * 2 + 1] = (byte)(v >> 8); }
            else { o[off + i * 4] = (byte)Cl(r[2][i], 255); o[off + i * 4 + 1] = (byte)Cl(r[1][i], 255); o[off + i * 4 + 2] = (byte)Cl(r[0][i], 255); o[off + i * 4 + 3] = (byte)Cl(r[3][i], 255); }
        }
        File.WriteAllBytes(dst, o); return true;
    }
}
"@

function Set-UiScale($gameDir, $k) {
    # $k <= 1 (or -UiScale not given): the originals are put back. The scaled sprites are always made from the saved copies in IMAGES\_orig
    $img = Join-Path $gameDir "RESOURCE\IMAGES"; $bak = Join-Path $img "_orig"
    $n = 0
    foreach ($d in $UiDirs) {
        $dir = Join-Path $img $d; $o = Join-Path $bak $d
        if (-not (Test-Path $dir)) { continue }
        if (-not (Test-Path $o)) { if ($k -le 1) { continue }; New-Item $bak -ItemType Directory -Force | Out-Null; Copy-Item $dir $o -Recurse }
        foreach ($f in Get-ChildItem $o -Recurse -Filter *.tga) {
            $to = Join-Path $dir $f.FullName.Substring($o.Length + 1)
            if ($k -le 1 -or -not [TgaScale]::Scale($f.FullName, $to, $k)) { Copy-Item $f.FullName $to -Force } else { $n++ }
        }
    }
    # fonts of the menus: "name,N" is scaled in its own way (huge text), "name,N,0" by the multiplier of fonts.ini
    $enc = [Text.Encoding]::GetEncoding(1251)
    foreach ($n2 in $UiInis) {
        $p = Join-Path $gameDir "RESOURCE\INI\$n2"
        if (-not (Test-Path $p)) { continue }
        Save-Original $p
        if ($k -le 1) { Copy-Item "$p.orig" $p -Force; continue }
        $sec = ""
        $lines = [IO.File]::ReadAllLines("$p.orig", $enc) | ForEach-Object {
            if ($_ -match '^\[(\w+)\]') { $sec = $Matches[1] }
            $l = $_ -replace '(font:"\w+,\d+)"', '${1},0"'
            # the text of a message box: its size is in pixels of the render (not virtual 800x600), the font is wider than the other fonts of the menu
            if ($sec -eq "MessageBox" -and $l -match '^EditText') {
                $l = [regex]::Replace($l, '\b(dx|dy):(\d+)', { param($m) $m.Groups[1].Value + ":" + [int]([int]$m.Groups[2].Value * $k) })
                $l = [regex]::Replace($l, '(font:"\w+,)(\d+)', { param($m) $m.Groups[1].Value + [int]([int]$m.Groups[2].Value * 1.5) })
            }
            $l
        }
        [IO.File]::WriteAllLines($p, $lines, $enc)
    }
    Write-Host "ui: $n sprites x$k"
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
    Set-UiScale $GameDir 1
    foreach ($p in @($dll, $ini, (Join-Path $GameDir "RESOURCE\INI\fonts.ini"), (Join-Path $GameDir "RESOURCE\INI\controls.ini"))) {
        if (Test-Path "$p.orig") { Move-Item "$p.orig" $p -Force; Write-Host "restored $(Split-Path -Leaf $p)" }
        elseif ($p -eq $dll -and (Test-Path $p)) { Remove-Item $p; Write-Host "removed ddraw.dll" }
    }
    return
}

# dgVoodoo2 (dgvoodoo.ps1) keeps its own ddraw.dll and the DDrawCompat copy as ddraw.dll.ddc: DDrawCompat is not put over it
if (-not (Test-Path (Join-Path $GameDir "ddraw.dll.ddc"))) {
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
# a running game holds ddraw.dll: the same file is not copied again (the settings window can be saved while the game is open)
if (-not (Test-Path $dll) -or (Get-FileHash $dll).Hash -ne (Get-FileHash $new).Hash) { Copy-Item $new $dll -Force }
Copy-Item (Join-Path $Here "DDrawCompat.ini") (Join-Path $GameDir "DDrawCompat.ini") -Force
}

if (-not $Width -or -not $Height) {
    $v = Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
    $Width = if ($v) { [int]$v.CurrentHorizontalResolution } else { 1280 }
    $Height = if ($v) { [int]$v.CurrentVerticalResolution } else { 960 }
    if ($Windowed) { $Width = 1024; $Height = 768 }   # a window with a title bar has to fit the screen
}
if ($Supersample -gt 1) {
    $k = $Supersample
    $Width = [int]([Math]::Round($Width * $k / 2) * 2); $Height = [int]([Math]::Round($Height * $k / 2) * 2)
    # the resolution has to be in the list of DDrawCompat, otherwise the game does not get it
    $dd = Join-Path $GameDir "DDrawCompat.ini"; $res = "${Width}x$Height"
    $t = [IO.File]::ReadAllText($dd)
    if ($t -match "(?m)^SupportedResolutions=(.*)$" -and $Matches[1] -notmatch "\b$res\b") { [IO.File]::WriteAllText($dd, ($t -replace "(?m)^(SupportedResolutions=.*)$", "`$1, $res")) }
}
Save-Original $ini
Set-IniKey $ini "BPP" 16   # the game is 16-bit; DDrawCompat.ini (DesktopColorDepth=16) keeps it so on a 32-bit desktop
Set-IniKey $ini "WINDOW_WIDTH" $Width
Set-IniKey $ini "WINDOW_HEIGHT" $Height
Set-IniKey $ini "WINDOW_MODE" ($(if ($Windowed) { 1 } else { 0 }))
if (-not $FontScale -and $UiScale -and $Supersample -gt 1) { $FontScale = [Math]::Round($Width / 800.0, 1) }   # the sprites of the menu grow with the render: 800 virtual pixels = the whole width
if (-not $FontScale) { $FontScale = [Math]::Max(1.0, [Math]::Floor($Height / 96.0 + 0.5) / 10.0) }
$fonts = Join-Path $GameDir "RESOURCE\INI\fonts.ini"
Save-Original $fonts
Set-FontScale $fonts $FontScale
Write-Host "fonts x$FontScale"
Set-UiScale $GameDir ($(if ($UiScale -and $Supersample -gt 1) { $FontScale } else { 1 }))
$ctl = Join-Path $GameDir "RESOURCE\INI\controls.ini"
Save-Original $ctl
Set-Walk $ctl ([bool]$Wasd)
if ($Wasd) { Write-Host "walking: W A S D" }
# the settings window next to the game (the repository folder can be deleted) and a shortcut on the desktop
$tools = Join-Path $GameDir "fix"
if ($Here -ne $tools) {
    New-Item $tools -ItemType Directory -Force | Out-Null
    foreach ($n in "install.ps1", "settings.ps1", "capture.ps1", "overlay.bin", "play.ps1", "play.vbs", "settings.vbs", "profile.ps1", "DDrawCompat.ini") { Copy-Item (Join-Path $Here $n) $tools -Force }
}
$lnk = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Корсары - настройки.lnk"
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$sc.TargetPath = "wscript.exe"; $sc.Arguments = "`"$(Join-Path $tools "settings.vbs")`""; $sc.WorkingDirectory = $tools
$sc.IconLocation = (Join-Path $GameDir "ENGINE.exe") + ",0"; $sc.Save()
$lnk2 = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Корсары - игра (F8 F9 FPS).lnk"
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk2)
$sc.TargetPath = "wscript.exe"; $sc.Arguments = "`"$(Join-Path $tools "play.vbs")`""; $sc.WorkingDirectory = $tools
$sc.IconLocation = (Join-Path $GameDir "ENGINE.exe") + ",0"; $sc.Save()
$lnk3 = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Корсары - игра (минимум задержки).lnk"
$sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk3)
$sc.TargetPath = "wscript.exe"; $sc.Arguments = "`"$(Join-Path $tools "play.vbs")`" lowlag"; $sc.WorkingDirectory = $tools
$sc.IconLocation = (Join-Path $GameDir "ENGINE.exe") + ",0"; $sc.Save()
Write-Host "settings: $tools\settings.vbs, shortcut on the desktop"
Write-Host "done: DDrawCompat $DdVersion, engine.ini BPP 16, $Width x $Height" ($(if ($Windowed) { "windowed" } else { "fullscreen" }))
