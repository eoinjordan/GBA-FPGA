# FPGBA Tang 60K port status gate.
#
# This script intentionally refuses to create a bitstream until the platform
# adapter, memory controller, clocking, and exact constraints are present.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]
set upstream [file join $repo_root external FPGBA FPGA src]

if {![file isdirectory $upstream]} {
    error "Upstream FPGBA source not found. Run scripts/bootstrap.sh or scripts/bootstrap.ps1 first."
}

set required_files [list \
    [file join $upstream gba gba_top.vhd] \
    [file join $upstream top framebuffer.vhd] \
    [file join $script_dir rtl fpgba_platform_pkg.vhd] \
    [file join $script_dir rtl fpgba_tang60k_platform.vhd] \
]

foreach path $required_files {
    if {![file exists $path]} {
        error "Required source is missing: $path"
    }
}

error "Port scaffold is present, but no verified FPGBA-to-GW5AT core adapter, DDR3 bridge, PLL configuration, or board constraints exist yet. See docs/FPGBA_UNOFFICIAL_BUILD.md."
