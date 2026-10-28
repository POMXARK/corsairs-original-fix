<#
Sets the latency profile and the FPS limit of the game before it starts (play.vbs starts it); the values come from fix.ini of the settings window, -Mode overrides lowlag:
  lowlag=0  DDrawCompat.ini as the installer made it, SLEEP_TIME 2 (the original)
  lowlag=1  + VSync=off (no frame waits for the screen, tearing is possible) and SLEEP_TIME 0 in engine.ini (the engine does not sleep in its loop)
  fpslimit=N  FpsLimiter=flipstart(N) of DDrawCompat, 0 = no limit
#>
param([string]$GameDir, [ValidateSet("normal", "lowlag")][string]$Mode)
$Cfg = @{ lowlag = 1; fpslimit = 0 }
$cfgFile = Join-Path $PSScriptRoot "fix.ini"
if (Test-Path $cfgFile) { foreach ($l in [IO.File]::ReadAllLines($cfgFile)) { if ($l -match "^\s*(\w+)\s*=\s*(\d+)\s*$" -and $Cfg.ContainsKey($Matches[1])) { $Cfg[$Matches[1]] = [int]$Matches[2] } } }
if ($Mode) { $Cfg.lowlag = [int]($Mode -eq "lowlag") }
$enc = [Text.Encoding]::GetEncoding(1251)
$ddIni = Join-Path $GameDir "DDrawCompat.ini"
$lines = [IO.File]::ReadAllLines($ddIni) | Where-Object { $_ -notmatch "^\s*(VSync|FpsLimiter)\s*=" }
if ($Cfg.lowlag) { $lines += "VSync=off" }
if ($Cfg.fpslimit -gt 0) { $lines += "FpsLimiter=flipstart($($Cfg.fpslimit))" }
[IO.File]::WriteAllLines($ddIni, $lines)
$ini = Join-Path $GameDir "engine.ini"
$sleep = if ($Cfg.lowlag) { 0 } else { 2 }
$found = $false
$out = [IO.File]::ReadAllLines($ini, $enc) | ForEach-Object { if ($_ -match "^SLEEP_TIME\s") { $found = $true; "SLEEP_TIME $sleep" } else { $_ } }
if (-not $found) { $out += "SLEEP_TIME $sleep" }
[IO.File]::WriteAllLines($ini, $out, $enc)
