$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Pre-provisioned Visual C++ host is unavailable.' }
$build = Join-Path (Get-Location) 'build/native-cemu-windows'
New-Item -ItemType Directory -Force $build | Out-Null
$vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
$commands = @"
call "$vcvars"
cd /d "$build"
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /LD "$PWD/native/cemu_guard_windows.cpp" /Fe:broomm-cemu-guard.dll || exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT "$PWD/native/cemu_process_windows.cpp" /Fe:broomm-cemu-run.exe /link psapi.lib || exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT "$PWD/tool/fixtures/cemu_windows_test.cpp" /Fe:cemu-check.exe /link psapi.lib user32.lib || exit /b 1
cemu-check.exe "$build/broomm-cemu-run.exe" "$build/broomm-cemu-guard.dll" "$build/cemu-check.exe" "$build/private profile" || exit /b 1
"@
$script = Join-Path $build 'check.cmd'
Set-Content -Path $script -Value $commands
& cmd.exe /c $script
if ($LASTEXITCODE -ne 0) { throw "Cemu Windows check failed: $LASTEXITCODE" }
