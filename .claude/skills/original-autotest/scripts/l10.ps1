$p=[Environment]::GetFolderPath("MyDocuments")+"\My Games\Sea Dogs\Logs\fps.log"
Get-Content $p | Select-String "autotest|game started" | Select-Object -Last 4 | % { $_.Line }
Get-Process ENGINE -ErrorAction SilentlyContinue | % { "ENGINE running $($_.Id)" }
Get-ChildItem ([Environment]::GetFolderPath("MyDocuments")+"\My Games\Sea Dogs\auto") | % { $_.Name }
