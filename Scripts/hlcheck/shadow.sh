#!/usr/bin/env bash
# Run the prebuilt hlcheck harness against the query files of ANOTHER checkout
# (a worktree) without rebuilding anything.
#
#   Scripts/hlcheck/shadow.sh <checkout-dir> <file> [hlcheck args...]
#
# The binary looks for CodeEditLanguages_CodeEditLanguages.bundle next to
# itself first, so we hard-link the main build's binary into a scratch dir and
# put a shadow bundle beside it whose Resources/ is a real directory of
# per-grammar symlinks into <checkout-dir>'s query folders. (A symlinked
# Resources/ directory is not seen by CFBundle; a symlinked binary is resolved
# to its real path — hence real dir + hard link.)
set -euo pipefail
CHECKOUT="$(cd "$1" && pwd)"; shift
FILE="$1"; shift
# The main checkout: where the .git dir really lives (a worktree's .git is a
# file pointing there), overridable with HLCHECK_MAIN.
MAIN="${HLCHECK_MAIN:-$(dirname "$(cd "$CHECKOUT" && git rev-parse --path-format=absolute --git-common-dir)")}"
BIN="$MAIN/.build/debug/atelier-hlcheck"
[[ -x "$BIN" ]] || { echo "build the harness once in the main checkout: (cd $MAIN && swift build --product atelier-hlcheck)" >&2; exit 2; }
SHADOW="${HLCHECK_SHADOW_DIR:-${TMPDIR:-/tmp}/hlcheck-shadow-$(echo "$CHECKOUT" | shasum | cut -c1-8)}"
mkdir -p "$SHADOW/CodeEditLanguages_CodeEditLanguages.bundle/Resources"
ln -f "$(readlink -f "$BIN")" "$SHADOW/atelier-hlcheck" 2>/dev/null || cp "$(readlink -f "$BIN")" "$SHADOW/atelier-hlcheck"
SRC="$CHECKOUT/Vendor/CodeEditLanguages/Sources/CodeEditLanguages/Resources"
for dir in "$SRC"/tree-sitter-*; do
  ln -sfn "$dir" "$SHADOW/CodeEditLanguages_CodeEditLanguages.bundle/Resources/$(basename "$dir")"
done
exec "$SHADOW/atelier-hlcheck" "$FILE" "$@"
