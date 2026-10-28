#!/bin/bash
: "${WIN_HOST:?задайте WIN_HOST}" "${WIN_USER:?задайте WIN_USER}" "${WIN_KEY:?задайте WIN_KEY}"
# usage: t.sh <frame>  — sets frame=, runs the game through autotest, prints the result
S="ssh -i $WIN_KEY $WIN_USER@$WIN_HOST"
cat > ${TMPDIR:-/tmp}/sf.ps1 <<EOP
\$f = "C:\\Program Files\\1C\\Корсары\\fix\\fix.ini"
\$l = @(Get-Content \$f | ? { \$_ -notmatch "^(frame|autotest)=" }); \$l += "frame=$1"; \$l += "autotest=$2"; \$l | Set-Content \$f
EOP
printf '\xef\xbb\xbf' | cat - ${TMPDIR:-/tmp}/sf.ps1 > ${TMPDIR:-/tmp}/sfb.ps1
scp -i "$WIN_KEY" ${TMPDIR:-/tmp}/sfb.ps1 "$WIN_USER@$WIN_HOST":C:/Users/User/cof/sf.ps1 >/dev/null
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\sf.ps1'
n0=$($S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\l10.ps1' 2>&1 | grep -c "autotest: Down")
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\runauto.ps1' >/dev/null 2>&1
for i in $(seq 15); do sleep 3; n=$($S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\l10.ps1' 2>&1 | grep -c "autotest: Down"); [ "$n" -gt "$n0" ] && break; done
$S 'powershell -ExecutionPolicy Bypass -File C:\Users\User\cof\l10.ps1' 2>&1 | grep "autotest" | tail -2
