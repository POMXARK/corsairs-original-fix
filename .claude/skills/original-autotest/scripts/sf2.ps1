$f = "C:\Program Files\1C\Корсары\fix\fix.ini"
$l = @(Get-Content $f | ? { $_ -notmatch "^(frame|autotest)=" }); $l += "frame=1"; $l | Set-Content $f; Get-Content $f
