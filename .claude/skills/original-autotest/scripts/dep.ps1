$g = "C:\Program Files\1C\Корсары\fix"
Copy-Item C:\Users\User\cof\capture.ps1 $g -Force
Copy-Item C:\Users\User\cof\overlay.bin $g -Force
Copy-Item C:\Users\User\cof\settings.ps1 $g -Force
Copy-Item C:\Users\User\cof\play.ps1 $g -Force
(Get-Item "$g\settings.ps1").Length
(Select-String -Path "$g\settings.ps1" -Pattern "chAud" -List).Count
