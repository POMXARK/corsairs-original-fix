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
    [switch]$ShowFps,   # the number in the corner of the screen
    [int]$HookMode = 2,   # 2 = the hook; 1 = only the memory and the code, 3 = the hook without stopping the threads (tests)
    [switch]$NoHook     # no overlay.bin in the game: the counter and the messages are windows on top (they are seen for a frame only)
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

Add-Type @"
using System; using System.Diagnostics; using System.Runtime.InteropServices;
// puts overlay.bin into the process of the game and points the flip of the screen at it (overlay/overlay.c); the strings it draws are poked into the data page
public static class GameHook {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr addr, UIntPtr size, uint type, uint prot);
    [DllImport("kernel32.dll")] static extern bool VirtualProtectEx(IntPtr p, IntPtr addr, UIntPtr size, uint prot, out uint old);
    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr p, IntPtr addr, byte[] buf, int size, out int done);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr p, IntPtr addr, byte[] buf, int size, out int done);
    [DllImport("kernel32.dll")] static extern bool FlushInstructionCache(IntPtr p, IntPtr addr, UIntPtr size);
    [DllImport("kernel32.dll")] static extern IntPtr OpenThread(uint access, bool inherit, int tid);
    [DllImport("kernel32.dll")] static extern uint SuspendThread(IntPtr t);
    [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr t);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    const int Data = 0x7E000000, Code = 0x7E001000, Site = 0x420C0A;   // the call of FUN_0040a2a0 (end of the frame) in Realize_Layers: E8 91 96 FE FF
    static IntPtr proc;
    public static string Install(int pid, byte[] code, int mode) {
        proc = OpenProcess(0x38, false, pid);   // VM operation, read, write
        if (proc == IntPtr.Zero) return "OpenProcess failed: " + Marshal.GetLastWin32Error();
        byte[] site = new byte[5]; int n;
        if (!ReadProcessMemory(proc, (IntPtr)Site, site, 5, out n) || site[0] != 0xE8) return "ENGINE.exe is not the expected one at the flip";
        int want = Code - (Site + 5);
        int now = BitConverter.ToInt32(site, 1);
        if (now == want) return "";   // already hooked
        if (now != unchecked((int)0xFFFE9691)) return "ENGINE.exe is not the expected one at the flip";
        IntPtr mem = VirtualAllocEx(proc, (IntPtr)Data, (UIntPtr)0x2000, 0x3000, 0x40);
        if (mem != (IntPtr)Data) return "no room at 0x7E000000";
        if (!WriteProcessMemory(proc, (IntPtr)Code, code, code.Length, out n)) return "code not written";
        if (mode == 1) return "";   // memory and code only, the call is not patched (a test)
        var threads = new System.Collections.Generic.List<IntPtr>();
        try {
            if (mode != 3) foreach (ProcessThread t in Process.GetProcessById(pid).Threads) { IntPtr h = OpenThread(0x2, false, t.Id); if (h != IntPtr.Zero) { SuspendThread(h); threads.Add(h); } }
            uint old;
            VirtualProtectEx(proc, (IntPtr)(Site + 1), (UIntPtr)4, 0x40, out old);
            bool ok = WriteProcessMemory(proc, (IntPtr)(Site + 1), BitConverter.GetBytes(want), 4, out n);
            VirtualProtectEx(proc, (IntPtr)(Site + 1), (UIntPtr)4, old, out old);
            FlushInstructionCache(proc, (IntPtr)Site, (UIntPtr)5);
            if (!ok) return "the call is not patched";
        } finally { foreach (IntPtr h in threads) { ResumeThread(h); CloseHandle(h); } }
        return "";
    }
    public static int Peek(int offset) { byte[] b = new byte[4]; int n; if (proc == IntPtr.Zero || !ReadProcessMemory(proc, (IntPtr)(Data + offset), b, 4, out n)) return -1; return BitConverter.ToInt32(b, 0); }
    public static bool Poke(int offset, byte[] data) { int n; return proc != IntPtr.Zero && WriteProcessMemory(proc, (IntPtr)(Data + offset), data, data.Length, out n); }
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
        foreach ($m in [regex]::Matches($l, "(x|y|size)=([0-9.]+)")) { $Osd[$m.Groups[1].Value] = [double]::Parse($m.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture) }   # also "x=1 y=0" on one line
    }
}

function Log($text) { Add-Content $FpsLog ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $text) -Encoding UTF8 }

# in the game (overlay.bin hooked into ENGINE.exe) when it is there, else in a window on top
$script:hooked = $false
$script:hookLive = $false   # the debug font draws only when the gameplay frames come through the hook
function Poke-Text($offset, $size, $text, [switch]$Raw) {
    $b = New-Object byte[] $size
    if (-not $Raw) { $text = $text.Replace("%", "%%") }
    $a = [Text.Encoding]::ASCII.GetBytes($text)   # the text function of the engine is a printf: a lone % reads arguments that are not there and hangs the game
    [Array]::Copy($a, $b, [Math]::Min($a.Length, $size - 1))
    [void][GameHook]::Poke($offset, $b)
}
$script:osdN = 0; $script:fpsText = ""; $script:msgText = ""; $script:msgPos = 0, 24
$script:fpsShown = $true   # F10 shows and hides the counter
function Show-Fps($text) {
    if (-not $script:fpsShown) { $text = "" }
    $script:fpsText = $text
    if ($text -and (++$script:osdN % 5 -eq 0) -and -not $NoFpsLog) { Log "osd: $text" }
    if ($script:hooked) { if ($script:hookLive) { Poke-Text 0x10 48 $text } }
    elseif ($overlay) { $overlay.Text1.Text = $(if ($text) { $text } else { " " }) }
}

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

Add-Type @"
using System; using System.Collections.Concurrent; using System.Diagnostics;
// keeps every line that PresentMon writes (one per frame, hundreds a second): reading them one by one from the script loses most of them
public class FpsPipe {
    public ConcurrentQueue<string> Q = new ConcurrentQueue<string>();
    public void Attach(Process p) { p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) Q.Enqueue(e.Data); }; p.BeginOutputReadLine(); }
}
"@

# PresentMon writes a row of CSV per presented frame to its stdout (a file it writes is locked against reading)
function Start-Fps($game) {
    $psi = New-Object Diagnostics.ProcessStartInfo (Get-PresentMon)
    $psi.Arguments = "--process_id $($game.Id) --output_stdout --stop_existing_session --terminate_on_proc_exit --no_console_stats"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
    $p = [Diagnostics.Process]::Start($psi)
    $pipe = New-Object FpsPipe; $pipe.Attach($p)
    return @{ Proc = $p; Pipe = $pipe; Col = -1; Acc = (New-Object Collections.Generic.List[double]); N = 0 }
}

# FPS: what DDrawCompat presents (PresentMon), GAME: frames per second that pass through the code of the engine (the hook counts them), CPU: the share of one core
$script:dbg = @{ Frames = -1; At = [datetime]::Now; Cpu = [TimeSpan]::Zero }
function Debug-Line($pres) {
    $now = [datetime]::Now; $dt = ($now - $dbg.At).TotalSeconds
    $gf = -1.0
    if ($hooked) { $fr = [GameHook]::Peek(0x7C); if ($dbg.Frames -ge 0 -and $fr -ge $dbg.Frames -and $dt -gt 0) { $gf = ($fr - $dbg.Frames) / $dt }; $dbg.Frames = $fr }
    $cpu = -1
    try { $gameProc.Refresh(); $t = $gameProc.TotalProcessorTime; if ($dt -gt 0) { $cpu = [int](100 * ($t - $dbg.Cpu).TotalSeconds / $dt) }; $dbg.Cpu = $t } catch { }
    $dbg.At = $now
    $line = ("FPS {0:0}" -f $pres)
    if ($gf -ge 0) { $line += (" | GAME {0:0} ({1:0}ms)" -f $gf, $(if ($gf -gt 0) { 1000 / $gf } else { 0 })) }
    if ($cpu -ge 0) { $line += (" | CPU {0}" -f $cpu) }
    return $line
}

function Read-Fps($s) {
    $ms = New-Object Collections.Generic.List[double]
    $line = $null
    while ($s.Pipe.Q.TryDequeue([ref]$line)) {
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
        Show-Fps (Debug-Line (1000 * $ms.Count / $one))
    } else { Show-Fps (Debug-Line 0) }
    if ($s.N % 5 -eq 0 -and $s.Acc.Count -gt 0) {
        $ms = $s.Acc; $s.Acc = New-Object Collections.Generic.List[double]
        $sum = 0.0; foreach ($x in $ms) { $sum += $x }
        $sorted = $ms.ToArray(); [Array]::Sort($sorted)
        $worst = $sorted[[Math]::Max(0, [int][Math]::Ceiling($sorted.Count * 0.99) - 1)]   # 99th percentile: the 1 % lows
        $slow = 0; foreach ($x in $ms) { if ($x -gt 50) { $slow++ } }   # stutters: frames longer than 50 ms
        if (-not $NoFpsLog) { Log ("fps avg {0:0.0} min {1:0.0} 1%low {2:0.0} frames {3} stutters>50ms {4} worst {5:0}ms" -f (1000 * $ms.Count / $sum), (1000 / $sorted[-1]), (1000 / $worst), $ms.Count, $slow, $sorted[-1]) }
    }
}

$game = Wait-Game
$gameProc = $game
Log "game started (pid $($game.Id)); F8 screenshot, F9 video, F10 fps on/off, fps every 5 s, on screen: $ShowFps"
$fps = $null
if (-not $NoFps -and ($ShowFps -or -not $NoFpsLog)) {
    try { $fps = Start-Fps $game } catch { Log "fps: PresentMon did not start: $($_.Exception.Message)" }
}
$overlay = $null
$binFile = Join-Path $PSScriptRoot "overlay.bin"
if (-not $NoHook -and (Test-Path $binFile)) {
    $err = [GameHook]::Install($game.Id, [IO.File]::ReadAllBytes($binFile), $HookMode)
    if ($err) { Log "hook: $err (windows on top are used)" }
    else {
        $hooked = $true
        $script:scr = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $px = [int]($Osd.x * ($scr.Width - 10 * 40)); $py = [int]($Osd.y * ($scr.Height - 20))
        $script:fpsPos = $px, $py
        [void][GameHook]::Poke(0, [BitConverter]::GetBytes($px) + [BitConverter]::GetBytes($py))
        Log "hook: drawing inside the game, counter at $px,$py"
    }
}
$toast = New-Object Toast
$toastUntil = [datetime]::MinValue
function Notify($text, $color, $seconds, $ascii) {
    $script:toastUntil = (Get-Date).AddSeconds($seconds)
    if ($hooked) {
        if ($hookLive) {
            $w = [Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
            $script:msgText = $ascii; $script:msgPos = [int](($w - 8 * $ascii.Length) / 2), 24
            [void][GameHook]::Poke(8, [BitConverter]::GetBytes($msgPos[0]) + [BitConverter]::GetBytes($msgPos[1]))
            Poke-Text 0x40 60 $ascii
        }
        return
    }
    $toast.Text1.ForeColor = $color; $toast.Text1.Text = $text
    if (-not $toast.Visible) { $toast.Show() }
    $toast.Raise()
}
if ($ShowFps -and -not $hooked) { $overlay = New-Object FpsOverlay($Osd.x, $Osd.y, [int]$Osd.size); $overlay.Show(); Log "overlay at $($overlay.Left),$($overlay.Top) size $($overlay.Width)x$($overlay.Height) from osd.ini x=$($Osd.x) y=$($Osd.y)" }
$video = $null; $f8 = $false; $f9 = $false; $f10 = $false; $tick = 0
while (-not $game.HasExited) {
    Start-Sleep -Milliseconds 100
    $tick++
    $owner = [uint32]0
    [void][CapNative]::GetWindowThreadProcessId([CapNative]::GetForegroundWindow(), [ref]$owner)
    $focus = ($owner -eq $game.Id)   # the keys count only while the game is the window in front
    $d8 = $focus -and (([CapNative]::GetAsyncKeyState(0x77) -band 0x8000) -ne 0)
    $d9 = $focus -and (([CapNative]::GetAsyncKeyState(0x78) -band 0x8000) -ne 0)
    if ($d8 -and -not $f8) {
        try { $n = Join-Path $Shots ("{0:yyyy-MM-dd_HH-mm-ss}.jpg" -f (Get-Date)); Save-Screenshot $n; Log "screenshot $n"; Notify "Скриншот сохранён" ([Drawing.Color]::Lime) 2 "SCREENSHOT SAVED" }
        catch { Log "screenshot failed: $($_.Exception.Message)"; Notify "Скриншот не удался" ([Drawing.Color]::Red) 3 "SCREENSHOT FAILED" }
    }
    if ($d9 -and -not $f9 -and -not $NoVideo) {
        try {
            if ($video) { Stop-Video $video; $video = $null; Log "video ended"; Notify "Запись сохранена" ([Drawing.Color]::Lime) 3 "RECORDING SAVED" }
            else { $n = Join-Path $Shots ("{0:yyyy-MM-dd_HH-mm-ss}.mp4" -f (Get-Date)); $video = Start-Video $n; Log "video $n"; Notify "● Запись началась (F9 - стоп)" ([Drawing.Color]::Red) 3 "RECORDING (F9 - STOP)" }
        } catch { Log "video failed: $($_.Exception.Message)"; Notify "Запись не удалась" ([Drawing.Color]::Red) 3 "RECORDING FAILED" }
    }
    $d10 = $focus -and (([CapNative]::GetAsyncKeyState(0x79) -band 0x8000) -ne 0)
    if ($d10 -and -not $f10) { $fpsShown = -not $fpsShown; Log "fps counter $(if ($fpsShown) { 'on' } else { 'off' })"; if (-not $fpsShown) { Show-Fps "" } }
    $f8 = $d8; $f9 = $d9; $f10 = $d10
    [Windows.Forms.Application]::DoEvents()
    if ($hooked) { if ($toastUntil -ne [datetime]::MinValue -and (Get-Date) -gt $toastUntil) { Poke-Text 0x40 60 ""; $msgText = ""; $toastUntil = [datetime]::MinValue } }
    elseif ($toast.Visible) { if ((Get-Date) -gt $toastUntil) { $toast.Hide() } elseif ($tick % 10 -eq 0) { $toast.Raise() } }
    if ($overlay) { if ($tick % 10 -eq 0) { $overlay.Raise() }; if ($tick % 300 -eq 20) { Log ("overlay: " + $overlay.Where([uint32]$game.Id)) } }
    if ($hooked -and $hookLive -and $tick % 5 -eq 0) {   # something in the game zeroes the page now and then: the strings are written again
        [void][GameHook]::Poke(0, [BitConverter]::GetBytes([int]$fpsPos[0]) + [BitConverter]::GetBytes([int]$fpsPos[1]) + [BitConverter]::GetBytes([int]$msgPos[0]) + [BitConverter]::GetBytes([int]$msgPos[1]))
        Poke-Text 0x10 48 $fpsText
        Poke-Text 0x40 60 $msgText
        $gx = [Math]::Max(0, [int]($scr.Width - 490)); $gy = [Math]::Max(0, [int]$fpsPos[1] - 200)   # the frame-time graph above the counter
        [void][GameHook]::Poke(0x80, [BitConverter]::GetBytes([int]$(if ($fpsShown) { 1 } else { 0 })) + [BitConverter]::GetBytes($gx) + [BitConverter]::GetBytes($gy))
        Poke-Text 0x400 32 "Framerate %d FPS" -Raw; Poke-Text 0x420 32 "Frametime %d.%d ms" -Raw   # formats of the engine text function (a printf), the numbers come from the hook
        Poke-Text 0x440 32 "1%% low  %d FPS" -Raw; Poke-Text 0x460 32 "0.1%% low %d FPS" -Raw; Poke-Text 0x480 32 "%d ms" -Raw
    }
    if ($hooked -and $tick % 10 -eq 5) {
        $fr = [GameHook]::Peek(0x7C)
        if (-not $hookLive -and $fr -ge 100) { $hookLive = $true; Log "hook: gameplay frames reached, text on" }   # no text on the loading screens
        if ($tick % 50 -eq 5) { Log ("hook: frames {0}, game responding {1}" -f $fr, $game.Responding) }
    }
    if ($fps -and $tick % 10 -eq 0) { try { Read-Fps $fps } catch { Log "fps: $($_.Exception.Message)" } }
}
Stop-Video $video
$toast.Close()
if ($overlay) { $overlay.Close() }
if ($fps -and -not $fps.Proc.HasExited) { $fps.Proc.Kill() }
Log "game ended"
