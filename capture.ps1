<#
Screenshots, screen recording and an FPS log for the original game, as F8 / F9 and show_fps of the new engine.
Runs next to the game and ends with it (play.cmd starts both):

  F8   a screenshot to Documents\My Games\Sea Dogs\Screenshots\<date>.jpg
  F9   a video to Screenshots\<date>.mp4 (ffmpeg, the desktop 30 fps, no sound); F9 again ends it
  FPS  every 5 s a line of Documents\My Games\Sea Dogs\Logs\fps.log (PresentMon, the frames that DDrawCompat presents)

PresentMon (MIT) and ffmpeg (GPL, a build of gyan.dev) are downloaded once to <game>\fix\tools, the versions and
SHA-256 are pinned below. PresentMon watches the process through ETW and needs the rights of an administrator.
#>
param(
    [Parameter(Mandatory)][string]$GameDir,
    [switch]$NoVideo,
    [switch]$NoFps
)
$ErrorActionPreference = "Stop"
$PmUrl = "https://github.com/GameTechDev/PresentMon/releases/download/v2.6.0/PresentMon-2.6.0-x64.exe"
$PmSha256 = "b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af"
$FfUrl = "https://github.com/GyanD/codexffmpeg/releases/download/2026-10-22-git-bf0e831606/ffmpeg-2026-10-22-git-bf0e831606-essentials_build.zip"
$FfSha256 = "07de5469e123c02e06959cbf7cc9e405c29f0530abde67f0721fe57dfe5e1fb4"
$Tools = Join-Path $GameDir "fix\tools"
$Stash = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\Sea Dogs"
$Shots = Join-Path $Stash "Screenshots"
$Logs = Join-Path $Stash "Logs"
New-Item $Shots, $Logs, $Tools -ItemType Directory -Force | Out-Null
$FpsLog = Join-Path $Logs "fps.log"

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class CapNative {
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@

function Log($text) { Add-Content $FpsLog ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $text) -Encoding UTF8 }

function Get-Tool($file, $url, $sha, [scriptblock]$unpack) {
    $path = Join-Path $Tools $file
    if (Test-Path $path) { return $path }
    $dl = Join-Path $env:TEMP ([IO.Path]::GetFileName($url))
    Invoke-WebRequest $url -OutFile $dl -UseBasicParsing
    if ((Get-FileHash $dl -Algorithm SHA256).Hash -ne $sha.ToUpper()) { Remove-Item $dl; throw "$file : wrong SHA-256, not used" }
    & $unpack $dl $path
    return $path
}

function Get-PresentMon {
    Get-Tool "PresentMon.exe" $PmUrl $PmSha256 { param($dl, $path) Copy-Item $dl $path }
}

function Get-Ffmpeg {
    Get-Tool "ffmpeg.exe" $FfUrl $FfSha256 {
        param($dl, $path)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($dl)
        try {
            $e = $z.Entries | Where-Object { $_.FullName -like "*/bin/ffmpeg.exe" } | Select-Object -First 1
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $path, $true)
        } finally { $z.Dispose() }
    }
}

function Wait-Game {
    while ($true) { $p = Get-Process ENGINE -ErrorAction SilentlyContinue | Select-Object -First 1; if ($p) { return $p }; Start-Sleep -Milliseconds 500 }
}

function Save-Screenshot($name) {
    $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object Drawing.Bitmap($b.Width, $b.Height)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
    $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq "image/jpeg"
    $q = New-Object Drawing.Imaging.EncoderParameters(1)
    $q.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [long]92)
    $bmp.Save($name, $codec, $q)
    $g.Dispose(); $bmp.Dispose()
}

function Start-Video($name) {
    $psi = New-Object Diagnostics.ProcessStartInfo (Get-Ffmpeg)
    $psi.Arguments = "-y -f gdigrab -framerate 30 -draw_mouse 0 -i desktop -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p `"$name`""
    $psi.RedirectStandardInput = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    return [Diagnostics.Process]::Start($psi)
}

function Stop-Video($proc) {
    if (-not $proc -or $proc.HasExited) { return }
    $proc.StandardInput.WriteLine("q"); $proc.StandardInput.Flush()   # ffmpeg ends the file by itself on q
    if (-not $proc.WaitForExit(15000)) { $proc.Kill() }
}

# PresentMon writes a row per presented frame; the CSV of one run is read in its tail
function Start-Fps($game) {
    $csv = Join-Path $env:TEMP "corsairs-presentmon.csv"
    Remove-Item $csv -ErrorAction SilentlyContinue
    $psi = New-Object Diagnostics.ProcessStartInfo (Get-PresentMon)
    $psi.Arguments = "--process_id $($game.Id) --output_file `"$csv`" --stop_existing_session --terminate_on_proc_exit --no_console_stats"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    return @{ Proc = [Diagnostics.Process]::Start($psi); Csv = $csv; Pos = 0L; Col = -1 }
}

function Read-Fps($s) {
    if (-not (Test-Path $s.Csv)) { return }
    $fs = [IO.File]::Open($s.Csv, "Open", "Read", "ReadWrite")
    try {
        $sr = New-Object IO.StreamReader($fs)
        if ($s.Col -lt 0) {
            $head = $sr.ReadLine()
            if (-not $head) { return }
            $cols = $head.Split(",")
            foreach ($n in "MsBetweenPresents", "FrameTime") { $i = [Array]::IndexOf($cols, $n); if ($i -ge 0) { $s.Col = $i; break } }
            if ($s.Col -lt 0) { Log "fps: no frame-time column in $($head)"; $s.Col = 9999; return }
            $s.Pos = $fs.Position
        } else { $fs.Position = $s.Pos; $sr.DiscardBufferedData() }
        $ms = New-Object Collections.Generic.List[double]
        while ($null -ne ($line = $sr.ReadLine())) {
            $f = $line.Split(",")
            $v = 0.0
            if ($f.Count -gt $s.Col -and [double]::TryParse($f[$s.Col], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -gt 0) { $ms.Add($v) }
            $s.Pos += [Text.Encoding]::UTF8.GetByteCount($line) + 2
        }
        if ($ms.Count -gt 0) {
            $sum = 0.0; foreach ($x in $ms) { $sum += $x }
            $sorted = $ms.ToArray(); [Array]::Sort($sorted)
            $worst = $sorted[[Math]::Max(0, [int][Math]::Ceiling($sorted.Count * 0.99) - 1)]   # 99th percentile: the 1 % lows
            Log ("fps avg {0:0.0} min {1:0.0} 1%low {2:0.0} frames {3}" -f (1000 * $ms.Count / $sum), (1000 / $sorted[-1]), (1000 / $worst), $ms.Count)
        }
    } finally { $fs.Dispose() }
}

$game = Wait-Game
Log "game started (pid $($game.Id)); F8 screenshot, F9 video, fps every 5 s"
$fps = $null
if (-not $NoFps) {
    try { $fps = Start-Fps $game } catch { Log "fps: PresentMon did not start: $($_.Exception.Message)" }
}
$video = $null; $f8 = $false; $f9 = $false; $tick = 0
while (-not $game.HasExited) {
    Start-Sleep -Milliseconds 100
    $tick++
    $owner = [uint32]0
    [void][CapNative]::GetWindowThreadProcessId([CapNative]::GetForegroundWindow(), [ref]$owner)
    $focus = ($owner -eq $game.Id)   # the keys count only while the game is the window in front
    $d8 = $focus -and (([CapNative]::GetAsyncKeyState(0x77) -band 0x8000) -ne 0)
    $d9 = $focus -and (([CapNative]::GetAsyncKeyState(0x78) -band 0x8000) -ne 0)
    if ($d8 -and -not $f8) {
        try { $n = Join-Path $Shots ("{0:yyyy-MM-dd_HH-mm-ss}.jpg" -f (Get-Date)); Save-Screenshot $n; Log "screenshot $n" }
        catch { Log "screenshot failed: $($_.Exception.Message)" }
    }
    if ($d9 -and -not $f9 -and -not $NoVideo) {
        try {
            if ($video) { Stop-Video $video; $video = $null; Log "video ended" }
            else { $n = Join-Path $Shots ("{0:yyyy-MM-dd_HH-mm-ss}.mp4" -f (Get-Date)); $video = Start-Video $n; Log "video $n" }
        } catch { Log "video failed: $($_.Exception.Message)" }
    }
    $f8 = $d8; $f9 = $d9
    if ($fps -and $tick % 50 -eq 0) { try { Read-Fps $fps } catch { Log "fps: $($_.Exception.Message)" } }
}
Stop-Video $video
if ($fps -and -not $fps.Proc.HasExited) { $fps.Proc.Kill() }
Log "game ended"
