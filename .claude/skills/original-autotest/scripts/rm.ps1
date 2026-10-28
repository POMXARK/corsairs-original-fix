$f = "C:\Program Files\1C\Корсары\fix\fix.ini"
(Get-Content $f) | ? { $_ -notmatch "^autotest=" } | Set-Content $f
Get-Content $f | select -last 2
