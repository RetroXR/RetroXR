#!/usr/bin/env python3
"""Rename the systemids in a directory of libretro .info files to RetroXR's.

RetroXR's systemids are ES-DE's folder names (n64, snes, gb); libretro's .info
files say nintendo_64, super_nes, game_boy. RetroXR/libretro-core-info is a cp
mirror of the libretro-super fork, so a refresh from a fork that was not renamed
brings every old id back. Run this after one, or on the fork's dist/info itself:

    python Tools/rename_systemids.py RetroXR/libretro-core-info RetroXR/libretro-core-info-retroxr
    python Tools/rename_systemids.py --check RetroXR/libretro-core-info    # exits 1 if any are left
    python Tools/rename_systemids.py ../libretro-super/dist/info

Only two lines of a file are touched: `systemid = "..."`, and the id left of each
colon in `secondary_systemids = "id:ext,ext|id:ext"`. Nothing else in a .info is
a systemid, whatever it looks like (`database`, `systemname`, firmware paths).

The table is not kept here. It is read out of SystemIds.LEGACY, so there is one.
"""
import argparse
import re
import sys
from pathlib import Path

TABLE = Path(__file__).resolve().parent.parent / "RetroXR/Scripts/Data/systems/system_ids.gd"


def load_legacy() -> dict[str, str]:
    text = TABLE.read_text(encoding="utf-8")
    body = re.search(r"const LEGACY: Dictionary = \{(.*?)\n\}", text, re.S)
    if not body:
        sys.exit(f"no LEGACY table in {TABLE}")
    legacy = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', body.group(1)))
    if not legacy:
        sys.exit(f"LEGACY table in {TABLE} is empty")
    return legacy


LINE = re.compile(r'^(\s*)(systemid|secondary_systemids)(\s*=\s*")([^"]*)(".*)$')


def rename_value(key: str, value: str, legacy: dict[str, str]) -> str:
    if key == "systemid":
        return legacy.get(value, value)
    parts = []
    for part in value.split("|"):
        sid, colon, exts = part.partition(":")
        lead = sid[: len(sid) - len(sid.lstrip())]
        parts.append(lead + legacy.get(sid.strip(), sid.strip()) + colon + exts)
    return "|".join(parts)


def process(path: Path, legacy: dict[str, str], write: bool) -> list[str]:
    raw = path.read_bytes().decode("utf-8", errors="surrogateescape")
    lines = raw.splitlines(keepends=True)
    changes = []
    for i, line in enumerate(lines):
        m = LINE.match(line.rstrip("\r\n"))
        if not m:
            continue
        new_value = rename_value(m.group(2), m.group(4), legacy)
        if new_value == m.group(4):
            continue
        ending = line[len(line.rstrip("\r\n")):]
        lines[i] = m.group(1) + m.group(2) + m.group(3) + new_value + m.group(5) + ending
        changes.append(f"{path.name}: {m.group(2)} {m.group(4)} -> {new_value}")
    if changes and write:
        path.write_bytes("".join(lines).encode("utf-8", errors="surrogateescape"))
    return changes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dirs", nargs="+", type=Path, help="directories of .info files")
    ap.add_argument("--check", action="store_true", help="change nothing; exit 1 if an old id is found")
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args()

    legacy = load_legacy()
    changes = []
    for d in args.dirs:
        if not d.is_dir():
            sys.exit(f"not a directory: {d}")
        for path in sorted(d.glob("*.info")):
            changes += process(path, legacy, write=not args.check)
    if not args.quiet:
        for c in changes:
            print(c)
    verb = "would change" if args.check else "changed"
    print(f"{verb} {len(changes)} line(s)")
    return 1 if (args.check and changes) else 0


if __name__ == "__main__":
    sys.exit(main())
