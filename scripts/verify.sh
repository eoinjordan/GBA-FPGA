#!/bin/sh
# Report which tools are installed and what this machine can build or flash.
exec "$(dirname "$0")/gbafpga.sh" doctor "$@"
