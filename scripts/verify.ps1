# Report which tools are installed and what this machine can build or flash.
& (Join-Path $PSScriptRoot 'gbafpga.ps1') doctor @args
exit $LASTEXITCODE
