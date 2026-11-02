#!/usr/bin/env python3
"""Builds dist/mecbook.koplugin-v<version>.zip with mecbook.koplugin/ at the zip root.

Usage: package.py [tag]   (when a tag is given, it must match VERSION in main.lua)
"""
import re
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
plugin = root / "mecbook.koplugin"
version = re.search(r'local VERSION = "([^"]+)"', (plugin / "main.lua").read_text(encoding="utf-8")).group(1)

if len(sys.argv) > 1 and sys.argv[1].lstrip("v") != version:
    sys.exit("tag %s does not match VERSION %s in main.lua" % (sys.argv[1], version))

out = root / "dist" / ("mecbook.koplugin-v%s.zip" % version)
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(plugin.rglob("*")):
        if f.is_file() and f.name != "mecbook_tokens.lua.sample":
            info = zipfile.ZipInfo("mecbook.koplugin/" + f.relative_to(plugin).as_posix(), (1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, f.read_bytes())
print(out)
