#!/usr/bin/env bash
# Render a .xopp file to PDF + PNGs headlessly, for checking background configs.
# Usage: scripts/render-check.sh [file.xopp] [outdir]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
in="${1:-$here/tests/fixtures/spacing.xopp}"
out="${2:-$here/out}"
mkdir -p "$out"
base="$(basename "${in%.*}")"
xournalpp --create-pdf="$out/$base.pdf" "$in" >/dev/null 2>&1
pdftoppm -png -r 40 "$out/$base.pdf" "$out/$base"
ls "$out/$base"*.png
