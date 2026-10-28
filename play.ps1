<#
The game with the profile, the hook, the logs and the capture of fix.ini, without a console window (play.vbs starts it hidden and as an administrator: PresentMon needs the rights).
  play.ps1 [-Mode lowlag|normal] [-NoKeyRepeat] [-NoFineTick]    # the switches override fix.ini
#>
param([string]$Mode, [switch]$NoKeyRepeat, [switch]$NoFineTick)
$GameDir = Split-Path -Parent $PSScriptRoot
$pa = @{}; if ($Mode) { $pa.Mode = $Mode }
& (Join-Path $PSScriptRoot "profile.ps1") -GameDir $GameDir @pa
$cap = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-WindowStyle", "Hidden", "-File", (Join-Path $PSScriptRoot "capture.ps1"), "-GameDir", $GameDir)
if ($NoKeyRepeat) { $cap += "-NoKeyRepeat" }
if ($NoFineTick) { $cap += "-NoFineTick" }
$psi = New-Object Diagnostics.ProcessStartInfo "powershell.exe"
$psi.Arguments = ($cap | ForEach-Object { if ($_ -match "\s") { "`"$_`"" } else { $_ } }) -join " "
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
[void][Diagnostics.Process]::Start($psi)
Start-Process (Join-Path $GameDir "ENGINE.exe") -WorkingDirectory $GameDir
