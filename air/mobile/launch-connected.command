#!/bin/zsh
set -eu
cd -- "${0:A:h}"
exec /opt/homebrew/bin/python3 run_connected.py "$@"
