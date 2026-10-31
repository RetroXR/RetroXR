#!/usr/bin/env python3
"""Which button a driving game's gear lever is, and whether MAME makes it a toggle, read from MAME's own driver sources.

The cabinet's gear lever has two positions. What it sends is the game's, not the cabinet's: a shifter MAME declares as
`PORT_TOGGLE` flips with every press of its button (Out Run, Final Lap), one that is not is held while the lever is high (the
button is down for as long as the lever is thrown), and which button it is differs from game to game (Out Run's gear shift is
button 3, Chase HQ's 4, Final Lap's 1). `-listxml` carries neither, so this reads the `INPUT_PORTS_START` blocks of the
drivers (`mame_inputs.py` is the same reader for one game at a time) and writes the answer where `gen_game_index.py` finds it:

    python Tools/arcade/shifters.py <folder of MAME driver sources> <mame -listxml> [--out Tools/arcade/shifters.json] [--report]

For every driving PARENT (a paddle or dial with a pedal, the rule `gen_game_index.py` files a game under `race`/`stand` by) it
finds the entry named like a gear change (`Gear Shift`, `Shift`, `High/Low`, `Gear`, `Speed`...) and records
`{"button": n, "toggle": bool, "name": "..."}`. A sequential gearbox ("Shift Up" and "Shift Down", two buttons) is `{"up": n, "down": m}`: the lever
taps one going high and the other going low. An H pattern (`Gear 1`... `Gear 4`, four or five buttons) is recorded as `{"gears": [buttons]}` for the
record and no lever is built for it: a two-position lever cannot say which of four gears. A game with no such entry is not in the file: it has no
shifter, and the cabinet draws none.
The output is sorted, so a run on the same sources is byte for byte the same.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mame_inputs as mi  # noqa: E402

SHIFT_NAME = re.compile(r"\b(gear|shift\w*|high|low|hi/lo|hi-lo|lo/hi|speed|transmission)\b", re.I)
SEQ_UP = re.compile(r"\b(up|high|hi|h)\b", re.I)
SEQ_DOWN = re.compile(r"\b(down|low|lo|l)\b", re.I)
GEAR_N = re.compile(r"\b(gear|speed|shift)\s*[1-6]\b|\b[1-6](st|nd|rd|th)\b", re.I)
ENTRY_START = re.compile(r"^(PORT_START|PORT_BIT|PORT_DIPNAME|PORT_CONFNAME|PORT_DIPSETTING|PORT_CONFSETTING|PORT_INCLUDE|PORT_MODIFY|"
                         r"PORT_SERVICE|PORT_SERVICE_NO_TOGGLE|PORT_CUSTOM_MEMBER|PORT_READ_LINE_DEVICE_MEMBER|PORT_READ_LINE_MEMBER|"
                         r"PORT_ADJUSTER|PORT_DIPLOCATION|PORT_UNUSED|PORT_UNKNOWN|PORT_BIT_FIELD)")


def entries(text, name, seen=None, depth=0):
    """Every entry of an input block, `PORT_INCLUDE`s followed, as one string each: a `PORT_BIT(...)` and the `PORT_NAME(...) PORT_TOGGLE`
    lines that continue it."""
    seen = seen if seen is not None else set()
    if name in seen or depth > 6:
        return []
    seen.add(name)
    body = mi.block(text, name)
    if body is None:
        return []
    out = []
    current = ""
    for raw in body.split("\n"):
        line = re.sub(r"\s+", " ", raw.strip())
        if not line or line.startswith("//"):
            continue
        include = re.match(r"PORT_INCLUDE\s*\(\s*(\w+)\s*\)", line)
        if include:
            if current:
                out.append(current)
                current = ""
            out.extend(entries(text, include.group(1), seen, depth + 1))
            continue
        # A new entry begins at a PORT_ macro that starts one; the others (PORT_NAME, PORT_TOGGLE...) belong to the entry before.
        if ENTRY_START.match(line) or line.startswith("INPUT_"):
            if current:
                out.append(current)
            current = line
        else:
            current = (current + " " + line) if current else line
    if current:
        out.append(current)
    return out


def shifter_of(text, ports):
    """{"button", "toggle", "name"} for a two-position shifter, {"up", "down"} for a sequential box, {"gears": [...]} for an H pattern, or None."""
    named = []
    for e in entries(text, ports):
        m = re.search(r"IPT_BUTTON(\d+)", e)
        if not m:
            continue
        name = re.search(r'PORT_NAME\("([^"]*)"\)', e)
        label = name.group(1) if name else ""
        # A two-player game names its second player's: "P1 Gear Shift". Player 1's is the shifter that counts.
        if re.match(r"^P[2-9]\b", label) or "PORT_PLAYER(2)" in e or "PORT_PLAYER(3)" in e or "PORT_PLAYER(4)" in e:
            continue
        toggle = "PORT_TOGGLE" in e
        named.append((int(m.group(1)), label, toggle))
    shift = [(b, n, t) for b, n, t in named if n and SHIFT_NAME.search(n)]
    if not shift:
        return None
    gears = [b for b, n, _ in shift if GEAR_N.search(n)]
    if len(shift) >= 3 and len(gears) >= 3:
        return {"gears": sorted(set(b for b, _, _ in shift))}
    up = [b for b, n, _ in shift if SEQ_UP.search(n)]
    down = [b for b, n, _ in shift if SEQ_DOWN.search(n)]
    if up and down and up[0] != down[0]:
        return {"up": up[0], "down": down[0]}
    # One lever: prefer an entry named a shift or a gear to one named "High" or "Low" or "Speed", and a toggle to a button held.
    def rank(row):
        _b, n, t = row
        return (0 if re.search(r"shift|gear", n, re.I) else 1, 0 if t else 1)
    shift.sort(key=rank)
    b, n, t = shift[0]
    return {"button": b, "toggle": t, "name": n}


def driving_parents(xml_path):
    """{romset: sourcefile} for every driving parent in -listxml: a paddle or dial AND a pedal, taking a coin."""
    out = {}
    for _ev, el in ET.iterparse(xml_path, events=("end",)):
        if el.tag != "machine":
            continue
        if el.get("isdevice") == "yes" or el.get("isbios") == "yes" or el.get("runnable", "yes") == "no" or el.get("cloneof"):
            el.clear()
            continue
        inp = el.find("input")
        if inp is not None and int(inp.get("coins", "0") or 0) >= 1:
            kinds = {c.get("type") for c in inp.findall("control")}
            if "pedal" in kinds and kinds & {"paddle", "dial"}:
                out[el.get("name")] = el.get("sourcefile", "")
        el.clear()
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = [a for a in sys.argv[1:] if a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    folder, xml_path = args
    out_path = os.path.join(HERE, "shifters.json")
    for o in opts:
        if o.startswith("--out="):
            out_path = o.split("=", 1)[1]
    result = {}
    missing = []
    for romset, source in sorted(driving_parents(xml_path).items()):
        path = os.path.join(folder, source)
        if not os.path.isfile(path):
            flat = os.path.join(folder, source.replace("/", "__"))
            path = flat if os.path.isfile(flat) else ""
        if not path:
            missing.append(romset)
            continue
        with open(path, errors="replace") as f:
            text = f.read()
        ports = None
        for m in mi.GAME_RE.finditer(text):
            if m.group(1) == romset:
                ports = m.group(4)
                break
        if ports is None:
            missing.append(romset)
            continue
        found = shifter_of(text, ports)
        if found is not None:
            result[romset] = found
        if "--report" in opts:
            print("%-12s %-30s %s" % (romset, source, json.dumps(found) if found else "-"))
    with open(out_path, "w", newline="\n") as f:
        json.dump(result, f, indent=1, sort_keys=True)
        f.write("\n")
    print("%d driving parents, %d with a shifter (%d two-position, %d toggles) -> %s" % (
        len(driving_parents(xml_path)), len(result), sum(1 for v in result.values() if "button" in v),
        sum(1 for v in result.values() if v.get("toggle")), out_path))
    if missing:
        print("not found in the sources (no shifter recorded): " + ", ".join(missing))


if __name__ == "__main__":
    main()
