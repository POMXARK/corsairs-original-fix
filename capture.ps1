<#
Screenshots, screen recording and an FPS log for the original game, as F8 / F9 and show_fps of the new engine.
Runs next to the game and ends with it (play.cmd starts both):

  F8   a screenshot to Documents\My Games\Sea Dogs\Screenshots\<date>.jpg
  F10  the counter and the graph on/off
  F11  the periodic statistics lines of fps.log on/off
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
    [switch]$NoFineTick,    # the frame time stays in steps of 15.6 ms of GetTickCount (docs/frame-time.md)
    [switch]$NoKeyRepeat,   # no repeats of the held keys from the hook (docs/input-latency.md)
    [switch]$NoHook     # no overlay.bin in the game: the counter and the messages are windows on top (they are seen for a frame only)
)
$ErrorActionPreference = "Stop"
# fix.ini next to this script (written by the settings window): the switches of the patches, the logs, the screenshots and the video; the command line only adds "off" switches
$Cfg = @{ keyrepeat = 1; finetick = 0; screenshots = 1; video = 1; fpslog = 1; osd = 1; statlog = 1; frame = 3; skipintro = 1; fpslimit = 0; autotest = 0; testx = 0; testy = 0 }
$cfgFile = Join-Path $PSScriptRoot "fix.ini"
if (Test-Path $cfgFile) { foreach ($l in [IO.File]::ReadAllLines($cfgFile)) { if ($l -match "^\s*(\w+)\s*=\s*(\d+)\s*$" -and $Cfg.ContainsKey($Matches[1])) { $Cfg[$Matches[1]] = [int]$Matches[2] } } }
if (-not $Cfg.keyrepeat) { $NoKeyRepeat = [switch]$true }
if (-not $Cfg.finetick) { $NoFineTick = [switch]$true }
if (-not $Cfg.video) { $NoVideo = [switch]$true }
if (-not $Cfg.fpslog) { $NoFpsLog = [switch]$true }
if ($Cfg.osd) { $ShowFps = [switch]$true }
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
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct PT { public int X, Y; }
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(PT p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr r, IntPtr rgn, uint flags);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int index, IntPtr value);
    [DllImport("user32.dll")] public static extern bool AdjustWindowRectEx(ref RECT r, uint style, bool menu, uint exStyle);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetClipCursor(out RECT r);
    [DllImport("user32.dll")] public static extern bool ClipCursor(ref RECT r);
    [DllImport("user32.dll", EntryPoint = "ClipCursor")] public static extern bool ClipCursorOff(IntPtr none);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId")] static extern uint Tid(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint tid, byte[] info);
    public static string Gui(IntPtr h) { uint p; uint t = Tid(h, out p); int w = IntPtr.Size, n = 8 + 6 * w + 16; byte[] b = new byte[n]; BitConverter.GetBytes(n).CopyTo(b, 0); if (!GetGUIThreadInfo(t, b)) return "?"; return "active " + BitConverter.ToInt64(b, 8) + " focus " + BitConverter.ToInt64(b, 8 + w) + " capture " + BitConverter.ToInt64(b, 8 + 2 * w); }
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public delegate bool EnumCb(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumCb f, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    // every top-level window of a process: handle, class, rectangle, styles (for the log: where DDrawCompat keeps its window)
    public static string Windows(uint pid) {
        var sb = new System.Text.StringBuilder(); int z = 0;
        EnumWindows((h, l) => {
            z++; uint p; GetWindowThreadProcessId(h, out p);
            if (p != pid) return true;
            var c = new System.Text.StringBuilder(64); GetClassNameW(h, c, 64); RECT r; GetWindowRect(h, out r);
            sb.AppendFormat("[{0} {1} z={2} vis={3} {4},{5} {6}x{7} st={8:X} ex={9:X}] ", h, c, z, IsWindowVisible(h), r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top, (long)GetWindowLongPtr(h, -16), (long)GetWindowLongPtr(h, -20));
            return true; }, IntPtr.Zero);
        return sb.ToString();
    }
}
"@

Add-Type @"
using System; using System.Diagnostics; using System.Text; using System.Runtime.InteropServices;
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
    [DllImport("psapi.dll")] static extern bool EnumProcessModulesEx(IntPtr p, IntPtr[] mods, int cb, out int needed, uint filter);
    [DllImport("psapi.dll", CharSet = CharSet.Ansi)] static extern int GetModuleFileNameExA(IntPtr p, IntPtr mod, StringBuilder name, int size);
    const int Data = 0x7E000000, Code = 0x7E001000, Site = 0x420C0A;   // the call of FUN_0040a2a0 (end of the frame) in Realize_Layers: E8 91 96 FE FF
    static IntPtr proc; static int procId;
    public static string Install(int pid, byte[] code, int mode) {
        procId = pid; proc = OpenProcess(0x438, false, pid);   // VM operation, read, write, query information (the modules)
        if (proc == IntPtr.Zero) return "OpenProcess failed: " + Marshal.GetLastWin32Error();
        byte[] site = new byte[5]; int n;
        if (!ReadProcessMemory(proc, (IntPtr)Site, site, 5, out n) || site[0] != 0xE8) return "ENGINE.exe is not the expected one at the flip";
        int want = Code + 0x100 - (Site + 5);   // hook() is at +0x100 of the code, fast_tick() at +0
        int now = BitConverter.ToInt32(site, 1);
        if (now == want) return "";   // already hooked
        if (now != unchecked((int)0xFFFE9691)) return "ENGINE.exe is not the expected one at the flip";
        IntPtr mem = VirtualAllocEx(proc, (IntPtr)Data, (UIntPtr)0x6000, 0x3000, 0x40);
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
    // GetCursorPos of the interface modules (MENU.dll, WS_*.dll, ...) -> cursor_get() (overlay.c): they take the screen for the game, in a moved window the buttons do not react. The modules load later: called again and again, returns how many imports it changed
    public static string Dbg = "";
    public static int CursorFix() {
        int changed = 0, n, mods = 0, withUser = 0, found = 0; Dbg = ""; if (proc == IntPtr.Zero) return 0;
        IntPtr[] ms = new IntPtr[1024]; int need;
        if (!EnumProcessModulesEx(proc, ms, ms.Length * IntPtr.Size, out need, 1)) { Dbg = "EnumProcessModulesEx failed: " + Marshal.GetLastWin32Error(); return 0; }
        for (int k = 0; k < Math.Min(need / IntPtr.Size, ms.Length); k++) {
            StringBuilder fn = new StringBuilder(260); GetModuleFileNameExA(proc, ms[k], fn, 260); string path = fn.ToString();
            if (path.EndsWith("ENGINE.exe", StringComparison.OrdinalIgnoreCase) || path.EndsWith("ddraw.dll", StringComparison.OrdinalIgnoreCase) || path.IndexOf("\\Windows\\", StringComparison.OrdinalIgnoreCase) >= 0) continue;
            mods++; int b = (int)ms[k]; byte[] h = new byte[0x400];
            if (!ReadProcessMemory(proc, (IntPtr)b, h, h.Length, out n) || h[0] != 0x4D) continue;
            int pe = BitConverter.ToInt32(h, 0x3C); if (pe < 0 || pe + 0x88 > h.Length) continue;
            int impRva = BitConverter.ToInt32(h, pe + 0x80); if (impRva == 0) continue;
            for (int d = b + impRva; ; d += 20) {
                byte[] e = new byte[20]; if (!ReadProcessMemory(proc, (IntPtr)d, e, 20, out n)) break;
                int nameRva = BitConverter.ToInt32(e, 12); if (nameRva == 0) break;
                byte[] nm = new byte[16]; ReadProcessMemory(proc, (IntPtr)(b + nameRva), nm, 16, out n);
                if (!Encoding.ASCII.GetString(nm).ToUpperInvariant().StartsWith("USER32")) continue;
                withUser++;
                int oft = BitConverter.ToInt32(e, 0), ft = BitConverter.ToInt32(e, 16); if (oft == 0) oft = ft;
                for (int i = 0; i < 2000; i++) {
                    byte[] t = new byte[4]; if (!ReadProcessMemory(proc, (IntPtr)(b + oft + i * 4), t, 4, out n)) break;
                    int th = BitConverter.ToInt32(t, 0); if (th == 0) break; if (th < 0) continue;
                    byte[] sn = new byte[16]; ReadProcessMemory(proc, (IntPtr)(b + th + 2), sn, 16, out n);
                    if (!Encoding.ASCII.GetString(sn).StartsWith("GetCursorPos\0")) continue;
                    found++; int slot = b + ft + i * 4; byte[] cur = new byte[4]; ReadProcessMemory(proc, (IntPtr)slot, cur, 4, out n);
                    if (BitConverter.ToInt32(cur, 0) == Code + 0x2000) break;
                    if (Redirect(slot, 0xF8, Code + 0x2000)) changed++;
                    break;
                }
            }
        }
        Dbg = "modules " + mods + ", with USER32 imports " + withUser + ", GetCursorPos found " + found; return changed;
    }
    // the import GetTickCount of ENGINE.exe (0x431050, read-only page) -> fast_tick(): the time of the frame in milliseconds, not in steps of 15.6 ms
    public static bool FineTick() {
        const int Iat = 0x431050; uint old; int n;
        if (proc == IntPtr.Zero) return false;
        VirtualProtectEx(proc, (IntPtr)Iat, (UIntPtr)4, 0x04, out old);
        bool ok = WriteProcessMemory(proc, (IntPtr)Iat, BitConverter.GetBytes(Code), 4, out n);
        VirtualProtectEx(proc, (IntPtr)Iat, (UIntPtr)4, old, out old);
        return ok;
    }
    static bool Redirect(int iat, int realAt, int to) {   // the import slot of ENGINE.exe now points at our code, the real address is kept in the data page
        uint old; int n; byte[] cur = new byte[4];
        if (proc == IntPtr.Zero || !ReadProcessMemory(proc, (IntPtr)iat, cur, 4, out n)) return false;
        if (BitConverter.ToInt32(cur, 0) == to) return true;
        if (!Poke(realAt, cur)) return false;
        VirtualProtectEx(proc, (IntPtr)iat, (UIntPtr)4, 0x04, out old);
        bool ok = WriteProcessMemory(proc, (IntPtr)iat, BitConverter.GetBytes(to), 4, out n);
        VirtualProtectEx(proc, (IntPtr)iat, (UIntPtr)4, old, out old);
        return ok;
    }
    // SetCursorPos and MoveWindow of the game get the origin of its window added (overlay.c cursor_fix, move_fix): it takes the window for the screen
    public static bool WindowFix() { return Redirect(0x43119C, 0xC4, Code + 0x80) && Redirect(0x43116C, 0xD0, Code + 0x3000); }
    // the Blt of the primary surface gets the origin of the window added to its rectangle (overlay.c blt_fix): the vtable of that surface is in DDrawCompat, the slot is 0x14
    public static bool BltFix() {
        byte[] b = new byte[4]; int n; uint old;
        if (proc == IntPtr.Zero || !ReadProcessMemory(proc, (IntPtr)0x77DD1C, b, 4, out n)) return false;
        int dev = BitConverter.ToInt32(b, 0); if (dev == 0) return false;
        if (!ReadProcessMemory(proc, (IntPtr)(dev + 0x90168), b, 4, out n)) return false;
        int prim = BitConverter.ToInt32(b, 0); if (prim == 0) return false;
        if (!ReadProcessMemory(proc, (IntPtr)prim, b, 4, out n)) return false;
        int slot = BitConverter.ToInt32(b, 0) + 0x14; if (slot == 0x14) return false;
        if (!ReadProcessMemory(proc, (IntPtr)slot, b, 4, out n)) return false;
        int cur = BitConverter.ToInt32(b, 0), to = Code + 0x1000;
        if (cur == to) return true;
        if (!Poke(0xD8, b)) return false;
        VirtualProtectEx(proc, (IntPtr)slot, (UIntPtr)4, 0x04, out old);
        bool ok = WriteProcessMemory(proc, (IntPtr)slot, BitConverter.GetBytes(to), 4, out n);
        VirtualProtectEx(proc, (IntPtr)slot, (UIntPtr)4, old, out old);
        return ok;
    }
    public static int PeekAbs(int addr) { byte[] b = new byte[4]; int n; if (proc == IntPtr.Zero || !ReadProcessMemory(proc, (IntPtr)addr, b, 4, out n)) return -1; return BitConverter.ToInt32(b, 0); }
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

$script:statLog = [bool]$Cfg.statlog   # F11 stops the periodic statistics lines (osd, fps avg, hook frames); screenshots, videos and errors are still logged
function Log($text) { if (-not $script:statLog -and $text -match "^(osd:|fps avg|hook: frames)") { return }; $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $text
    foreach ($try in 1..5) { try { Add-Content $FpsLog $line -Encoding UTF8; return } catch { Start-Sleep -Milliseconds 40 } }   # the log is open in another program (a reader, an editor): a lost line must not stop the whole script (ErrorActionPreference Stop)
}

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
$script:fpsShown = [bool]$Cfg.osd   # F10 shows and hides the counter
function Show-Fps($text) {
    if (-not $script:fpsShown) { $text = "" }
    $script:fpsText = $text
    if ($text -and (++$script:osdN % 5 -eq 0) -and -not $NoFpsLog) { Log "osd: $text" }
    if ($script:hooked) { if ($script:hookLive) { Poke-Text 0x10 48 $text } }
    elseif ($overlay) { $overlay.Text1.Text = $(if ($text) { $text } else { " " }) }
}

# windowed mode (WINDOW_MODE 1): the game window is not touched (a changed style leaves DDrawCompat drawing a black window): a title strip
# of its own sits above it, the strip is dragged and the game window follows it; at the start both go to the middle of the working area
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System; using System.Windows.Forms;
public class NoActForm : Form {
    protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x08000080; return p; } }   // NOACTIVATE | TOOLWINDOW
    protected override bool ShowWithoutActivation { get { return true; } }
}
"@
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class WinDump {
    delegate bool Cb(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(Cb f, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetLong(IntPtr h, int i);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out Rc r);
    [StructLayout(LayoutKind.Sequential)] struct Rc { public int Left, Top, Right, Bottom; }
    // the visible top-level windows of a process, from the top of the Z order down: what covers what
    public static List<string> Of(uint pid) {
        var o = new List<string>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (!IsWindowVisible(h) || p != pid) return true;
            var c = new StringBuilder(128); GetClassName(h, c, 128); var t = new StringBuilder(128); GetWindowText(h, t, 128);
            Rc r; GetWindowRect(h, out r);
            o.Add(string.Format("{0:X} [{1}] '{2}' {3},{4} {5}x{6} style {7:X} ex {8:X}", (long)h, c, t, r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top, GetLong(h, -16), GetLong(h, -20)));
            return true;
        }, IntPtr.Zero);
        return o;
    }
}
"@
$script:bar = $null; $script:barH = 26; $script:winDumped = $false
$script:cursorFixed = $false
function Set-Pos($x, $y) {
    if (-not $script:cursorFixed -and $hooked) { $script:cursorFixed = [GameHook]::WindowFix(); Log "window fix: $($script:cursorFixed)" }
    if ($script:cursorFixed -and -not $script:bltFixed) { $script:bltFixed = [GameHook]::BltFix(); Log "blt fix: $($script:bltFixed)" }
    if ($script:cursorFixed) { [void][GameHook]::Poke(0xC8, [BitConverter]::GetBytes([int]$x)); [void][GameHook]::Poke(0xCC, [BitConverter]::GetBytes([int]$y)) }
    if ($script:cursorFixed) { [void][GameHook]::Poke(0xD4, [BitConverter]::GetBytes([int]1)); return }   # the game moves itself in its next frame (overlay.c hook): a move from outside freezes the picture of DDrawCompat
    $t0 = Get-Date
    [void][CapNative]::SetWindowPos($game.MainWindowHandle, [IntPtr]::Zero, $x, $y, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010)   # NOSIZE | NOZORDER | NOACTIVATE
    $ms = ((Get-Date) - $t0).TotalMilliseconds
    if ($ms -gt 100) { Log ("window move took {0:N0} ms" -f $ms) }
}   # NOSIZE | NOZORDER | NOACTIVATE
# the logo videos (MCI, DAT_009a3ddc = 1 while one plays): Esc ends it, as it does by hand (ENGINE.exe.c:17981)
$script:escAt = [DateTime]::MinValue; $script:mouseAt = [DateTime]::MinValue; $script:lastMouse = ""
function Skip-Intro {
    if ([GameHook]::PeekAbs(0x9A3DDC) -ne 1 -or ((Get-Date) - $script:escAt).TotalMilliseconds -lt 700) { return }
    $h = $game.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { return }
    $script:escAt = Get-Date
    [void][CapNative]::PostMessage($h, 0x100, [IntPtr]0x1B, [IntPtr]0x00010001); [void][CapNative]::PostMessage($h, 0x101, [IntPtr]0x1B, [IntPtr]0xC0010001)
    Log "intro: Esc"
}
function Set-Frame {
    if ($hookLive -and -not $script:winDumped) {
        if (-not $script:dumpAt) { $script:dumpAt = (Get-Date).AddSeconds(5) }
        elseif ((Get-Date) -gt $script:dumpAt) { $script:winDumped = $true; foreach ($w in [WinDump]::Of([uint32]$game.Id)) { Log "window dump: $w" }; Log ("cursor " + [Windows.Forms.Cursor]::Position + ", strip " + $script:bar.Bounds) }
    }
    if (-not $hookLive) { return }   # the logo videos go to GetWindowRect of the window as if it were the client area: it stays at 0,0 until they are over
    if (-not $script:frameAt) { $script:frameAt = Get-Date }
    if (((Get-Date) - $script:frameAt).TotalSeconds -lt 6) { return }   # the first move waits until DDrawCompat has settled
    $game.Refresh()
    $h = $game.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { return }
    $r = New-Object CapNative+RECT
    [void][CapNative]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    if ($w -lt 200 -or $ht -lt 200) { return }
    if ([CapNative]::IsIconic($h)) { if ($script:bar) { $script:bar.Hide() }; return }
    if ($Cfg.frame -eq 2) {   # test: only centre the window, no strip
        if (-not $script:placed) { $script:placed = $true; $wa = [Windows.Forms.Screen]::FromHandle($h).WorkingArea; if ($Cfg.testx -or $Cfg.testy) { Set-Pos $Cfg.testx $Cfg.testy } else { Set-Pos ($wa.X + [int](($wa.Width - $w) / 2)) ($wa.Y + [int](($wa.Height - $ht) / 2)) }; Log "window centred only" }
        if ([CapNative]::GetForegroundWindow() -eq $h) { $r2 = New-Object CapNative+RECT; [void][CapNative]::GetWindowRect($h, [ref]$r2); [void][CapNative]::ClipCursor([ref]$r2); $script:clipSet = $true }
        elseif ($script:clipSet) { [void][CapNative]::ClipCursorOff([IntPtr]::Zero); $script:clipSet = $false }
        return
    }
    if ($Cfg.frame -eq 3) {   # test: the real frame of the window (caption, system menu), no strip: the window is dragged by the system
        if (-not $script:placed) {
            $script:placed = $true
            $rc = New-Object CapNative+RECT; $rc.Right = $w; $rc.Bottom = $ht
            $ns = ([int64][CapNative]::GetWindowLongPtr($h, -16) -band 0x7FFFFFFF) -bor 0xCA0000   # no WS_POPUP; WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
            [void][CapNative]::AdjustWindowRectEx([ref]$rc, [uint32]$ns, $false, [uint32][int64][CapNative]::GetWindowLongPtr($h, -20))
            $ints = @((0 - $rc.Left), (0 - $rc.Top), (($rc.Right - $rc.Left) - $w), (($rc.Bottom - $rc.Top) - $ht))
            [void][GameHook]::Poke(0x900, ($ints | % { [BitConverter]::GetBytes([int]$_) } | % { $_ }))
            [void][CapNative]::SetWindowLongPtr($h, -16, [IntPtr]$ns)
            $wa = [Windows.Forms.Screen]::FromHandle($h).WorkingArea
            Set-Pos ($wa.X + [Math]::Max(0, [int](($wa.Width - $w) / 2))) ($wa.Y + [Math]::Max($ints[1], [int](($wa.Height - $ht) / 2)))
            Log "real frame: style $($ns.ToString('X')), client in outer $($ints[0]),$($ints[1]), extra $($ints[2])x$($ints[3]), game $w x $ht"
            return
        }
        $pt = New-Object CapNative+PT; [void][CapNative]::ClientToScreen($h, [ref]$pt)   # the client origin follows the window when it is dragged by the caption
        if ($pt.X -ne $script:lastCx -or $pt.Y -ne $script:lastCy) { $script:lastCx = $pt.X; $script:lastCy = $pt.Y; [void][GameHook]::Poke(0xC8, [BitConverter]::GetBytes([int]$pt.X) + [BitConverter]::GetBytes([int]$pt.Y)) }
        # no clip of the cursor: it moves over the whole screen, the game takes the keys and mouse only while its window is in front (ClipCursor is released in the main loop)
        return
    }
    if (-not $script:bar) {
        $b = New-Object NoActForm
        $b.FormBorderStyle = "None"; $b.StartPosition = "Manual"; $b.ShowInTaskbar = $false; $b.BackColor = [Drawing.Color]::FromArgb(40, 44, 52)
        $b.ClientSize = New-Object Drawing.Size($w, $script:barH)
        $t = New-Object Windows.Forms.Label
        $t.Dock = "Fill"; $t.Text = "  Корсары"; $t.ForeColor = [Drawing.Color]::FromArgb(220, 220, 220); $t.TextAlign = "MiddleLeft"; $t.Font = New-Object Drawing.Font("Segoe UI", 9)
        $b.Controls.Add($t)
        $script:drag = $null
        $t.Add_MouseDown({ param($s, $e) if ($e.Button -eq "Left") { $script:drag = [Windows.Forms.Cursor]::Position } })
        $t.Add_MouseUp({ $script:drag = $null; [void][CapNative]::SetForegroundWindow($game.MainWindowHandle) })
        $t.Add_MouseMove({
            if ($script:drag -and [Windows.Forms.Control]::MouseButtons -eq "Left") {
                $p = [Windows.Forms.Cursor]::Position
                $vs = [Windows.Forms.Screen]::FromPoint($p).Bounds   # the whole window stays on the screen: DDrawCompat does not draw the part that has been out of it
                $gh = $script:bar.Height + $script:gameH
                $nx = [Math]::Min([Math]::Max($script:bar.Left + $p.X - $script:drag.X, $vs.Left), $vs.Right - $script:bar.Width)
                $ny = [Math]::Min([Math]::Max($script:bar.Top + $p.Y - $script:drag.Y, $vs.Top), $vs.Bottom - $gh)
                $script:bar.Location = New-Object Drawing.Point($nx, $ny)
                $script:drag = $p
                Set-Pos $script:bar.Left $script:bar.Bottom
            }
        })
        $wa = [Windows.Forms.Screen]::FromHandle($h).WorkingArea
        $x = $wa.X + [Math]::Max(0, [int](($wa.Width - $w) / 2)); $y = $wa.Y + [Math]::Max(0, [int](($wa.Height - $ht - $script:barH) / 2))
        $b.Location = New-Object Drawing.Point($x, $y)
        $script:bar = $b; $script:gameH = $ht
        Set-Pos $x ($y + $script:barH)
        $b.Show()
        Log "window strip: game $w x $ht, window at $x,$($y + $script:barH)"
        return
    }
    $b = $script:bar
    # where the game thinks the cursor is (ENGINE.exe.c: object 0x77DD28 + 0x498CC / 0x498D0, from WM_MOUSEMOVE) against the real one; written when it changes, at most once a second
    $fg = [CapNative]::GetForegroundWindow()
    # the strip is above everything only while the game (or the strip) is in front: after Alt+Tab it goes away with the game, and comes back with it
    if ($fg -eq $h -or $fg -eq $b.Handle) { if (-not $b.TopMost -or -not $b.Visible) { $b.TopMost = $true; if (-not $b.Visible) { $b.Show() } } }
    elseif ($b.TopMost -or $b.Visible) { $b.TopMost = $false; $b.Hide() }
    if ($fg -ne $script:lastFg) { $script:lastFg = $fg; $fo = [uint32]0; [void][CapNative]::GetWindowThreadProcessId($fg, [ref]$fo); Log "foreground: $fg of pid $fo (game $($game.Id), game window $h, strip $($b.Handle))" }
    $mx = [GameHook]::PeekAbs(0x7C75F4); $my = [GameHook]::PeekAbs(0x7C75F8); $cp = [Windows.Forms.Cursor]::Position
    if ("$mx,$my,$($cp.X),$($cp.Y)" -ne $script:lastMouse -and ((Get-Date) - $script:mouseAt).TotalMilliseconds -gt 1000) {
        $script:lastMouse = "$mx,$my,$($cp.X),$($cp.Y)"; $script:mouseAt = Get-Date
        Log "mouse: game $mx,$my screen $($cp.X),$($cp.Y) window $($r.Left),$($r.Top) buttons $([Windows.Forms.Control]::MouseButtons)"
    }
    # the cursor of the game is kept in 0,0 - 800x600 of the screen (the game works with a window in the corner): it is let into the moved window and the strip, as long as the game is in front
    if ([CapNative]::GetForegroundWindow() -eq $h) {
        $want = New-Object CapNative+RECT; $want.Left = $r.Left; $want.Top = $b.Top; $want.Right = $r.Right; $want.Bottom = $r.Bottom
        $have = New-Object CapNative+RECT; [void][CapNative]::GetClipCursor([ref]$have)
        if ($have.Left -ne $want.Left -or $have.Top -ne $want.Top -or $have.Right -ne $want.Right -or $have.Bottom -ne $want.Bottom) {
            if (-not $script:clipLogged) { $script:clipLogged = $true; Log "cursor clip was $($have.Left),$($have.Top) $($have.Right),$($have.Bottom), now $($want.Left),$($want.Top) $($want.Right),$($want.Bottom)" }
            [void][CapNative]::ClipCursor([ref]$want); $script:clipSet = $true
        }
    } elseif ($script:clipSet) { [void][CapNative]::ClipCursorOff([IntPtr]::Zero); $script:clipSet = $false }
    if ($b.Width -ne $w) { $b.Width = $w }
}
$script:picAt = (Get-Date).AddSeconds(-5)
function Log-Input {
    $script:mouseAt = $script:mouseAt
    $cp = [Windows.Forms.Cursor]::Position; $pt = New-Object CapNative+PT; $pt.X = $cp.X; $pt.Y = $cp.Y; $under = [CapNative]::WindowFromPoint($pt); $fg = [CapNative]::GetForegroundWindow()
    $gm = "$([GameHook]::PeekAbs(0x7C75F4)),$([GameHook]::PeekAbs(0x7C75F8))"; $keys = (13, 27, 37, 38, 39, 40 | ? { [CapNative]::GetAsyncKeyState($_) -band 0x8000 }) -join "+"; $gui = [CapNative]::Gui($game.MainWindowHandle); $sig = "$under,$fg,$([Windows.Forms.Control]::MouseButtons),$keys,$gui"
    $mb = [Windows.Forms.Control]::MouseButtons; if ($mb -ne $script:lastMb) { $script:lastMb = $mb; Log "click: buttons $mb cursor $($cp.X),$($cp.Y) fg $fg game $($game.MainWindowHandle) gui [$gui] keys $keys state $(((0x7C75F0,0x7C77A4,0x44D6FC,0x44D708,0x44D70C | % { '{0:X}={1}' -f $_, [GameHook]::PeekAbs($_) }) -join ' '))" }
    if ($sig -ne $script:lastSig -and ((Get-Date) - $script:mouseAt).TotalMilliseconds -gt 500) { $script:lastSig = $sig; $script:mouseAt = Get-Date; $sb = New-Object Text.StringBuilder 64; [void][CapNative]::GetClassNameW($under, $sb, 64); $sf = New-Object Text.StringBuilder 64; [void][CapNative]::GetClassNameW($fg, $sf, 64); Log "input: cursor $($cp.X),$($cp.Y) under $under [$sb] foreground $fg [$sf] game $($game.MainWindowHandle) buttons $([Windows.Forms.Control]::MouseButtons) game-mouse $gm keys $keys gui [$gui] state $(((0x7C75F0,0x7C77A4,0x44D6FC,0x44D708,0x44D70C | % { "{0:X}={1}" -f $_, [GameHook]::PeekAbs($_) }) -join " "))" }
    if (((Get-Date) - $script:picAt).TotalMilliseconds -gt 1000) {   # a picture hash once a second: tells a frozen picture from dead input
        $script:picAt = Get-Date; $rr = New-Object CapNative+RECT; [void][CapNative]::GetWindowRect($game.MainWindowHandle, [ref]$rr)
        $bm = New-Object Drawing.Bitmap 260, 480; $g = [Drawing.Graphics]::FromImage($bm); $g.CopyFromScreen(($rr.Left + 270), ($rr.Top + 100), 0, 0, $bm.Size); $g.Dispose(); $ms = New-Object IO.MemoryStream; $bm.Save($ms, [Drawing.Imaging.ImageFormat]::Bmp); $bm.Dispose()
        $ph = [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash($ms.ToArray())).Replace("-", "").Substring(0, 8)
        Log "pic: $ph frames $([GameHook]::PeekAbs(0x7E00007C)) keys $keys buttons $mb game-mouse $gm"
    }
}
$engineIni = Join-Path $GameDir "engine.ini"
function Test-Windowed { foreach ($l in [IO.File]::ReadAllLines($engineIni, [Text.Encoding]::GetEncoding(1251))) { if ($l -match "^WINDOW_MODE\s+(\d+)") { return [int]$Matches[1] -eq 1 } }; return $false }
$windowed = Test-Windowed

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
$stale = @(Get-Process ENGINE -ErrorAction SilentlyContinue | ? { $_.Id -ne $game.Id }); if ($stale.Count) { Log "WARNING: another ENGINE.exe is running (pid $($stale.Id -join ', ')): two copies of the game fight over DDrawCompat, the picture then freezes (FPS 0); close it in the Task Manager" }
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
# autotest=1 in fix.ini: no hands needed. 20 s after the hook is live: a screenshot, the cursor over two buttons, two more, the hashes of the window area
# are compared (a live picture has a changing FPS counter), the result goes to the log, the pictures to Documents\My Games\Sea Dogs\auto, the game is closed
$script:autoAt = $null; $script:autoStep = 0
function Auto-Step {
    if (-not $script:autoAt) { $script:autoAt = Get-Date }
    $t = ((Get-Date) - $script:autoAt).TotalSeconds; $dir = Join-Path $Stash "auto"
    function Snap($n, $crop) { $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds; $bm = New-Object Drawing.Bitmap $b.Width, $b.Height; $g = [Drawing.Graphics]::FromImage($bm); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size); $g.Dispose(); $bm.Save((Join-Path $dir "$n.png")); if ($crop) { $c = $bm.Clone((New-Object Drawing.Rectangle(($crop.Left + 270), ($crop.Top + 100), 260, 480)), $bm.PixelFormat); $ms = New-Object IO.MemoryStream; $c.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $c.Dispose(); $bm.Dispose(); $h = [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash($ms.ToArray())).Replace("-", "").Substring(0, 8); return $h }; $bm.Dispose(); (Get-FileHash (Join-Path $dir "$n.png")).Hash.Substring(0, 8) }
    $r = New-Object CapNative+RECT; [void][CapNative]::GetWindowRect($game.MainWindowHandle, [ref]$r)
    if ($script:autoStep -eq 0 -and $t -gt 6) { New-Item $dir -ItemType Directory -Force | Out-Null; Remove-Item "$dir\*" -Force; $script:h1 = Snap "1_start"; $script:autoStep = 1 }
    elseif ($script:autoStep -eq 1 -and $t -gt 7) { [Windows.Forms.Cursor]::Position = New-Object Drawing.Point(($r.Left + 400), ($r.Top + 140)); $script:autoStep = 2 }
    elseif ($script:autoStep -eq 2 -and $t -gt 8) { $script:h2 = Snap "2_button1"; [Windows.Forms.Cursor]::Position = New-Object Drawing.Point(($r.Left + 400), ($r.Top + 450)); $script:autoStep = 3 }
    elseif ($script:autoStep -eq 3 -and $t -gt 9) { $script:h3 = Snap "3_button2"; Log "autotest: window $($r.Left),$($r.Top) hashes $($script:h1) $($script:h2) $($script:h3) -> $(if ($script:h1 -ne $script:h2 -or $script:h2 -ne $script:h3) { 'screen changes' } else { 'SCREEN STATIC' })"; [Windows.Forms.Cursor]::Position = New-Object Drawing.Point(($r.Left + 8), ($r.Top + 300)); $script:autoStep = 4 }
    elseif ($script:autoStep -eq 4 -and $t -gt 10 -and $Cfg.autotest -eq 4) { $script:k0 = Snap "4_menu" $r; $cl = New-Object CapNative+RECT; [void][CapNative]::GetClipCursor([ref]$cl); [Windows.Forms.Cursor]::Position = New-Object Drawing.Point(50, 50); Start-Sleep -Milliseconds 400; $c = [Windows.Forms.Cursor]::Position; Log "autotest free: clip $($cl.Left),$($cl.Top)-$($cl.Right),$($cl.Bottom), cursor set 50,50 -> $($c.X),$($c.Y), window $($r.Left),$($r.Top) -> $(if ($c.X -eq 50) { 'CURSOR FREE' } else { 'CURSOR CLIPPED' })"; $script:k1 = Snap "5_far" $r; $script:autoStep = 14; Stop-Process -Id $game.Id -Force }
    elseif ($script:autoStep -eq 4 -and $t -gt 10 -and $Cfg.autotest -eq 3) { $script:k0 = Snap "4_menu" $r; $script:dx0 = $r.Left; $script:dy0 = $r.Top; $oy = [GameHook]::PeekAbs(0x7E0000CC); [Windows.Forms.Cursor]::Position = New-Object Drawing.Point(($r.Left + 400), ($oy - 13)); Start-Sleep -Milliseconds 300; [CapNative]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Log "autotest drag: down at $($r.Left + 400),$($oy - 13), window $($r.Left),$($r.Top)"; $script:autoStep = 10; $script:dragAt = $t }
    elseif ($script:autoStep -ge 10 -and $script:autoStep -le 12 -and $t -gt $script:dragAt + 0.4) { $m = $script:autoStep - 9; $c = [Windows.Forms.Cursor]::Position; [Windows.Forms.Cursor]::Position = New-Object Drawing.Point(($script:dx0 + 400 + 120 * $m), ($c.Y + 0 + $(if ($m -eq 1) { 0 } else { 0 }) + 50)); $script:dragAt = $t; $script:autoStep++; Log "autotest drag: move $m to $([Windows.Forms.Cursor]::Position.X),$([Windows.Forms.Cursor]::Position.Y)" }
    elseif ($script:autoStep -eq 13 -and $t -gt $script:dragAt + 0.4) { [CapNative]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 800; [void][CapNative]::GetWindowRect($game.MainWindowHandle, [ref]$r); $script:k1 = Snap "5_afterdrag" $r; Log "autotest drag: window $($script:dx0),$($script:dy0) -> $($r.Left),$($r.Top), client origin $([GameHook]::PeekAbs(0x7E0000C8)),$([GameHook]::PeekAbs(0x7E0000CC)) -> $(if ($r.Left -gt $script:dx0 + 300) { 'DRAG WORKS' } else { 'DRAG STUCK' })"; $script:autoStep = 14; Stop-Process -Id $game.Id -Force }
    elseif ($script:autoStep -eq 4 -and $t -gt 10) { $script:k0 = Snap "4_menu" $r; $script:autoStep = 5; $ox = $r.Left; $oy = $r.Top; if ($Cfg.frame -eq 3) { $ox = [GameHook]::PeekAbs(0x7E0000C8); $oy = [GameHook]::PeekAbs(0x7E0000CC) }; [Windows.Forms.Cursor]::Position = New-Object Drawing.Point(($ox + 400), ($oy + 479)); Start-Sleep -Milliseconds 300; $cc = [Windows.Forms.Cursor]::Position; Log "autotest: before click cursor $($cc.X),$($cc.Y) window $($r.Left),$($r.Top) rel $($cc.X - $ox),$($cc.Y - $oy) game-mouse $([GameHook]::PeekAbs(0x7C75F4)),$([GameHook]::PeekAbs(0x7C75F8))"; if ($Cfg.autotest -ne 2) { [CapNative]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [CapNative]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero) } }   # autotest=2: no click
    elseif ($script:autoStep -eq 5 -and $t -gt 11.5) { $script:k1 = Snap "5_afterclick" $r; $script:autoStep = 6; [CapNative]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [CapNative]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero) }
    elseif ($script:autoStep -eq 6 -and $t -gt 13) { $script:k2 = Snap "6_afteresc" $r; Log "autotest: keys menu/click/esc hashes $($script:k0) $($script:k1) $($script:k2) -> click $(if ($script:k0 -ne $script:k1) { 'WORKS' } else { 'DEAD' }), Esc $(if ($script:k1 -ne $script:k2) { 'WORKS' } else { 'DEAD' })"; Log "autotest: gui $([CapNative]::Gui($game.MainWindowHandle)) foreground $([CapNative]::GetForegroundWindow()) game $($game.MainWindowHandle)"; $script:autoStep = 7; foreach ($i in 1..2) { [CapNative]::keybd_event(0x28, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [CapNative]::keybd_event(0x28, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 200 } }
    elseif ($script:autoStep -eq 7 -and $t -gt 14.5) { $script:k3 = Snap "7_afterdown" $r; Log "autotest: Down x2 -> $(if ($script:k3 -ne $script:k2) { 'WORKS' } else { 'DEAD' })"; $script:autoStep = 8; Stop-Process -Id $game.Id -Force }
}
$fineDone = $false; $video = $null; $f8 = $false; $f9 = $false; $f10 = $false; $f11 = $false; $tick = 0
try {
while (-not $game.HasExited) {
    Start-Sleep -Milliseconds 100
    $tick++
    $owner = [uint32]0
    [void][CapNative]::GetWindowThreadProcessId([CapNative]::GetForegroundWindow(), [ref]$owner)
    $focus = ($owner -eq $game.Id)   # the keys count only while the game is the window in front
    $d8 = $focus -and (([CapNative]::GetAsyncKeyState(0x77) -band 0x8000) -ne 0)
    $d9 = $focus -and (([CapNative]::GetAsyncKeyState(0x78) -band 0x8000) -ne 0)
    if ($d8 -and -not $f8 -and $Cfg.screenshots) {
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
    $d11 = $focus -and (([CapNative]::GetAsyncKeyState(0x7A) -band 0x8000) -ne 0)
    if ($d11 -and -not $f11) { $script:statLog = -not $script:statLog; $statLog = $script:statLog; Log "statistics log $(if ($statLog) { 'on' } else { 'off' })"; if (-not $statLog) { Add-Content $FpsLog ("{0:yyyy-MM-dd HH:mm:ss} statistics log off" -f (Get-Date)) -Encoding UTF8 } }
    $f8 = $d8; $f9 = $d9; $f10 = $d10; $f11 = $d11
    [Windows.Forms.Application]::DoEvents()
    if ($Cfg.skipintro -and $tick % 2 -eq 0) { try { Skip-Intro } catch { } }
    if ($Cfg.autotest -and $hookLive) { try { Auto-Step } catch { Log "autotest failed: $($_.Exception.Message)" } }
    if ($hookLive -and $windowed) { try { Log-Input } catch { if (-not $script:liErr) { $script:liErr = $true; Log "log-input failed: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)" } } }
    if ($script:cursorFixed -and $tick % 10 -eq 3) { try { $nc = [GameHook]::CursorFix(); if ($nc -or $tick % 100 -eq 3) { Log "cursor fix: changed $nc, $([GameHook]::Dbg)" } } catch { if (-not $script:cfErr) { $script:cfErr = $true; Log "cursor fix failed: $($_.Exception.Message)" } } }
    if ($Cfg.frame -eq 3 -and $windowed -and $focus) { try { $vs = [Windows.Forms.SystemInformation]::VirtualScreen; $cl = New-Object CapNative+RECT; if ([CapNative]::GetClipCursor([ref]$cl) -and ($cl.Right - $cl.Left) -lt $vs.Width) { [void][CapNative]::ClipCursorOff([IntPtr]::Zero); $script:clipFreed++; if ($script:clipFreed -le 5) { Log "cursor clip $($cl.Left),$($cl.Top)-$($cl.Right),$($cl.Bottom) released" } } } catch { } }
    if ($Cfg.frame -and $windowed -and $tick % 5 -eq 0) { try { Set-Frame } catch { Log "window frame failed: $($_.Exception.Message)" } }
    if ($hooked) { if ($toastUntil -ne [datetime]::MinValue -and (Get-Date) -gt $toastUntil) { Poke-Text 0x40 60 ""; $msgText = ""; $toastUntil = [datetime]::MinValue } }
    elseif ($toast.Visible) { if ((Get-Date) -gt $toastUntil) { $toast.Hide() } elseif ($tick % 10 -eq 0) { $toast.Raise() } }
    if ($overlay) { if ($tick % 10 -eq 0) { $overlay.Raise() }; if ($tick % 300 -eq 20) { Log ("overlay: " + $overlay.Where([uint32]$game.Id)) } }
    if ($hooked -and $hookLive -and -not $fineDone -and -not $NoFineTick -and [GameHook]::Peek(0xBC) -eq 1) {
        $fineDone = $true; Log ("fine tick: " + $(if ([GameHook]::FineTick()) { "on" } else { "not set" }))
    }
    if ($hooked -and $hookLive -and $tick % 5 -eq 0) {   # something in the game zeroes the page now and then: the strings are written again
        [void][GameHook]::Poke(0, [BitConverter]::GetBytes([int]$fpsPos[0]) + [BitConverter]::GetBytes([int]$fpsPos[1]) + [BitConverter]::GetBytes([int]$msgPos[0]) + [BitConverter]::GetBytes([int]$msgPos[1]))
        Poke-Text 0x10 48 $fpsText
        Poke-Text 0x40 60 $msgText
        $gx = [Math]::Max(0, [int]($scr.Width - 490)); $gy = [Math]::Max(0, [int]$fpsPos[1] - 200)   # the frame-time graph above the counter
        [void][GameHook]::Poke(0xF4, [BitConverter]::GetBytes([int][Math]::Min(1000, [Math]::Max(0, $Cfg.fpslimit))))   # the frame limit of fix.ini (overlay.c hook)
        [void][GameHook]::Poke(0xA0, [BitConverter]::GetBytes([int]$(if ($focus -and -not $NoKeyRepeat) { 1 } else { 0 })))   # the held keys are repeated while the game is in front
        [void][GameHook]::Poke(0x80, [BitConverter]::GetBytes([int]$(if ($fpsShown) { 1 } else { 0 })) + [BitConverter]::GetBytes($gx) + [BitConverter]::GetBytes($gy))
        Poke-Text 0x400 32 "Framerate %d FPS" -Raw; Poke-Text 0x420 32 "Frametime %d.%d ms" -Raw   # formats of the engine text function (a printf), the numbers come from the hook
        Poke-Text 0x440 32 "1%% low  %d FPS" -Raw; Poke-Text 0x460 32 "0.1%% low %d FPS" -Raw; Poke-Text 0x480 32 "%d ms" -Raw
    }
    if ($hooked -and $tick % 10 -eq 5) {
        $fr = [GameHook]::Peek(0x7C)
        if (-not $hookLive -and $fr -ge 100) { $hookLive = $true; Log "hook: gameplay frames reached, text on" }   # no text on the loading screens
        if ($tick % 50 -eq 5) { Log ("hook: frames {0}, game responding {1}, blt calls {2} last {3:X} rect {4},{5},{6},{7} limit {8} cpm {9}" -f $fr, $game.Responding, [GameHook]::PeekAbs(0x7E0000E0), [GameHook]::PeekAbs(0x7E0000DC), [GameHook]::PeekAbs(0x7E0000E4), [GameHook]::PeekAbs(0x7E0000E8), [GameHook]::PeekAbs(0x7E0000EC), [GameHook]::PeekAbs(0x7E0000F0), [GameHook]::PeekAbs(0x7E0000F4), [GameHook]::PeekAbs(0x7E00008C)) }
    }
    if ($fps -and $tick % 10 -eq 0) { try { Read-Fps $fps } catch { Log "fps: $($_.Exception.Message)" } }
}
} catch { Log "main loop died: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)" }
Stop-Video $video
$toast.Close()
if ($overlay) { $overlay.Close() }
if ($fps -and -not $fps.Proc.HasExited) { $fps.Proc.Kill() }
Log "game ended"
