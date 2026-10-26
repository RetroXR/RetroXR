#!/usr/bin/env python3
"""Where each screen of a multi-screen game stands in the picture MAME draws, read from MAME's own sources.

The core hands the cabinet ONE frame: MAME draws the first of the game's views that shows every screen (libretro-mame takes
`render_target`'s first view with all the screens, `render.cpp` `view_for_screen`), so a two-screen game arrives as two pictures in
one frame and which part is which depends on the LAYOUT the driver names. `-listxml` carries neither the layout nor where it puts
the screens, so this reads them:

    python Tools/arcade/layouts.py <MAME src/mame folder> <mame -listxml> [--layouts=<folder of .lay files>,...] [--out Tools/arcade/layouts.json] [--report]

For every runnable machine that takes a coin and has two or more `<display>`s it finds the driver's layout (the last argument of its
`GAMEL(...)`, else the `set_default_layout(layout_...)` of its machine configuration, calls to the configurations it builds on followed),
opens that layout's `.lay` file (default: `<folder>/layout` and `<folder>/../emu/layout`, which is where a checkout keeps them) and takes
the first `<view>` that has every screen: each screen's bounds, in the layout's own units, in screen order. A machine with no layout of its
own, or whose layout has no view of every screen, gets what MAME generates for it, the "Left-to-Right" view: every screen in a unit square
(a 4:3 screen 1 x 0.75, a rotated one 0.75 x 1) in a row with a gap of 1% of the smaller side (`render_target::load_layout_files`).
The output is sorted, so a run on the same sources is byte for byte the same:

    {"layouts": {"dualhsxs": {"view": "Dual Side-by-Side", "rects": [[0, 0, 4, 3], [4.03, 0, 4, 3]]}, ...},
     "romsets": {"sscope": "dualhsxs", ...}}

`gen_game_index.py` turns it into the table's `c` attribute. A layout this cannot read (a view that nests its screens in groups or
parameters) is listed at the end and treated as the generated one, which is right for the shape of the frame and wrong for which part is which.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))

GAME_START = re.compile(r"^\s*(?:/\*.*?\*/\s*)?(GAME|GAMEL|GAMEB|GAMEBL|GAMEC|GAMES)\s*\(", re.M)
# Machines whose configuration builds on another's (`sscope2` calls `sscope(config)`): followed this many calls deep.
CALL_DEPTH = 4


def macro_args(text, open_paren):
    """The top-level arguments of the macro whose `(` is at `open_paren`, quotes and nested parentheses respected."""
    args = []
    depth = 0
    current = []
    quote = ""
    i = open_paren
    while i < len(text):
        c = text[i]
        if quote:
            current.append(c)
            if c == "\\":
                i += 1
                current.append(text[i])
            elif c == quote:
                quote = ""
        elif c in "\"'":
            quote = c
            current.append(c)
        elif c == "(":
            depth += 1
            if depth > 1:
                current.append(c)
        elif c == ")":
            depth -= 1
            if depth == 0:
                args.append("".join(current).strip())
                return args
            current.append(c)
        elif c == "," and depth == 1:
            args.append("".join(current).strip())
            current = []
        else:
            current.append(c)
        i += 1
    return args


def game_rows(text):
    """{romset: (machine config function, layout name or None)} for every GAME-type macro of a driver."""
    out = {}
    for m in GAME_START.finditer(text):
        args = macro_args(text, m.end() - 1)
        if len(args) < 9:
            continue
        layout = None
        if args[-1].startswith("layout_"):
            layout = args[-1][len("layout_"):]
        out[args[1]] = (args[3], layout)
    return out


def function_body(text, name):
    """The body of `void <Class>::<name>(machine_config &config)`, or None."""
    m = re.search(r"void\s+\w+::" + re.escape(name) + r"\s*\(\s*machine_config\s*&\s*config\s*\)\s*\{", text)
    if not m:
        return None
    depth = 1
    i = m.end()
    while i < len(text) and depth:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    return text[m.end():i - 1]


def config_layout(text, name, depth=0):
    """The layout a machine configuration sets, following the configurations it calls, or None."""
    if depth > CALL_DEPTH:
        return None
    body = function_body(text, name)
    if body is None:
        return None
    found = None
    for m in re.finditer(r"set_default_layout\s*\(\s*layout_(\w+)\s*\)", body):
        found = m.group(1)
    if found:
        return found
    for m in re.finditer(r"^\s*(\w+)\s*\(\s*config\s*\)\s*;", body, re.M):
        inner = config_layout(text, m.group(1), depth + 1)
        if inner:
            return inner
    return None


def number(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def bounds_of(node):
    """[x, y, w, h] of a `<bounds>` child (x/y/width/height or left/top/right/bottom), or None."""
    b = node.find("bounds")
    if b is None:
        return None
    if any("~" in str(v) for v in b.attrib.values()):
        return None
    if "width" in b.attrib or "x" in b.attrib:
        return [number(b.get("x")), number(b.get("y")), number(b.get("width")), number(b.get("height"))]
    left, top = number(b.get("left")), number(b.get("top"))
    return [left, top, number(b.get("right")) - left, number(b.get("bottom")) - top]


def trim(v):
    v = round(v, 4)
    return int(v) if v == int(v) else v


def read_layout(path, displays):
    """(view name, [[x, y, w, h] per display in order]) for the first view that shows every display, or None."""
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        return None
    tags = [d["tag"].lstrip(":") for d in displays]
    for view in root.iter("view"):
        slots = {}
        readable = True
        # A view that nests items in groups or repeats (a golf machine's LED matrices) lays out more than its screens: the frame is not theirs
        # alone and working it out means evaluating the layout's parameters, so it is left to the generated one. (A `collection` only toggles
        # overlays that sit on the screens, like the shifter of a driving game: it does not move them.)
        if any(child.tag in ("group", "repeat") for child in view):
            continue
        for screen in view.findall("screen"):
            b = bounds_of(screen)
            if b is None:
                readable = False
                break
            if "index" in screen.attrib:
                slots[int(screen.get("index"))] = b
            elif "tag" in screen.attrib:
                t = screen.get("tag").lstrip(":")
                hit = [i for i, d in enumerate(tags) if d == t or d.endswith(":" + t) or d.endswith("." + t)]
                if hit:
                    slots[hit[0]] = b
        if not readable or set(slots) != set(range(len(displays))):
            continue
        return view.get("name", ""), [[trim(v) for v in slots[i]] for i in range(len(displays))]
    return None


def generated(displays):
    """MAME's own "Left-to-Right" view: every screen in a unit square in a row, 1% apart (render_target::load_layout_files)."""
    sizes = []
    for d in displays:
        rotated = d["rotate"] in (90, 270)
        sizes.append((0.75, 1.0) if rotated else (1.0, 0.75))
    spacing = 0.01 * min(max(s[0] for s in sizes), max(s[1] for s in sizes))
    rects = []
    x = 0.0
    height = max(s[1] for s in sizes)
    for w, h in sizes:
        rects.append([trim(x), trim((height - h) / 2), trim(w), trim(h)])
        x += w + spacing
    return "Left-to-Right", rects


def arcade_multi(xml_path):
    """{romset: {"source", "displays": [{"tag", "rotate"}]}} for every runnable machine that takes a coin and has two or more displays."""
    out = {}
    for _ev, el in ET.iterparse(xml_path, events=("end",)):
        if el.tag != "machine":
            continue
        if el.get("isdevice") == "yes" or el.get("isbios") == "yes" or el.get("runnable", "yes") == "no":
            el.clear()
            continue
        inp = el.find("input")
        displays = el.findall("display")
        if inp is not None and int(inp.get("coins", "0") or 0) >= 1 and len(displays) >= 2:
            out[el.get("name")] = {
                "source": el.get("sourcefile", ""),
                "displays": [{"tag": d.get("tag", ""), "rotate": int(d.get("rotate", "0") or 0)} for d in displays],
            }
        el.clear()
    return out


def find_layout_file(name, folders):
    for folder in folders:
        path = os.path.join(folder, name + ".lay")
        if os.path.isfile(path):
            return path
    return ""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = [a for a in sys.argv[1:] if a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    folder, xml_path = args
    out_path = os.path.join(HERE, "layouts.json")
    lay_folders = [os.path.join(folder, "layout"), os.path.join(folder, "..", "emu", "layout")]
    for o in opts:
        if o.startswith("--out="):
            out_path = o.split("=", 1)[1]
        elif o.startswith("--layouts="):
            lay_folders = o.split("=", 1)[1].split(",")
    machines = arcade_multi(xml_path)
    drivers = {}
    layouts = {}
    romsets = {}
    unread = {}
    missing = []
    for romset, m in sorted(machines.items()):
        source = m["source"]
        if source not in drivers:
            path = os.path.join(folder, source)
            if not os.path.isfile(path):
                flat = os.path.join(folder, source.replace("/", "__"))
                path = flat if os.path.isfile(flat) else ""
            if path:
                with open(path, errors="replace") as f:
                    text = f.read()
                drivers[source] = (text, game_rows(text))
            else:
                drivers[source] = None
        entry = drivers[source]
        if entry is None:
            missing.append(romset)
            continue
        text, rows = entry
        machine, layout = rows.get(romset, (None, None))
        if layout is None and machine:
            layout = config_layout(text, machine)
        read = None
        if layout:
            path = find_layout_file(layout, lay_folders)
            if path:
                read = read_layout(path, m["displays"])
            if read is None:
                unread.setdefault(layout, []).append(romset)
        if read is None:
            rot = "".join("r" if d["rotate"] in (90, 270) else "u" for d in m["displays"])
            key = "default-" + rot
            if key not in layouts:
                layouts[key] = dict(zip(("view", "rects"), generated(m["displays"])))
            romsets[romset] = key
        else:
            # The same layout file can lay out a different number of screens: key by name and count.
            key = "%s-%d" % (layout, len(m["displays"]))
            if key not in layouts:
                layouts[key] = {"view": read[0], "rects": read[1]}
            elif layouts[key]["rects"] != read[1]:
                key = key + "-" + "".join("r" if d["rotate"] in (90, 270) else "u" for d in m["displays"])
                layouts[key] = {"view": read[0], "rects": read[1]}
            romsets[romset] = key
        if "--report" in opts:
            print("%-14s %-26s %s" % (romset, source, romsets[romset]))
    with open(out_path, "w", newline="\n") as f:
        json.dump({"layouts": layouts, "romsets": romsets}, f, indent=1, sort_keys=True)
        f.write("\n")
    print("%d multi-screen machines, %d layouts -> %s" % (len(romsets), len(layouts), out_path))
    if unread:
        print("layouts with no readable view of every screen (the generated one is used): " + ", ".join(
            "%s (%d)" % (k, len(v)) for k, v in sorted(unread.items())))
    if missing:
        print("driver not found in the sources (not recorded): " + ", ".join(missing))


if __name__ == "__main__":
    main()
