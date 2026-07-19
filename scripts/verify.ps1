[CmdletBinding()]
param()

$Required = @('git', 'python', 'iverilog', 'vvp', 'ghdl')
$Optional = @('node', 'npm', 'gowin_sh', 'gw_sh', 'gh')
$Missing = $false

foreach ($Tool in $Required) {
    if (Get-Command $Tool -ErrorAction SilentlyContinue) {
        Write-Host "OK       $Tool"
    }
    else {
        Write-Host "MISSING  $Tool (required)"
        $Missing = $true
    }
}

foreach ($Tool in $Optional) {
    if (Get-Command $Tool -ErrorAction SilentlyContinue) {
        Write-Host "OK       $Tool"
    }
    else {
        Write-Host "OPTIONAL $Tool"
    }
}

if ($Missing) {
    throw 'One or more required tools are missing.'
}
