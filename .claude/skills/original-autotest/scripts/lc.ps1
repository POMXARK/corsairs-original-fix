$p=[Environment]::GetFolderPath("MyDocuments")+"\My Games\Sea Dogs\Logs\fps.log"
$l = Get-Content $p; $i = ($l | Select-String "game started" | Select -Last 1).LineNumber
$l[($i-1)..($l.Count-1)] | ? { $_ -match "pic:|click:|game started|exited" } | % { ($_ -replace ' wins .* state',' state') } | select -last 90 | % { $_.Substring(0,[Math]::Min(330,$_.Length)) }
$l | ? { $_ -match "osd:" } | select -last 3
