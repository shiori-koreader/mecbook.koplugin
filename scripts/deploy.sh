#!/usr/bin/env bash
set -euo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)/mecbook.koplugin"
dest="/d/koreader/plugins/mecbook.koplugin"
[ -d /d/koreader/plugins ] || { echo "Kindle not mounted at /d/" >&2; exit 1; }
rm -rf "$dest"
cp -r "$src" "$dest"
rm -f "$dest/mecbook_tokens.lua.sample"
echo "Deployed to $dest"
