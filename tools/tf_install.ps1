<#
Puts the bigger textures (the output of tf_upscale.py) into the game or brings the originals back.
  tf_install.ps1 -GameDir "C:\Program Files\1C\Корсары" -From C:\path\tex_up        # needs the rights of an administrator
  tf_install.ps1 -GameDir "C:\Program Files\1C\Корсары" -Restore
The first run copies every file it replaces to <game>\RESOURCE\Textures_orig (a file that is already there stays: it is the
original, not the result of an earlier run).
#>
param([Parameter(Mandatory)][string]$GameDir, [string]$From, [switch]$Restore)
$tex = Join-Path $GameDir "RESOURCE\Textures"
$bak = Join-Path $GameDir "RESOURCE\Textures_orig"
if ($Restore) {
    if (-not (Test-Path $bak)) { throw "no ${bak}: nothing to restore" }
    Get-ChildItem $bak -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($bak.Length).TrimStart("\")
        Copy-Item $_.FullName (Join-Path $tex $rel) -Force
    }
    Write-Host "restored from $bak"
    return
}
if (-not $From -or -not (Test-Path $From)) { throw "-From <the folder with the new .tf> is needed" }
$n = 0
Get-ChildItem $From -Recurse -File -Filter *.tf | ForEach-Object {
    $rel = $_.FullName.Substring((Resolve-Path $From).Path.Length).TrimStart("\")
    $dst = Join-Path $tex $rel; $old = Join-Path $bak $rel
    if ((Test-Path $dst) -and -not (Test-Path $old)) { New-Item -ItemType Directory -Force (Split-Path $old) | Out-Null; Copy-Item $dst $old }
    Copy-Item $_.FullName $dst -Force; $n++
}
Write-Host "installed $n textures, originals in $bak"
