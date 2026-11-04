#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Ding Zheng Yuan
# Install the LineSpacing plugin for the current user.
#   scripts/install.sh            symlink (development: edits take effect on restart)
#   scripts/install.sh --copy     copy files instead
#   scripts/install.sh --uninstall
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/LineSpacing"

flatpak_dir="$HOME/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins"
native_dir="${XDG_CONFIG_HOME:-$HOME/.config}/xournalpp/plugins"
if command -v xournalpp >/dev/null 2>&1 || [[ ! -d "$(dirname "$flatpak_dir")" ]]; then
  dest_dir="$native_dir"
else
  dest_dir="$flatpak_dir"
fi
dest="$dest_dir/LineSpacing"

case "${1:-}" in
  --uninstall)
    rm -rf "$dest"
    echo "Removed $dest (presets in plugin-settings/LineSpacing are kept)"
    exit 0 ;;
  --copy)
    mkdir -p "$dest_dir"; rm -rf "$dest"; cp -r "$src" "$dest" ;;
  "")
    mkdir -p "$dest_dir"; rm -rf "$dest"; ln -s "$src" "$dest" ;;
  *) echo "usage: $0 [--copy|--uninstall]" >&2; exit 2 ;;
esac
echo "Installed to $dest"

if [[ "$dest_dir" == "$native_dir" ]] && ! lua -e 'require("lgi")' >/dev/null 2>&1; then
  echo "Note: lua-lgi not found; the plugin will use its simpler fallback dialog."
  echo "      For the full settings window: sudo dnf install lua-lgi   (Debian/Ubuntu: sudo apt install lua-lgi)"
fi
echo "Restart Xournal++ and look in the Plugin menu for \"Line spacing: Configure…\" (Ctrl+Alt+S)."
