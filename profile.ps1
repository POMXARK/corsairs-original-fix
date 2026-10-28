<#
Switches the latency profile of the game before it starts (play.cmd calls it; play-lowlag.cmd sets "lowlag"):
  normal  DDrawCompat.ini as the installer made it, SLEEP_TIME 2 (the original)
  lowlag  + VSync=off (no frame waits for the screen, tearing is possible) and SLEEP_TIME 0 in engine.ini (the engine does not sleep in its loop)
#>
param([string]$GameDir, [ValidateSet("normal", "lowlag")][string]$Mode = "normal")
$enc = [Text.Encoding]::GetEncoding(1251)
$cfg = Join-Path $GameDir "DDrawCompat.ini"
$lines = [IO.File]::ReadAllLines($cfg) | Where-Object { $_ -notmatch "^\s*VSync\s*=" }
if ($Mode -eq "lowlag") { $lines += "VSync=off" }
[IO.File]::WriteAllLines($cfg, $lines)
$ini = Join-Path $GameDir "engine.ini"
$sleep = if ($Mode -eq "lowlag") { 0 } else { 2 }
$found = $false
$out = [IO.File]::ReadAllLines($ini, $enc) | ForEach-Object { if ($_ -match "^SLEEP_TIME\s") { $found = $true; "SLEEP_TIME $sleep" } else { $_ } }
if (-not $found) { $out += "SLEEP_TIME $sleep" }
[IO.File]::WriteAllLines($ini, $out, $enc)
