$e=$null;[void][Management.Automation.Language.Parser]::ParseFile("C:\Users\User\cof\capture.ps1",[ref]$null,[ref]$e);"errors: "+$e.Count;$e|select -first 3|%{$_.Message}
