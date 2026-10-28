schtasks /create /tn cofauto /tr "powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\go.ps1" /sc once /st 23:59 /ru User /it /f
schtasks /run /tn cofauto
Start-Sleep 5
schtasks /delete /tn cofauto /f
