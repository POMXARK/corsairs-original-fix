$d=[Environment]::GetFolderPath("MyDocuments")+"\My Games\Sea Dogs\auto"
New-Item C:\Users\User\cof\shots -ItemType Directory -Force | Out-Null
Copy-Item "$d\*.png" C:\Users\User\cof\shots -Force
Get-ChildItem C:\Users\User\cof\shots | % { "$($_.Name) $($_.LastWriteTime)" }
