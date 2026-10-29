# Окно настроек оригинальных «Корсаров»: разрешение, режим экрана, размер шрифта. Запуск: settings.vbs
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
$f.ClientSize = New-Object Drawing.Size(422, 666)
$f.StartPosition = "CenterScreen"
$f.FormBorderStyle = "FixedDialog"; $f.MaximizeBox = $false; $f.MinimizeBox = $false
$f.Font = New-Object Drawing.Font("Tahoma", 8.25)

function Add-Ctl($parent, $ctl, $x, $y, $w, $h) {
    $ctl.Location = New-Object Drawing.Point($x, $y); $ctl.Size = New-Object Drawing.Size($w, $h)
    $parent.Controls.Add($ctl); return $ctl
}
function New-Text($text) { $l = New-Object Windows.Forms.Label; $l.Text = $text; $l.TextAlign = "MiddleLeft"; return $l }

$g = Add-Ctl $f (New-Object Windows.Forms.GroupBox) 8 4 316 212 0
$g.Text = "Параметры визуализации"
$lblRes = Add-Ctl $g (New-Text "Разрешение") 12 26 96 22
$cbRes = Add-Ctl $g (New-Object Windows.Forms.ComboBox) 110 26 190 22
$cbRes.Items.AddRange($modes)

# fix.ini: настройки наших патчей, их читают profile.ps1 (задержка, лимит FPS) и capture.ps1 (хук, логи, снимки, видео)
$cfgPath = Join-Path $Here "fix.ini"
$cfg = [ordered]@{ lowlag = 1; fpslimit = 0; keyrepeat = 1; finetick = 0; screenshots = 1; video = 1; audio = 1; fpslog = 1; osd = 1; statlog = 1; frame = 3; skipintro = 1; fontauto = 1; supersample = 100; thumb = 0; outw = 0; outh = 0 }
if (Test-Path $cfgPath) { foreach ($l in [IO.File]::ReadAllLines($cfgPath)) { if ($l -match "^\s*(\w+)\s*=\s*(\d+)\s*$" -and $cfg.Contains($Matches[1])) { $cfg[$Matches[1]] = [int]$Matches[2] } } }

$cbRes.Text = if ($cfg.thumb -eq 1 -and $cfg.outw -gt 0) { "$($cfg.outw)x$($cfg.outh)" } elseif ($curW -and $curH) { "${curW}x$curH" } else { $desktop }
$chFull = Add-Ctl $g (New-Object Windows.Forms.CheckBox) 12 62 140 20
$chFull.Text = "Полный экран"; $chFull.Checked = ($curMode -ne "1"); $chFull.Width = 100
$frameModes = @("окно в углу, без рамки", "полоса-заголовок, центр", "настоящая рамка, центр")
$frameVals = @(0, 1, 3)
$cbFrame = Add-Ctl $g (New-Object Windows.Forms.ComboBox) 116 60 190 22
$cbFrame.DropDownStyle = "DropDownList"; $cbFrame.Items.AddRange($frameModes)
$fi = [Array]::IndexOf($frameVals, [int]$cfg.frame); $cbFrame.SelectedIndex = $(if ($fi -ge 0) { $fi } else { 2 })
$tip0 = New-Object Windows.Forms.ToolTip; $tip0.SetToolTip($cbFrame, "Вид окна при выключенном полном экране. Настоящая рамка: родной заголовок Windows (светлый, стиль Windows 10). окно двигается и без фокуса игры. Полоса-заголовок: прежний вариант, полоса над окном. Без рамки: окно в углу экрана, как в оригинале. Разрешение лучше брать меньше экрана.")
$chFull.Add_CheckedChanged({ $cbFrame.Enabled = -not $chFull.Checked }); $cbFrame.Enabled = -not $chFull.Checked

$null = Add-Ctl $g (New-Text "Размер шрифта") 12 96 96 22
$nud = Add-Ctl $g (New-Object Windows.Forms.NumericUpDown) 110 96 60 22
$nud.DecimalPlaces = 1; $nud.Increment = 0.1; $nud.Minimum = 0.5; $nud.Maximum = 4
$nud.Value = [decimal][Math]::Min(4, [Math]::Max(0.5, $curFont))
$auto = Add-Ctl $g (New-Object Windows.Forms.CheckBox) 184 96 116 22
$auto.Text = "по экрану"
$auto.Add_CheckedChanged({ $nud.Enabled = -not $auto.Checked }); $auto.Checked = [bool]$cfg.fontauto; $nud.Enabled = -not $auto.Checked

$null = Add-Ctl $g (New-Text "Суперсэмплинг") 12 124 96 22
$cbSS = Add-Ctl $g (New-Object Windows.Forms.ComboBox) 110 124 190 22
$cbSS.DropDownStyle = "DropDownList"; $ssVals = @(100, 150, 200, 300, 400)
$cbSS.Items.AddRange(@("выкл.", "x1,5 (мягкий)", "x2 (сильный)", "x3 (Full HD, ~27 к/с)", "x4 (максимум, тяжело)"))
$si = [Array]::IndexOf($ssVals, [int]$cfg.supersample); $cbSS.SelectedIndex = $(if ($si -ge 0) { $si } else { 0 })
$tip0.SetToolTip($cbSS, "Игра рисует в разрешении выше выбранного, а DDrawCompat уменьшает кадр до экрана: убирает лесенку на краях и мерцание у ближайших объектов. В окне размер окна остаётся выбранным (например 800x600), игра рисует крупнее, а маленькое окно показывает уменьшенную копию (рендер не выше высоты экрана). x2 при 2560x1440 даёт рендер 5120x2880: нужна мощная видеокарта.")
$chThumb = Add-Ctl $g (New-Object Windows.Forms.CheckBox) 12 152 292 22
$chThumb.Text = "Маленькое окно, рендер выше (сглаживание)"
$tip0.SetToolTip($chThumb, "Маленькое окно выбранного размера (например 800x600) показывает уменьшенную копию кадра, который игра рисует крупнее (масштаб справа). Лесенка пропадает, а размер окна не зависит от разрешения рендера. Рендер не выше высоты экрана. Полный экран и рамка в этом режиме не нужны: окно со своей рамкой, закрытие окна закрывает игру. Масштаб «выкл.» заменяется на x2.")
function Update-Thumb {
    $on = $chThumb.Checked
    $lblRes.Text = $(if ($on) { "Размер окна" } else { "Разрешение" })
    if ($on) { $chFull.Checked = $false }
    $chFull.Enabled = -not $on; $cbFrame.Enabled = (-not $on) -and (-not $chFull.Checked)
    if ($on -and $cbSS.SelectedIndex -eq 0) { $cbSS.SelectedIndex = $(if ([Windows.Forms.Screen]::PrimaryScreen.Bounds.Width -ge 1920) { 3 } else { 2 }) }   # x3 for Full HD windows (measured 27 fps), else x2
}
$chThumb.Checked = ($cfg.thumb -eq 1 -and $curMode -eq "1")
$chThumb.Add_CheckedChanged({ Update-Thumb }); Update-Thumb
$chWasd = Add-Ctl $g (New-Object Windows.Forms.CheckBox) 12 180 290 22
$chWasd.Text = "Ходьба в городе на W A S D"; $chWasd.Checked = $curWasd

# счётчик FPS: место и размер задаются на миниатюре экрана; fix\osd.ini читает capture.ps1
$osdPath = Join-Path $Here "osd.ini"
$osd = @{ x = 0.0; y = 0.0; size = 14 }
if (Test-Path $osdPath) {
    foreach ($l in [IO.File]::ReadAllLines($osdPath)) {
        if ($l -match "^(x|y|size)=([0-9.]+)$") { $osd[$Matches[1]] = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture) }
    }
}
$g2 = Add-Ctl $f (New-Object Windows.Forms.GroupBox) 8 196 316 168 0
$g2.Text = "Счётчик FPS"
$chOsd = Add-Ctl $g2 (New-Object Windows.Forms.CheckBox) 12 20 130 22
$chOsd.Text = "FPS и график (F10)"; $chOsd.Checked = [bool]$cfg.osd; $chOsd.Width = 146
$null = Add-Ctl $g2 (New-Text "Размер") 12 50 50 22
$nudOsd = Add-Ctl $g2 (New-Object Windows.Forms.NumericUpDown) 66 50 60 22
$nudOsd.Minimum = 8; $nudOsd.Maximum = 96; $nudOsd.Value = [decimal][Math]::Min(96, [Math]::Max(8, $osd.size))

# миниатюра экрана с той же пропорцией, что у рабочего стола; квадрат - счётчик, щелчок или перетаскивание двигают его
$ds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$pw = 148; $ph = [int][Math]::Round($pw * $ds.Height / $ds.Width)
$pan = Add-Ctl $g2 (New-Object Windows.Forms.Panel) 158 20 $pw $ph
$pan.BackColor = [Drawing.Color]::FromArgb(30, 40, 60); $pan.BorderStyle = "FixedSingle"
$hint = Add-Ctl $g2 (New-Text "Или щёлкните на миниатюре") 158 ($ph + 24) 148 40
$hint.TextAlign = "TopLeft"
function Get-OsdBox {   # размер счётчика на миниатюре: ширина 5, высота 1.7 кегля на экране
    $w = [Math]::Max(6, [int]($nudOsd.Value * 5 * $pw / $ds.Width)); $h = [Math]::Max(4, [int]($nudOsd.Value * 1.7 * $ph / $ds.Height))
    return @($w, $h)
}
$pan.Add_Paint({
    param($s, $e)
    $b = Get-OsdBox
    $x = [int]($osd.x * ($pan.ClientSize.Width - $b[0])); $y = [int]($osd.y * ($pan.ClientSize.Height - $b[1]))
    foreach ($ax in 0, 0.5, 1) { foreach ($ay in 0, 0.5, 1) {   # 9 места, к которым щелчок "прилипает"
        $e.Graphics.FillEllipse([Drawing.Brushes]::Gray, [int]($ax * ($pan.ClientSize.Width - $b[0]) + $b[0] / 2 - 2), [int]($ay * ($pan.ClientSize.Height - $b[1]) + $b[1] / 2 - 2), 4, 4)
    } }
    $e.Graphics.FillRectangle([Drawing.Brushes]::Lime, $x, $y, $b[0], $b[1])
})
$moveOsd = {
    param($s, $e)
    if ($e.Button -ne "Left") { return }
    $b = Get-OsdBox
    $osd.x = [Math]::Min(1, [Math]::Max(0, ($e.X - $b[0] / 2) / [Math]::Max(1, $pan.ClientSize.Width - $b[0])))
    $osd.y = [Math]::Min(1, [Math]::Max(0, ($e.Y - $b[1] / 2) / [Math]::Max(1, $pan.ClientSize.Height - $b[1])))
    foreach ($k in "x", "y") { foreach ($a in 0, 0.5, 1) { if ([Math]::Abs($osd[$k] - $a) -lt 0.07) { $osd[$k] = $a } } }   # прилипание к краям и центру
    $pan.Invalidate()
}
$pan.Add_MouseDown($moveOsd); $pan.Add_MouseMove($moveOsd)
$pan.Add_MouseUp({ Save-Osd })   # положение запоминается сразу, без кнопки «Сохранить»
$nudOsd.Add_ValueChanged({ $pan.Invalidate(); Save-Osd })

# готовые места
$cbPlace = Add-Ctl $g2 (New-Object Windows.Forms.ComboBox) 12 116 138 22
$cbPlace.DropDownStyle = "DropDownList"
$places = [ordered]@{ "Слева вверху" = @(0, 0); "Вверху по центру" = @(0.5, 0); "Справа вверху" = @(1, 0); "Слева по центру" = @(0, 0.5); "По центру" = @(0.5, 0.5); "Справа по центру" = @(1, 0.5); "Слева внизу" = @(0, 1); "Внизу по центру" = @(0.5, 1); "Справа внизу" = @(1, 1) }
$cbPlace.Items.AddRange(@($places.Keys))
$cbPlace.Add_SelectedIndexChanged({ $p = $places[$cbPlace.SelectedItem]; $osd.x = $p[0]; $osd.y = $p[1]; $pan.Invalidate(); Save-Osd })

# настоящий счётчик на рабочем столе: зажать мышь и тянуть; Esc или двойной щелчок - готово
function Show-OsdPlacer {
    $size = [int]$nudOsd.Value
    $o = New-Object Windows.Forms.Form
    $o.FormBorderStyle = "None"; $o.ShowInTaskbar = $false; $o.TopMost = $true; $o.StartPosition = "Manual"; $o.KeyPreview = $true
    $o.BackColor = [Drawing.Color]::Black; $o.Opacity = 0.8
    $o.Size = New-Object Drawing.Size([int]($size * 5), [int]($size * 1.7))
    $o.Location = New-Object Drawing.Point(([int]($ds.X + $osd.x * ($ds.Width - $o.Width))), ([int]($ds.Y + $osd.y * ($ds.Height - $o.Height))))
    $l = New-Object Windows.Forms.Label
    $l.Dock = "Fill"; $l.ForeColor = [Drawing.Color]::Lime; $l.TextAlign = "MiddleCenter"; $l.Text = "FPS 120"
    $l.Font = New-Object Drawing.Font("Consolas", $size, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $o.Controls.Add($l)
    $grab = @{ on = $false; dx = 0; dy = 0 }
    $down = { param($s, $e) if ($e.Button -eq "Left") { $grab.on = $true; $grab.dx = [Windows.Forms.Cursor]::Position.X - $o.Left; $grab.dy = [Windows.Forms.Cursor]::Position.Y - $o.Top } }
    $move = {
        param($s, $e)
        if (-not $grab.on) { return }
        $nx = [Math]::Min($ds.Right - $o.Width, [Math]::Max($ds.Left, [Windows.Forms.Cursor]::Position.X - $grab.dx))
        $ny = [Math]::Min($ds.Bottom - $o.Height, [Math]::Max($ds.Top, [Windows.Forms.Cursor]::Position.Y - $grab.dy))
        $o.Location = New-Object Drawing.Point($nx, $ny)
    }
    $up = { param($s, $e) $grab.on = $false }
    $done = { $o.Close() }
    foreach ($c in $o, $l) { $c.Add_MouseDown($down); $c.Add_MouseMove($move); $c.Add_MouseUp($up); $c.Add_DoubleClick($done) }
    $o.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq "Escape" -or $e.KeyCode -eq "Return") { $o.Close() } })
    $f.WindowState = "Minimized"
    [void]$o.ShowDialog()
    $f.WindowState = "Normal"; $f.Activate()
    $osd.x = [Math]::Min(1, [Math]::Max(0, ($o.Left - $ds.X) / [Math]::Max(1, $ds.Width - $o.Width)))
    $osd.y = [Math]::Min(1, [Math]::Max(0, ($o.Top - $ds.Y) / [Math]::Max(1, $ds.Height - $o.Height)))
    $pan.Invalidate()
    Save-Osd
    $status.Text = "Место счётчика сохранено"
}
$bPlace = Add-Ctl $g2 (New-Object Windows.Forms.Button) 12 84 138 24
$bPlace.Text = "Разместить на экране"
$bPlace.Add_Click({ [void][Windows.Forms.MessageBox]::Show("Счётчик появится на рабочем столе: зажмите его мышью и перетащите. Esc или двойной щелчок - готово.", "FPS"); Show-OsdPlacer })

$g3 = Add-Ctl $f (New-Object Windows.Forms.GroupBox) 8 368 316 244 0
$g3.Text = "Задержка, ввод, логи, снимки"
function Add-Check($text, $y, $on, $tip) {
    $c = Add-Ctl $g3 (New-Object Windows.Forms.CheckBox) 12 $y 296 22
    $c.Text = $text; $c.Checked = [bool]$on; $tip1.SetToolTip($c, $tip); return $c
}
$tip1 = New-Object Windows.Forms.ToolTip; $tip1.AutoPopDelay = 20000
$chLow = Add-Check "Минимум задержки (VSync выкл., без Sleep)" 20 $cfg.lowlag "VSync=off в DDrawCompat.ini и SLEEP_TIME 0 в engine.ini: кадр не ждёт экран. Возможны разрывы картинки."
$chKeys = Add-Check "Повтор зажатых клавиш (без паузы)" 44 $cfg.keyrepeat "Хук игры сам повторяет зажатые стрелки, пробел и A-Z: убирает паузу автоповтора Windows (docs/input-latency.md)."
$chFine = Add-Check "Точный таймер кадра (экспериментально)" 68 $cfg.finetick "Время кадра по TSC вместо GetTickCount (шаг 15,6 мс). На этой игре давало инерцию после отпускания клавиши: по умолчанию выкл. (docs/frame-time.md)."
$chShot = Add-Check "F8: снимок экрана" 92 $cfg.screenshots "Скриншот в Документы\My Games\Sea Dogs\Screenshots"
$chVid = Add-Check "F9: запись видео" 116 $cfg.video "ffmpeg пишет рабочий стол в Screenshots; F9 ещё раз - стоп."
$chVid.Width = 150
$chAud = Add-Ctl $g3 (New-Object Windows.Forms.CheckBox) 166 116 140 22
$chAud.Text = "со звуком"; $chAud.Checked = [bool]$cfg.audio; $tip1.SetToolTip($chAud, "К видео добавляется звук колонок (то, что играет на выходе по умолчанию, включая другие программы). Если выключено, видео без звука.")
$chVid.Add_CheckedChanged({ $chAud.Enabled = $chVid.Checked }); $chAud.Enabled = $chVid.Checked
$chLog = Add-Check "Писать FPS в лог (fps.log)" 140 $cfg.fpslog "Строка статистики раз в 5 секунд в Документы\My Games\Sea Dogs\Logs\fps.log"
$chStat = Add-Check "Строки статистики в логе (F11)" 164 $cfg.statlog "Если выкл., в логе остаются только события: снимки, видео, ошибки."
$chSkip = Add-Check "Пропускать заставки (Esc сам)" 188 $cfg.skipintro "Ролики logo1/logo2 пропускаются сразу после запуска (Esc посылается игре). Вручную: Esc во время ролика или Shift при запуске."
$null = Add-Ctl $g3 (New-Text "Лимит FPS") 12 216 70 22
$cbFps = Add-Ctl $g3 (New-Object Windows.Forms.ComboBox) 86 216 130 22
$cbFps.Items.AddRange(@("Без ограничения", "30", "45", "60", "75", "90", "120", "144", "165", "240"))
$cbFps.Text = if ($cfg.fpslimit -gt 0) { "$($cfg.fpslimit)" } else { "Без ограничения" }
$tip1.SetToolTip($cbFps, "FpsLimiter=flipstart(N) в DDrawCompat.ini. Число можно ввести своё.")
$null = Add-Ctl $g3 (New-Text "кадров/с") 222 216 70 22

$status = Add-Ctl $f (New-Object Windows.Forms.Label) 8 618 316 44 0
$status.Text = "Игра: $GameDir"

function Save-Osd {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    [IO.File]::WriteAllLines($osdPath, @("x=" + ([double]$osd.x).ToString("0.000", $inv), "y=" + ([double]$osd.y).ToString("0.000", $inv), "size=" + [int]$nudOsd.Value))
}

function Save-Cfg {
    $lim = [regex]::Match("$($cbFps.Text)", "\d+").Value
    $cfg.lowlag = [int]$chLow.Checked; $cfg.keyrepeat = [int]$chKeys.Checked; $cfg.finetick = [int]$chFine.Checked
    $cfg.screenshots = [int]$chShot.Checked; $cfg.video = [int]$chVid.Checked; $cfg.audio = [int]$chAud.Checked; $cfg.fpslog = [int]$chLog.Checked; $cfg.statlog = [int]$chStat.Checked
    $cfg.osd = [int]$chOsd.Checked; $cfg.fontauto = [int]$auto.Checked; $cfg.frame = $frameVals[[Math]::Max(0, $cbFrame.SelectedIndex)]; $cfg.supersample = $ssVals[[Math]::Max(0, $cbSS.SelectedIndex)]; $cfg.thumb = [int]$chThumb.Checked; $cfg.skipintro = [int]$chSkip.Checked; $cfg.fpslimit = $(if ($lim) { [Math]::Min(1000, [int]$lim) } else { 0 })
    [IO.File]::WriteAllLines($cfgPath, @($cfg.Keys | ForEach-Object { "$_=$($cfg[$_])" }))
}

function Apply-Settings([switch]$Launch) {
    Save-Osd; Save-Cfg
    $parts = "$($cbRes.Text)".Trim() -split "[xх×]"
    if ($parts.Count -ne 2 -or -not ($parts[0] -as [int]) -or -not ($parts[1] -as [int])) { $status.Text = "Разрешение вида 1920x1080"; return }
    $cfg.outw = [int]$parts[0]; $cfg.outh = [int]$parts[1]; Save-Cfg
    $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Install, "-GameDir", $GameDir, "-Width", [int]$parts[0], "-Height", [int]$parts[1])
    if ((-not $chFull.Checked) -or $chThumb.Checked) { $psArgs += "-Windowed" }
    if ($cfg.supersample -gt 100) { $psArgs += @("-Supersample", ($cfg.supersample / 100.0).ToString([Globalization.CultureInfo]::InvariantCulture)) }
    if ($chWasd.Checked) { $psArgs += "-Wasd" }
    $psArgs += @("-FontScale", $(if ($auto.Checked) { "0" } else { ([double]$nud.Value).ToString([Globalization.CultureInfo]::InvariantCulture) }))
    $status.Text = "Применяю..."; $f.Refresh()
    $out = & powershell @psArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and $out -match "(?i)error|ошибк|exception") { $status.Text = "Ошибка: " + $out.Trim().Split("`n")[-1]; return $false }
    $status.Text = "Сохранено: $(if ($chThumb.Checked) { "окно " })$($cbRes.Text)$(if ($cfg.supersample -gt 100) { " x$($cfg.supersample / 100.0)" }), шрифт ×$(if ($auto.Checked) { 'авто' } else { $nud.Value })"
    if ($Launch) {
        Start-Process wscript.exe -ArgumentList "`"$(Join-Path $Here "play.vbs")`""   # профиль, хук, логи и запись по fix.ini; просит права администратора для PresentMon
    }
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

# the first group grew by 24 px: everything under it (left column) moves down, the form too
foreach ($c in $f.Controls) { if ($c -ne $g -and $c.Left -lt 330 -and $c.Top -ge 190) { $c.Top += 24 } }
$f.ClientSize = New-Object Drawing.Size(422, 690)
[void]$f.ShowDialog()
