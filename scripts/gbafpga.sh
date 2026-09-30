#!/bin/sh
# Linux/macOS launcher for scripts/gbafpga.py: finds Python 3 and forwards
# all arguments.  Example:  ./scripts/gbafpga.sh build gba_lcd_480x272
set -eu
here=$(cd "$(dirname "$0")" && pwd)
python=${PYTHON:-}
if [ -z "$python" ]; then
    python=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
fi
if [ -z "$python" ]; then
    echo "error: Python 3.8+ is required (macOS: xcode-select --install or brew install python)" >&2
    exit 1
fi
exec "$python" "$here/gbafpga.py" "$@"
