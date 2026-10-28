$p=[Environment]::GetFolderPath("MyDocuments")+"\My Games\Sea Dogs\Logs\fps.log"
$l = Get-Content $p; $i = ($l | Select-String "game started" | Select -Last 1).LineNumber
$l[($i-1)..($l.Count-1)] | ? { $_ -notmatch "osd:|hook: frames|fps avg" } | % { ($_ -replace ' wins .* state',' state') } | select -last 40 | % { $_.Substring(0,[Math]::Min(300,$_.Length)) }
