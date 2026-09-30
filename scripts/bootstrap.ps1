# Clone upstream projects into external\ at the versions pinned in UPSTREAMS.json.
#   .\scripts\bootstrap.ps1                  everything
#   .\scripts\bootstrap.ps1 gbtang snestang  only the Tang Nano 20K cores
& (Join-Path $PSScriptRoot 'gbafpga.ps1') bootstrap @args
exit $LASTEXITCODE
