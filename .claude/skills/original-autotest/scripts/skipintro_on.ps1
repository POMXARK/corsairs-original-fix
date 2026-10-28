$f = "C:\Program Files\1C\Корсары\fix\fix.ini"
$l = @(Get-Content $f | ? { $_ -notmatch "^(skipintro|autotest)=" }); $l += "skipintro=1"; $l | Set-Content $f
