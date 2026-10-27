/// Domain decisions stay in Dart. These detached OS adapters only wait for that
/// process, swap prepared directories and launch; arguments are always literal.
// Built-in macOS bridge to renamex_np(RENAME_EXCL). Plain mv can nest a source
// inside a destination directory that appeared after a check.
const macExclusiveRenameScript = r'''
ObjC.bindFunction('renamex_np', ['int', ['char *', 'char *', 'unsigned int']]);
function run(args) {
  if (args.length !== 2 || $.renamex_np(args[0], args[1], 4) !== 0) {
    throw new Error('Exclusive application rename failed; existing destinations were kept.');
  }
}
''';

const unixUpdateHelper = r'''#!/bin/sh
set -eu
parent_pid=$1; target=$2; payload=$3; backup=$4; stage=$5; platform=$6; claim=$7
exec >>"$stage/install.log" 2>&1
release_claim() {
  if [ -f "$claim" ] && [ "$(cat "$claim")" = "$stage" ]; then rm "$claim"; fi
}
finish() {
  status=$?
  if [ "$status" -ne 0 ]; then touch "$stage/failed"; fi
  release_claim
}
trap finish EXIT
kernel=$(/usr/bin/uname -s)
move() {
  if [ "$kernel" = Darwin ]; then
    /usr/bin/osascript -l JavaScript "$stage/rename.js" "$1" "$2"
  else
    source_device=$(/usr/bin/stat -c %d "$1") || return 1
    destination_device=$(/usr/bin/stat -c %d "$(/usr/bin/dirname "$2")") || return 1
    [ "$source_device" = "$destination_device" ] || return 1
    /bin/mv -T -n "$1" "$2" && [ ! -e "$1" ]
  fi
}
launch() {
  if [ "$platform" = macos ]; then /usr/bin/open "$target"
  else
    [ -x "$target/broomm" ] || return 1
    (cd "$target" && ./broomm >/dev/null 2>&1 &)
  fi
}
parent_start=$(LC_ALL=C /bin/ps -p "$parent_pid" -o lstart=) || exit 1
[ -n "$parent_start" ] || exit 1
touch "$stage/ready"
count=0
while [ "$(LC_ALL=C /bin/ps -p "$parent_pid" -o lstart= 2>/dev/null || true)" = "$parent_start" ]; do
  [ ! -e "$stage/cancel" ] || exit 0
  count=$((count+1)); [ "$count" -lt 180 ] || exit 1
  sleep 1
done
[ ! -e "$stage/cancel" ] && [ -f "$stage/commit" ] || exit 0
[ ! -e "$backup" ] && [ -d "$payload" ] && [ -d "$target" ] || exit 1
if ! move "$target" "$backup"; then launch || true; exit 1; fi
if ! move "$payload" "$target"; then move "$backup" "$target"; launch || true; exit 1; fi
if ! launch; then
  move "$target" "$payload"; move "$backup" "$target"; launch || true; exit 1
fi
touch "$stage/installed"
''';

const windowsUpdateHelper = r'''
param([int]$ParentId,[string]$Target,[string]$Payload,[string]$Backup,[string]$Stage,[string]$Platform,[string]$Claim)
$ErrorActionPreference='Stop'
try {
  $parent=Get-Process -Id $ParentId -ErrorAction Stop
  $handle=$parent.Handle
  Set-Content -LiteralPath (Join-Path $Stage 'ready') -Value 'ready'
  for($i=0;$i -lt 180;$i++) {
    if(Test-Path -LiteralPath (Join-Path $Stage 'cancel')){exit 0}
    if($parent.HasExited){break}
    Start-Sleep -Seconds 1
  }
  if($parent.HasExited -eq $false){throw 'Broomm is still running'}
  if((Test-Path -LiteralPath (Join-Path $Stage 'cancel')) -or -not (Test-Path -LiteralPath (Join-Path $Stage 'commit'))){exit 0}
  if(Test-Path -LiteralPath $Backup){throw 'Backup already exists'}
  [System.IO.Directory]::Move($Target,$Backup)
  try {[System.IO.Directory]::Move($Payload,$Target)}
  catch {[System.IO.Directory]::Move($Backup,$Target);Start-Process -FilePath (Join-Path $Target 'broomm.exe') -WorkingDirectory $Target;throw}
  try {Start-Process -FilePath (Join-Path $Target 'broomm.exe') -WorkingDirectory $Target}
  catch {[System.IO.Directory]::Move($Target,$Payload);[System.IO.Directory]::Move($Backup,$Target);Start-Process -FilePath (Join-Path $Target 'broomm.exe') -WorkingDirectory $Target;throw}
  Set-Content -LiteralPath (Join-Path $Stage 'installed') -Value 'installed'
} catch {$_ | Out-File -LiteralPath (Join-Path $Stage 'install.log');Set-Content -LiteralPath (Join-Path $Stage 'failed') -Value 'failed';exit 1}
finally {
  if((Test-Path -LiteralPath $Claim) -and ((Get-Content -Raw -LiteralPath $Claim).TrimEnd([char[]]"`r`n") -eq $Stage)) {Remove-Item -LiteralPath $Claim}
}
''';
