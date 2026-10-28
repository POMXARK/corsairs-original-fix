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
$curWasd = $false
$ctlPath = Join-Path $GameDir "RESOURCE\INI\controls.ini"
if (Test-Path $ctlPath) { $curWasd = [bool]([IO.File]::ReadAllText($ctlPath, [Text.Encoding]::GetEncoding(1251)) -match "(?m)^control24=1,87,") }
$origFonts = "$fonts.orig"
if ((Test-Path $fonts) -and (Test-Path $origFonts)) {
    # масштаб = отношение первого числа строки seadogs в текущем и сохранённом fonts.ini
    $a = [regex]::Match(([IO.File]::ReadAllText($fonts, [Text.Encoding]::GetEncoding(1251))), "(?m)^seadogs\s*=\s*([0-9.]+)").Groups[1].Value
    $b = [regex]::Match(([IO.File]::ReadAllText($origFonts, [Text.Encoding]::GetEncoding(1251))), "(?m)^seadogs\s*=\s*([0-9.]+)").Groups[1].Value
    if ($a -and $b) { $inv = [Globalization.CultureInfo]::InvariantCulture; $curFont = [Math]::Round([double]::Parse($a, $inv) / [double]::Parse($b, $inv), 2) }
}

# вид как у Config.exe оригинала: серая форма, группа с полями слева, кнопки справа, мелкий шрифт
[Windows.Forms.Application]::EnableVisualStyles()
$f = New-Object Windows.Forms.Form
$f.Text = "Установки ""Корсаров"""
$f.AutoScaleMode = "None"
$f.ClientSize = New-Object Drawing.Size(422, 236)
$f.StartPosition = "CenterScreen"
$f.FormBorderStyle = "FixedDialog"; $f.MaximizeBox = $false; $f.MinimizeBox = $false
$f.Font = New-Object Drawing.Font("Tahoma", 8.25)

function Add-Ctl($parent, $ctl, $x, $y, $w, $h) {
    $ctl.Location = New-Object Drawing.Point($x, $y); $ctl.Size = New-Object Drawing.Size($w, $h)
    $parent.Controls.Add($ctl); return $ctl
}
function New-Text($text) { $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.TextAlign = "MiddleLeft"; return $l }

$g = Add-Ctl $f (New-Object Windows.Forms.GroupBox) 8 4 316 176 0
$g.Text = "Параметры визуализации"
$null = Add-Ctl $g (New-Text "Разрешение") 12 26 90 22
$cbRes = Add-Ctl $g (New-Object Windows.Forms.ComboBox) 110 26 190 22
$cbRes.Items.AddRange($modes)
$cbRes.Text = if ($curW -and $curH) { "${curW}x$curH" } else { $desktop }

$chFull = Add-Ctl $g (New-Object Windows.Forms.CheckBox) 12 62 140 20
$chFull.Text = "Полный экран"; $chFull.Checked = ($curMode -ne "1")

$null = Add-Ctl $g (New-Text "Размер шрифта") 12 96 96 22
$nud = Add-Ctl $g (New-Object Windows.Forms.NumericUpDown) 110 96 60 22
$nud.DecimalPlaces = 1; $nud.Increment = 0.1; $nud.Minimum = 0.5; $nud.Maximum = 4
$nud.Value = [decimal][Math]::Min(4, [Math]::Max(0.5, $curFont))
$auto = Add-Ctl $g (New-Object Windows.Forms.CheckBox) 184 96 116 22
$auto.Text = "по экрану"
$auto.Add_CheckedChanged({ $nud.Enabled = -not $auto.Checked })

$chWasd = Add-Ctl $g (New-Object Windows.Forms.CheckBox) 12 130 290 22
$chWasd.Text = "Ходьба в городе на W / S"; $chWasd.Checked = $curWasd

$status = Add-Ctl $f (New-Object Windows.Forms.Label) 8 188 316 44 0
$status.Text = "Игра: $GameDir"

function Apply-Settings([switch]$Launch) {
    $parts = "$($cbRes.Text)".Trim() -split "[xх×]"
    if ($parts.Count -ne 2 -or -not ($parts[0] -as [int]) -or -not ($parts[1] -as [int])) { $status.Text = "Разрешение вида 1920x1080"; return }
    $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Install, "-GameDir", $GameDir, "-Width", [int]$parts[0], "-Height", [int]$parts[1])
    if (-not $chFull.Checked) { $psArgs += "-Windowed" }
    if ($chWasd.Checked) { $psArgs += "-Wasd" }
    $psArgs += @("-FontScale", $(if ($auto.Checked) { "0" } else { ([double]$nud.Value).ToString([Globalization.CultureInfo]::InvariantCulture) }))
    $status.Text = "Применяю..."; $f.Refresh()
    $out = & powershell @psArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and $out -match "(?i)error|ошибк|exception") { $status.Text = "Ошибка: " + $out.Trim().Split("`n")[-1]; return $false }
    $status.Text = "Сохранено: $($cbRes.Text), шрифт ×$(if ($auto.Checked) { 'авто' } else { $nud.Value })"
    if ($Launch) { Start-Process (Join-Path $GameDir "ENGINE.exe") -WorkingDirectory $GameDir }
}

$b1 = Add-Ctl $f (New-Object Windows.Forms.Button) 334 12 80 26; $b1.Text = "Сохранить"
$b1.Add_Click({ Apply-Settings })
$b2 = Add-Ctl $f (New-Object Windows.Forms.Button) 334 44 80 26; $b2.Text = "Играть"
$b2.Add_Click({ Apply-Settings -Launch })
$b3 = Add-Ctl $f (New-Object Windows.Forms.Button) 334 76 80 26; $b3.Text = "Сбросить"
$b3.Add_Click({
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Install -GameDir $GameDir -Uninstall | Out-Null
    $status.Text = "Оригинальные файлы игры возвращены"
})
$b4 = Add-Ctl $f (New-Object Windows.Forms.Button) 334 108 80 26; $b4.Text = "Закрыть"
$b4.Add_Click({ $f.Close() })

[void]$f.ShowDialog()
