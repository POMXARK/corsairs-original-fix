' The settings window without a console window, as an administrator (the files of the game are in Program Files)
Set sh = CreateObject("Shell.Application")
dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.ShellExecute "conhost.exe", "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & dir & "\settings.ps1""", dir, "runas", 0
