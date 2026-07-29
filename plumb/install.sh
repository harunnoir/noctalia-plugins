#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$DATA_HOME/noctalia/plugins/plumb"
ACTIONS_DIR="$CONFIG_HOME/noctalia/plumb"
ACTIONS_FILE="$ACTIONS_DIR/actions.json"
BIN_DIR="${PLUMB_BIN_DIR:-$HOME/bin}"
PLUMB_BIN="$BIN_DIR/plumb"

missing=()
command -v wl-paste >/dev/null 2>&1 || missing+=(wl-clipboard)
command -v xdg-open >/dev/null 2>&1 || missing+=(xdg-utils)
command -v noctalia >/dev/null 2>&1 || missing+=(noctalia)
command -v python3 >/dev/null 2>&1 || missing+=(python3)

if ((${#missing[@]})); then
    printf 'Missing commands/packages: %s\n' "${missing[*]}" >&2
    printf 'On Void Linux, install the available dependencies with:\n' >&2
    printf '  sudo xbps-install -S wl-clipboard xdg-utils libnotify python3\n\n' >&2
fi

if [[ -d "$PLUGIN_DIR" ]]; then
    plugin_backup="$PLUGIN_DIR.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$PLUGIN_DIR" "$plugin_backup"
    printf 'Backed up existing plugin to %s\n' "$plugin_backup"
fi

mkdir -p -- "$PLUGIN_DIR/translations" "$ACTIONS_DIR" "$BIN_DIR"

if [[ -e "$PLUMB_BIN" ]]; then
    backup="$PLUMB_BIN.backup.$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$PLUMB_BIN" "$backup"
    printf 'Backed up existing plumb to %s\n' "$backup"
fi

install -m 0644 "$ROOT/plugin/plugin.toml" "$PLUGIN_DIR/plugin.toml"
install -m 0644 "$ROOT/plugin/panel.luau" "$PLUGIN_DIR/panel.luau"
install -m 0644 "$ROOT/plugin/default-actions.json" "$PLUGIN_DIR/default-actions.json"
install -m 0644 "$ROOT/plugin/translations/en.json" "$PLUGIN_DIR/translations/en.json"
install -m 0755 "$ROOT/bin/plumb" "$PLUMB_BIN"

if [[ ! -e "$ACTIONS_FILE" ]]; then
    install -m 0644 "$ROOT/plugin/default-actions.json" "$ACTIONS_FILE"
    printf 'Created editable actions tree: %s\n' "$ACTIONS_FILE"
else
    printf 'Kept your existing actions tree unchanged: %s\n' "$ACTIONS_FILE"
fi

printf 'Installed plugin: %s\n' "$PLUGIN_DIR"
printf 'Installed launcher: %s\n' "$PLUMB_BIN"

if command -v noctalia >/dev/null 2>&1; then
    noctalia msg plugins disable davamos/plumb >/dev/null 2>&1 || true
    if noctalia msg plugins enable davamos/plumb; then
        printf 'Enabled davamos/plumb in Noctalia.\n'
    else
        printf '\nNoctalia did not enable it automatically.\n' >&2
        printf 'Open Settings -> Plugins and enable "Plumb", or restart Noctalia and run:\n' >&2
        printf '  noctalia msg plugins enable davamos/plumb\n' >&2
    fi
else
    printf '\nNoctalia is not currently available on PATH. Enable the plugin later from Settings -> Plugins.\n'
fi

printf '\nEdit actions here:\n  %s\n' "$ACTIONS_FILE"
printf 'Select text and run:\n  %s\n' "$PLUMB_BIN"
