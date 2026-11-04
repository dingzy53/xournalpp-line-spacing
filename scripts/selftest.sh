#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Ding Zheng Yuan
# Run the in-app self test in a real Xournal++ with a throwaway config dir.
# Your own ~/.config/xournalpp is not touched. A Xournal++ window appears briefly.
#
# Needs lgi. If it is not installed system-wide, point LGI_ROOT at an unpacked
# lua-lgi RPM (dnf download lua-lgi && rpm2cpio lua-lgi*.rpm | cpio -idm).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/config/xournalpp/plugins"
ln -s "$here/LineSpacing" "$tmp/config/xournalpp/plugins/LineSpacing"
ln -s "$here/tests/selftest" "$tmp/config/xournalpp/plugins/LineSpacingSelfTest"
cp "$here/tests/fixtures/spacing.xopp" "$tmp/doc.xopp"

if [[ -n "${LGI_ROOT:-}" ]]; then
  export LUA_PATH="$LGI_ROOT/usr/share/lua/5.4/?.lua;$LGI_ROOT/usr/share/lua/5.4/?/init.lua;;"
  export LUA_CPATH="$LGI_ROOT/usr/lib64/lua/5.4/?.so;;"
fi

export LS_PLUGIN_DIR="$here/LineSpacing" LS_DOC="$tmp/doc.xopp" LS_OUT="$tmp/result.txt"
XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_DATA_HOME="$tmp/data" \
  timeout "${SELFTEST_TIMEOUT:-60}" xournalpp >"$tmp/xournalpp.log" 2>&1 && rc=0 || rc=$?

cat "$tmp/result.txt" 2>/dev/null || echo "no result file"
if grep -qi "lua\|plugin" "$tmp/xournalpp.log"; then
  echo "--- xournalpp log (plugin/lua lines) ---"
  grep -i "lua\|plugin" "$tmp/xournalpp.log" | head -20
fi

# persisted config in the saved .xopp (gzip)
echo "--- saved backgrounds ---"
gzip -dc "$tmp/doc.xopp" 2>/dev/null | grep -o '<background[^>]*>' || grep -o '<background[^>]*>' "$tmp/doc.xopp"

echo "--- xournalpp exit code: $rc (0 = clean quit, 124 = timeout, >128 = crash)"
grep -q "DONE failures=0" "$tmp/result.txt" && [[ $rc -eq 0 ]]
