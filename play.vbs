' Starts play.ps1 without a console window (conhost --headless: -WindowStyle Hidden still flashes the console for a moment) and as an administrator (the UAC question stays); the arguments go to play.ps1: play.vbs lowlag
Set sh = CreateObject("Shell.Application")
dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
args = ""
If WScript.Arguments.Count > 0 Then
  If LCase(WScript.Arguments(0)) = "lowlag" Or LCase(WScript.Arguments(0)) = "normal" Then args = " -Mode " & WScript.Arguments(0)
End If
sh.ShellExecute "conhost.exe", "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\play.ps1""" & args, dir, "runas", 0
