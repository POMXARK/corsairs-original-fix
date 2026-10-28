# Окно настроек оригинальных «Корсаров»: разрешение, режим экрана, размер шрифта. Запуск: settings.cmd
# Всё делает install.ps1 (он идемпотентен), здесь только форма: читает текущие значения, вызывает install.ps1 с ключами.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Install = Join-Path $Here "install.ps1"

function Find-Game {
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "C:\Games", "D:\Games")) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Recurse -Filter ENGINE.exe -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.DirectoryName "MODULES\CORE.dll") } | Select-Object -First 1
        if ($hit) { return $hit.DirectoryName }
    }
}

function Get-Key($path, $key) {
    if (-not (Test-Path $path)) { return $null }
    foreach ($l in [IO.File]::ReadAllLines($path, [Text.Encoding]::GetEncoding(1251))) { if ($l -match "^$key\s+(\S+)") { return $Matches[1] } }
}

$GameDir = Find-Game
if (-not $GameDir) {
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Папка с ENGINE.exe"
    if ($dlg.ShowDialog() -ne "OK") { return }
    $GameDir = $dlg.SelectedPath
}
$ini = Join-Path $GameDir "engine.ini"
$fonts = Join-Path $GameDir "RESOURCE\INI\fonts.ini"

# разрешения: свои режимы + разрешение рабочего стола; игра принимает любое
$v = Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
$desktop = if ($v) { "$($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution)" } else { "1920x1080" }
$modes = @("800x600", "1024x768", "1280x720", "1280x960", "1280x1024", "1600x900", "1600x1200", "1920x1080", "1920x1200", "2560x1080", "2560x1440", "3440x1440", "3840x2160")
if ($modes -notcontains $desktop) { $modes += $desktop }

$curW = Get-Key $ini "WINDOW_WIDTH"; $curH = Get-Key $ini "WINDOW_HEIGHT"
$curMode = Get-Key $ini "WINDOW_MODE"
$curFont = 1.0
$origFonts = "$fonts.orig"
if ((Test-Path $fonts) -and (Test-Path $origFonts)) {
    # масштаб = отношение первого числа строки seadogs в текущем и сохранённом fonts.ini
    $a = [regex]::Match(([IO.File]::ReadAllText($fonts, [Text.Encoding]::GetEncoding(1251))), "(?m)^seadogs\s*=\s*([0-9.]+)").Groups[1].Value
    $b = [regex]::Match(([IO.File]::ReadAllText($origFonts, [Text.Encoding]::GetEncoding(1251))), "(?m)^seadogs\s*=\s*([0-9.]+)").Groups[1].Value
    if ($a -and $b) { $inv = [Globalization.CultureInfo]::InvariantCulture; $curFont = [Math]::Round([double]::Parse($a, $inv) / [double]::Parse($b, $inv), 2) }
}

$f = New-Object Windows.Forms.Form
$f.Text = "Корсары: настройки"
$f.ClientSize = New-Object Drawing.Size(400, 250)
$f.StartPosition = "CenterScreen"
$f.FormBorderStyle = "FixedDialog"; $f.MaximizeBox = $false
$f.Font = New-Object Drawing.Font("Segoe UI", 10)

function Add-Label($text, $y) { $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object Drawing.Point(16, $y + 3); $l.AutoSize = $true; $f.Controls.Add($l) }

Add-Label "Разрешение" 16
$cbRes = New-Object Windows.Forms.ComboBox
$cbRes.Location = New-Object Drawing.Point(150, 16); $cbRes.Width = 230
$cbRes.Items.AddRange($modes)
$cbRes.Text = if ($curW -and $curH) { "${curW}x$curH" } else { $desktop }
$f.Controls.Add($cbRes)

Add-Label "Экран" 56
$cbMode = New-Object Windows.Forms.ComboBox
$cbMode.Location = New-Object Drawing.Point(150, 56); $cbMode.Width = 230; $cbMode.DropDownStyle = "DropDownList"
[void]$cbMode.Items.AddRange(@("На весь экран", "В окне"))
$cbMode.SelectedIndex = if ($curMode -eq "1") { 1 } else { 0 }
$f.Controls.Add($cbMode)

Add-Label "Размер шрифта" 96
$nud = New-Object Windows.Forms.NumericUpDown
$nud.Location = New-Object Drawing.Point(150, 96); $nud.Width = 80
$nud.DecimalPlaces = 1; $nud.Increment = 0.1; $nud.Minimum = 0.5; $nud.Maximum = 4
$nud.Value = [decimal][Math]::Min(4, [Math]::Max(0.5, $curFont))
$f.Controls.Add($nud)
$auto = New-Object Windows.Forms.CheckBox
$auto.Text = "по экрану"; $auto.Location = New-Object Drawing.Point(250, 96); $auto.AutoSize = $true
$auto.Add_CheckedChanged({ $nud.Enabled = -not $auto.Checked })
$f.Controls.Add($auto)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(16, 140); $status.Size = New-Object Drawing.Size(370, 40)
$status.Text = "Игра: $GameDir"
$f.Controls.Add($status)

function Apply-Settings([switch]$Launch) {
    $parts = "$($cbRes.Text)".Trim() -split "[xх×]"
    if ($parts.Count -ne 2 -or -not ($parts[0] -as [int]) -or -not ($parts[1] -as [int])) { $status.Text = "Разрешение вида 1920x1080"; return }
    $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Install, "-GameDir", $GameDir, "-Width", [int]$parts[0], "-Height", [int]$parts[1])
    if ($cbMode.SelectedIndex -eq 1) { $psArgs += "-Windowed" }
    $psArgs += @("-FontScale", $(if ($auto.Checked) { "0" } else { ([double]$nud.Value).ToString([Globalization.CultureInfo]::InvariantCulture) }))
    $status.Text = "Применяю..."; $f.Refresh()
    $out = & powershell @args 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and $out -match "(?i)error|ошибк|exception") { $status.Text = "Ошибка: " + $out.Trim().Split("`n")[-1]; return }
    $status.Text = "Готово: $($cbRes.Text), шрифт ×$(if ($auto.Checked) { 'авто' } else { $nud.Value })"
    if ($Launch) { Start-Process (Join-Path $GameDir "ENGINE.exe") -WorkingDirectory $GameDir }
}

$btn = New-Object Windows.Forms.Button
$btn.Text = "Применить"; $btn.Location = New-Object Drawing.Point(16, 195); $btn.Size = New-Object Drawing.Size(115, 36)
$btn.Add_Click({ Apply-Settings })
$f.Controls.Add($btn)
$btnGo = New-Object Windows.Forms.Button
$btnGo.Text = "Применить и играть"; $btnGo.Location = New-Object Drawing.Point(140, 195); $btnGo.Size = New-Object Drawing.Size(150, 36)
$btnGo.Add_Click({ Apply-Settings -Launch })
$f.Controls.Add($btnGo)
$btnOff = New-Object Windows.Forms.Button
$btnOff.Text = "Вернуть оригинал"; $btnOff.Location = New-Object Drawing.Point(298, 195); $btnOff.Size = New-Object Drawing.Size(86, 36)
$btnOff.Font = New-Object Drawing.Font("Segoe UI", 8)
$btnOff.Add_Click({
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Install -GameDir $GameDir -Uninstall | Out-Null
    $status.Text = "Оригинальные файлы возвращены"
})
$f.Controls.Add($btnOff)

[void]$f.ShowDialog()
