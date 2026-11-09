#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# checkout_onair.sh - put OnAir's clang_and_packaging branch in ./OnAir (next to this script; ignored by this repository).
# A first run clones it; a later run brings it up to date, and stops rather than overwrite local changes.
#
#   ONAIR_URL     default: https://github.com/peterdewitte/OnAir.git
#   ONAIR_BRANCH  default: clang_and_packaging
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL=${ONAIR_URL:-https://github.com/peterdewitte/OnAir.git}
BRANCH=${ONAIR_BRANCH:-clang_and_packaging}
DIR="$ROOT/OnAir"

if [ -d "$DIR/.git" ]; then
  git -C "$DIR" fetch --depth 1 origin "$BRANCH"
  [ -z "$(git -C "$DIR" status --porcelain --untracked-files=no)" ] || { echo "error: $DIR has local changes: commit them or remove the folder" >&2; exit 1; }
  git -C "$DIR" checkout -q "$BRANCH"
  git -C "$DIR" reset -q --hard FETCH_HEAD
else
  [ ! -e "$DIR" ] || { echo "error: $DIR exists and is not a git checkout" >&2; exit 1; }
  git clone --depth 1 --single-branch --branch "$BRANCH" "$URL" "$DIR"
fi
git -C "$DIR" log -1 --format='OnAir %h (%s)'
