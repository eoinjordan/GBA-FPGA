# Windows launcher for scripts\gbafpga.py: finds Python 3 and forwards all
# arguments.  Example:  .\scripts\gbafpga.ps1 build gba_lcd_480x272
# The WindowsApps "python" entries are Microsoft Store stubs, so they are skipped.

$ErrorActionPreference = 'Stop'
$Script = Join-Path $PSScriptRoot 'gbafpga.py'

$Launcher = Get-Command py -ErrorAction SilentlyContinue
if ($Launcher) {
    & $Launcher.Source -3 $Script @args
    exit $LASTEXITCODE
}

$Python = Get-Command python, python3 -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -notlike '*\WindowsApps\*' } |
    Select-Object -First 1
if (-not $Python) {
    throw 'Python 3.8+ is required: https://www.python.org/downloads/ (tick "Add python.exe to PATH").'
}
& $Python.Source $Script @args
exit $LASTEXITCODE
