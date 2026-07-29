#!/usr/bin/env bash
set -Eeuo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PLUGIN_DIR="$DATA_HOME/noctalia/plugins/plumb"
BIN_DIR="${PLUMB_BIN_DIR:-$HOME/bin}"

if command -v noctalia >/dev/null 2>&1; then
    noctalia msg plugins disable davamos/plumb >/dev/null 2>&1 || true
fi

rm -rf -- "$PLUGIN_DIR"
if [[ -e "$BIN_DIR/plumb" ]]; then
    removed="$BIN_DIR/plumb.removed.$(date +%Y%m%d-%H%M%S)"
    mv -- "$BIN_DIR/plumb" "$removed"
    printf 'Moved launcher to %s\n' "$removed"
fi
printf 'Removed Plumb plugin and launcher. Existing backups and notes were left untouched.\n'
