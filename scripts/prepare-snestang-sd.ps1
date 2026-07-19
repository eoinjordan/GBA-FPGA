param(
  [Parameter(Mandatory=$true)][string]$RomPath,
  [Parameter(Mandatory=$true)][string]$SdRoot,
  [string]$CorePath
)
$ErrorActionPreference = "Stop"
$ScriptPath = Join-Path $PSScriptRoot "prepare-snestang-sd.py"
$Arguments = @($ScriptPath, $RomPath, $SdRoot)
if ($CorePath) { $Arguments += @("--core", $CorePath) }
python @Arguments
