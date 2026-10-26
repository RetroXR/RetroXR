#!/usr/bin/env python3
"""Print what MAME's own driver says a game's controls are.

The table (`gen_game_index.py`) knows a game's controls by KIND, from `-listxml`. What the controls are CALLED, which analog
axis each is, its range and whether it keeps its place when let go, is in the driver source's `INPUT_PORTS_START` block, which
`-listxml` does not carry. This reads those, for the cabinets docs/dev/arcade-cabinets.md talks about:

    python Tools/arcade/mame_inputs.py <folder of MAME driver sources> panicprk propcycl sscope ...

The folder is a checkout of `src/mame` (or any folder holding the `.cpp` drivers, flat or nested; the 0.289 sources are at
https://github.com/mamedev/mame/tree/mame0289/src/mame). Each romset is looked up by its `GAME(...)` line, which names its
input ports, and that block is printed with every `PORT_INCLUDE` followed: the analog controls (type, `PORT_NAME`, range, the
flags that matter) and the named digital ones. A clone is looked up as itself. It says nothing of the game's behaviour.
"""
import os
import re
import sys

GAME_RE = re.compile(r"^\s*(?:GAME|GAMEL|GAMEB|GAMEBL|GAMEC|GAMES)\s*\(\s*[^,]+,\s*(\w+)\s*,\s*(\w+)\s*,\s*([^,]+),\s*(\w+)\s*,", re.M)
ANALOG_RE = re.compile(r"IPT_(AD_STICK_[XYZ]|PADDLE_V|PADDLE|PEDAL\d?|DIAL_V|DIAL|TRACKBALL_[XY]|LIGHTGUN_[XY]|POSITIONAL_V|POSITIONAL|MOUSE_[XY])")
DIGITAL_RE = re.compile(r"IPT_(BUTTON\d+|JOYSTICK_(?:UP|DOWN|LEFT|RIGHT)|START\d|COIN\d|SERVICE\d?|TILT|BILL1)")
FLAGS = ("PORT_REVERSE", "PORT_INVERT", "PORT_CENTERDELTA(0)", "PORT_TOGGLE", "PORT_PLAYER(2)", "PORT_PLAYER(3)", "PORT_PLAYER(4)")


def sources(folder):
    for root, _dirs, files in os.walk(folder):
        for name in sorted(files):
            if name.endswith(".cpp"):
                yield os.path.join(root, name)


def find_game(folder, romset):
    """(file text, the name of its input ports) for a romset, or None."""
    for path in sources(folder):
        with open(path, errors="replace") as f:
            text = f.read()
        for m in GAME_RE.finditer(text):
            if m.group(1) == romset:
                return path, text, m.group(4)
    return None


def block(text, name):
    m = re.search(r"INPUT_PORTS_START\s*\(\s*" + re.escape(name) + r"\s*\)(.*?)INPUT_PORTS_END", text, re.S)
    return m.group(1) if m else None


def lines_of(text, name, seen=None, depth=0):
    """[(the block a line came from, the line)] for a block and, after its own lines, those of every block it includes."""
    seen = seen if seen is not None else set()
    if name in seen or depth > 5:
        return []
    seen.add(name)
    body = block(text, name)
    if body is None:
        return [(name, "??")]
    own = []
    included = []
    for line in body.split("\n"):
        line = re.sub(r"\s+", " ", line.strip())
        if not line or line.startswith("//"):
            continue
        include = re.match(r"PORT_INCLUDE\s*\(\s*(\w+)\s*\)", line)
        if include:
            included.extend(lines_of(text, include.group(1), seen, depth + 1))
        elif ANALOG_RE.search(line) or DIGITAL_RE.search(line):
            own.append((name, line))
    return own + included


def describe(line):
    analog = ANALOG_RE.search(line)
    digital = DIGITAL_RE.search(line)
    kind = (analog or digital).group(1)
    name = re.search(r'PORT_NAME\("([^"]*)"\)', line)
    span = re.search(r"PORT_MINMAX\(([^)]*)\)", line)
    flags = [f for f in FLAGS if f in line]
    return "%s%s%s%s" % (kind, (' "%s"' % name.group(1)) if name else "", (" [%s]" % span.group(1)) if span else "",
        (" " + " ".join(flags)) if flags else "")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    folder = sys.argv[1]
    for romset in sys.argv[2:]:
        found = find_game(folder, romset)
        if found is None:
            print("%s: no GAME line in any .cpp under %s" % (romset, folder))
            continue
        path, text, ports = found
        print("%s  (%s, INPUT_PORTS %s)" % (romset, os.path.relpath(path, folder), ports))
        shown = set()
        for origin, line in lines_of(text, ports):
            if line == "??":
                print("    (INPUT_PORTS_START(%s) is not in this file: an include from another driver?)" % origin)
                continue
            # Another block's own bits (the board's base) are noise unless they are analog or named.
            if origin != ports and not ANALOG_RE.search(line) and "PORT_NAME" not in line:
                continue
            row = describe(line) + ("" if origin == ports else "   (from %s)" % origin)
            if row not in shown:
                shown.add(row)
                print("    " + row)


if __name__ == "__main__":
    main()
