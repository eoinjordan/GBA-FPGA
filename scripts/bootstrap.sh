#!/bin/sh
# Clone upstream projects into external/ at the versions pinned in UPSTREAMS.json.
#   ./scripts/bootstrap.sh                  everything
#   ./scripts/bootstrap.sh gbtang snestang  only the Tang Nano 20K cores
exec "$(dirname "$0")/gbafpga.sh" bootstrap "$@"
