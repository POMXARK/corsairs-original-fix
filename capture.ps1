<#
Screenshots, screen recording and an FPS log for the original game, as F8 / F9 and show_fps of the new engine.
Runs next to the game and ends with it (play.cmd starts both):

  F8   a screenshot to Documents\My Games\Sea Dogs\Screenshots\<date>.jpg
  F9   a video to Screenshots\<date>.mp4 (ffmpeg, the desktop 30 fps, no sound); F9 again ends it
  FPS  (-ShowFps: the number in the top left corner, as show_fps of the new engine) every 5 s a line of Documents\My Games\Sea Dogs\Logs\fps.log (PresentMon, the frames that DDrawCompat presents)

PresentMon (MIT) and ffmpeg (GPL, a build of gyan.dev) are downloaded once to <game>\fix\tools, the versions and
SHA-256 are pinned below. PresentMon watches the process through ETW and needs the rights of an administrator.
#>
param(
    [Parameter(Mandatory)][string]$GameDir,
    [switch]$NoVideo,
    [switch]$NoFps,
    [switch]$NoFpsLog,  # no fps.log lines (the screenshot and video lines stay)
    [switch]$ShowFps    # the number in the corner of the screen
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

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System; using System.Drawing; using System.Windows.Forms;
// a window on top of the game that the mouse and the keys pass through and that never takes the focus
public class FpsOverlay : Form {
    public Label Text1 = new Label();
    public FpsOverlay(double x, double y, int size) {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
        var scr = Screen.PrimaryScreen.Bounds;
        Size = new Size((int)(size * 5), (int)(size * 1.7)); BackColor = Color.Black; Opacity = 0.65;
        Location = new Point(scr.X + (int)(x * (scr.Width - Width)), scr.Y + (int)(y * (scr.Height - Height)));
        Text1.ForeColor = Color.Lime; Text1.Font = new Font("Consolas", size, FontStyle.Bold, GraphicsUnit.Pixel); Text1.TextAlign = ContentAlignment.MiddleCenter; Text1.Dock = DockStyle.Fill; Text1.Text = "FPS --";
        Controls.Add(Text1);
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    // the window of the game can come up after this one and cover it: put it on top again (topmost, no move, no size, no activate, show)
    public void Raise() { SetWindowPos(Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 | 0x0040); }
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out Rectangle r);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
    delegate bool EnumProc(IntPtr h, IntPtr l);
    // for the log: where the windows of this process and of the game stand in the z-order (1 = the top), their rectangles and extended styles
    public string Where(uint game) {
        var sb = new System.Text.StringBuilder(); int z = 0; uint me = (uint)System.Diagnostics.Process.GetCurrentProcess().Id; IntPtr self = Handle;
        EnumWindows((h, l) => {
            z++; uint p; GetWindowThreadProcessId(h, out p);
            if ((h == self || p == game) && IsWindowVisible(h)) { Rectangle r = new Rectangle(); GetWindowRect(h, out r);
                sb.AppendFormat("[{0} z={1} ltrb={2},{3},{4},{5} ex=0x{6:X}] ", h == self ? "overlay" : "game", z, r.X, r.Y, r.Width, r.Height, GetWindowLong(h, -20)); }
            return true; }, IntPtr.Zero);
        return sb.ToString() + "visible=" + Visible;
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x80 | 0x20 | 0x08000000 | 0x80000; return p; } } // toolwindow, transparent to input, no activate, layered
}
"@
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System; using System.Drawing; using System.Windows.Forms;
// a message in the top middle of the screen (a screenshot is saved, a video begins or ends): like the counter, it never takes the focus
public class Toast : Form {
    public Label Text1 = new Label();
    public Toast() {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
        Size = new Size(320, 40); BackColor = Color.Black; Opacity = 0.8;
        var scr = Screen.PrimaryScreen.Bounds;
        Location = new Point(scr.X + (scr.Width - Width) / 2, scr.Y + 24);
        Text1.Font = new Font("Segoe UI", 18, FontStyle.Bold, GraphicsUnit.Pixel); Text1.TextAlign = ContentAlignment.MiddleCenter; Text1.Dock = DockStyle.Fill;
        Controls.Add(Text1);
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public void Raise() { SetWindowPos(Handle, (IntPtr)(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 | 0x0040); }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x80 | 0x20 | 0x08000000 | 0x80000; return p; } }
}
"@

# fix\osd.ini of the settings window: where the counter stands (0..1 over the free room of the screen) and the size of its letters
$Osd = @{ x = 0.0; y = 0.0; size = 14 }
$osdFile = Join-Path $PSScriptRoot "osd.ini"
if (Test-Path $osdFile) {
    foreach ($l in [IO.File]::ReadAllLines($osdFile)) {
        if ($l -match "^(x|y|size)=([0-9.]+)$") { $Osd[$Matches[1]] = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture) }
    }
}

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

# PresentMon writes a row of CSV per presented frame to its stdout (a file it writes is locked against reading)
function Start-Fps($game) {
    $psi = New-Object Diagnostics.ProcessStartInfo (Get-PresentMon)
    $psi.Arguments = "--process_id $($game.Id) --output_stdout --stop_existing_session --terminate_on_proc_exit --no_console_stats"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
    $p = [Diagnostics.Process]::Start($psi)
    return @{ Proc = $p; Task = $p.StandardOutput.ReadLineAsync(); Col = -1; Acc = (New-Object Collections.Generic.List[double]); N = 0 }
}

function Read-Fps($s) {
    $ms = New-Object Collections.Generic.List[double]
    while ($s.Task.IsCompleted) {
        $line = $s.Task.Result
        if ($null -eq $line) { break }   # PresentMon has ended
        $s.Task = $s.Proc.StandardOutput.ReadLineAsync()
        $f = $line.Split(",")
        if ($s.Col -lt 0) {
            foreach ($n in "MsBetweenPresents", "FrameTime") { $i = [Array]::IndexOf($f, $n); if ($i -ge 0) { $s.Col = $i; break } }
            if ($s.Col -lt 0) { Log "fps: no frame-time column in $line"; $s.Col = 9999 }
            continue
        }
        $v = 0.0
        if ($f.Count -gt $s.Col -and [double]::TryParse($f[$s.Col], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -gt 0) { $ms.Add($v) }
    }
    $s.N++
    if ($ms.Count -gt 0) {
        $s.Acc.AddRange($ms)
        $one = 0.0; foreach ($x in $ms) { $one += $x }
        if ($overlay) { $overlay.Text1.Text = "FPS {0:0}" -f (1000 * $ms.Count / $one) }
    } elseif ($overlay) { $overlay.Text1.Text = "FPS 0" }
    if ($s.N % 5 -eq 0 -and $s.Acc.Count -gt 0) {
        $ms = $s.Acc; $s.Acc = New-Object Collections.Generic.List[double]
        $sum = 0.0; foreach ($x in $ms) { $sum += $x }
        $sorted = $ms.ToArray(); [Array]::Sort($sorted)
        $worst = $sorted[[Math]::Max(0, [int][Math]::Ceiling($sorted.Count * 0.99) - 1)]   # 99th percentile: the 1 % lows
        if (-not $NoFpsLog) { Log ("fps avg {0:0.0} min {1:0.0} 1%low {2:0.0} frames {3}" -f (1000 * $ms.Count / $sum), (1000 / $sorted[-1]), (1000 / $worst), $ms.Count) }
    }
}

$game = Wait-Game
Log "game started (pid $($game.Id)); F8 screenshot, F9 video, fps every 5 s, on screen: $ShowFps"
$fps = $null
if (-not $NoFps -and ($ShowFps -or -not $NoFpsLog)) {
    try { $fps = Start-Fps $game } catch { Log "fps: PresentMon did not start: $($_.Exception.Message)" }
}
$overlay = $null
$toast = New-Object Toast
$toastUntil = [datetime]::MinValue
function Notify($text, $color, $seconds) {
    $toast.Text1.ForeColor = $color; $toast.Text1.Text = $text
    $script:toastUntil = (Get-Date).AddSeconds($seconds)
    if (-not $toast.Visible) { $toast.Show() }
    $toast.Raise()
}
if ($ShowFps) { $overlay = New-Object FpsOverlay($Osd.x, $Osd.y, [int]$Osd.size); $overlay.Show(); Log "overlay at $($overlay.Left),$($overlay.Top) size $($overlay.Width)x$($overlay.Height) from osd.ini x=$($Osd.x) y=$($Osd.y)" }
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
        try { $n = Join-Path $Shots ("{0:yyyy-MM-dd_HH-mm-ss}.jpg" -f (Get-Date)); Save-Screenshot $n; Log "screenshot $n"; Notify "Скриншот сохранён" ([Drawing.Color]::Lime) 2 }
        catch { Log "screenshot failed: $($_.Exception.Message)"; Notify "Скриншот не удался" ([Drawing.Color]::Red) 3 }
    }
    if ($d9 -and -not $f9 -and -not $NoVideo) {
        try {
            if ($video) { Stop-Video $video; $video = $null; Log "video ended"; Notify "Запись сохранена" ([Drawing.Color]::Lime) 3 }
            else { $n = Join-Path $Shots ("{0:yyyy-MM-dd_HH-mm-ss}.mp4" -f (Get-Date)); $video = Start-Video $n; Log "video $n"; Notify "● Запись началась (F9 - стоп)" ([Drawing.Color]::Red) 3 }
        } catch { Log "video failed: $($_.Exception.Message)"; Notify "Запись не удалась" ([Drawing.Color]::Red) 3 }
    }
    $f8 = $d8; $f9 = $d9
    [Windows.Forms.Application]::DoEvents()
    if ($toast.Visible) { if ((Get-Date) -gt $toastUntil) { $toast.Hide() } elseif ($tick % 10 -eq 0) { $toast.Raise() } }
    if ($overlay) { if ($tick % 10 -eq 0) { $overlay.Raise() }; if ($tick % 300 -eq 20) { Log ("overlay: " + $overlay.Where([uint32]$game.Id)) } }
    if ($fps -and $tick % 10 -eq 0) { try { Read-Fps $fps } catch { Log "fps: $($_.Exception.Message)" } }
}
Stop-Video $video
$toast.Close()
if ($overlay) { $overlay.Close() }
if ($fps -and -not $fps.Proc.HasExited) { $fps.Proc.Kill() }
Log "game ended"
