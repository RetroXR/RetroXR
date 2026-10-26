#!/usr/bin/env python3
"""Which games came in a cabinet you SIT in, with a cabin round it, on a base that moves; and which flight sims have a throttle lever.

`-listxml` says a game has a stick and two buttons. It does not say that After Burner II's deluxe cabinet was a closed cockpit you
sat in, strapped to a seat that tilted with the stick. Two things say so:

* MAME's own Cabinet DIP, which NAMES the versions the game was built in ("Moving Deluxe", "Moving Standard", "Cockpit", "Ride On"). It
  is the factory setting that is no use (every one of them ships set to "Upright"), the choices are the evidence. `--report` lists
  which curated games have such a DIP and which do not.
* The research behind docs/dev/arcade-cabinets.md, for the games whose driver says nothing (The Lost World's jeep seat, Solar Assault's
  pod): `SEATING` below, each entry with where it comes from.

This file is the CURATED half. `gen_game_index.py` reads `FLY` and `SEATING` from it, and `cockpits.json` (what this script reads out of
MAME's driver sources, exactly as shifters.py does for gear levers) for the part that is MAME's: whether the game reads a throttle,
`IPT_AD_STICK_Z`:

    python Tools/arcade/cockpits.py <folder of MAME driver sources> <mame -listxml> [--out Tools/arcade/cockpits.json] [--report]

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
from shifters import entries  # noqa: E402

# Flight and space sims flown with a stick (and often a throttle) from a seat, by PARENT romset (a clone takes its parent's). The table files
# them under the form `fly`: a cockpit with the stick between the knees, not an upright with a stick on its panel. Only games with evidence
# of a sit-down version are here; the other flight games of MAME (Wing War, Air Rescue, Hang Pilot, Lock-On, the Atari yokes) stay uprights
# until someone has looked at them.
FLY = {
    # Sega
    "aburner", "aburner2", "sharrier", "gloc", "gforce2", "thndrbld", "strkfgtr", "sstrkfgt", "skytargt", "wingwar",
    # Taito
    "nightstr", "mlanding", "topland", "ainferno",
    # Konami, Namco
    "slrasslt", "aircomb", "airco22b", "tceptor",
}

# What each sit-down game was built with: s = a seat, c = a cabin round it (a canopy, side panels), m = a base that moves with the play.
# "DIP" is MAME's Cabinet DIP naming the version, "research" the summary in docs/dev/arcade-cabinets.md (secondary sources: no photograph
# of any of these could be opened from the build machine, so the cabin's shape is an estimate whatever the flags say).
SEATING = {
    # Flight
    "aburner": "scm",   # DIP "Moving Deluxe / Moving Standard"; the deluxe is an enclosed cockpit with a seat belt, hydraulic (research, 3 sources)
    "aburner2": "scm",  # the same cabinet, and the one with the throttle lever (DIP "Throttle Lever")
    "sharrier": "sm",   # DIP "Moving"; an open sit-down seat on a moving base, no cabin (research)
    "gloc": "scm",      # DIP "Moving" and "Cockpit"; the R-360 clone is a gyroscope cage, a cabin that turns (research)
    "gforce2": "scm",   # DIP "Super Deluxe / Deluxe": a sit-down simulator in which cabinet, seat and screen move together (research)
    "thndrbld": "sm",   # DIP "Deluxe" (thndrbld1): a helicopter-style chair that follows the stick, no cabin (research)
    "strkfgtr": "scm",  # DIP "Moving" and "Cockpit": a G-LOC conversion, the same cabinet
    "wingwar": "scm",   # Wing War R360 (`wingwar360`, MAME's clone) is the R-360 pod, the same cabinet as G-LOC R360: a gyroscope cage, a cabin that turns (research)
    "sstrkfgt": "s",    # NAOMI: a seat and rudder pedals, the deluxe three-screen one non-motion (research)
    "skytargt": "s",    # a sit-down unit listed by a dealer, the deluxe one non-motion (research, one source)
    "nightstr": "sc",   # DIP "Cockpit" (research: a cockpit-style cabinet)
    "mlanding": "scm",  # DIP "Deluxe": a cockpit-style cabinet whose hydraulics follow the stick (research, one source for the motion)
    "topland": "sc",    # DIP "Deluxe": the same cockpit cabinet as Midnight Landing, motion not found
    "ainferno": "scm",  # DIP "DX Moving Only": a motion simulator cockpit (left and right) and a standard one
    "slrasslt": "scm",  # no DIP: the deluxe is a SpeedKing pod, an enclosed unit that tilts pneumatically (research, one source)
    "aircomb": "sc",    # a full-size cockpit with a rumbling seat, not moving (research)
    "airco22b": "sc",   # the same cabinet, "authentic cockpit" (research)
    "tceptor": "s",     # a sit-down cabinet with a yoke and an accelerator pad, like Space Harrier's (research)
    # Rides with guns: a bench you sit on, in front of the cabinet
    "rchase": "sm",     # DIP "Moving": a bench that pitches and sways with the ride (pneumatic, research)
    "rchase2": "sm",    # the same bench
    "lostwsga": "s",    # a seat styled on the film's jeep, the screen where the windscreen would be (research)
    "loffire": "s",     # DIP "Cockpit": two seats, a gun each (research, one source)
    "jpark": "sm",      # a deluxe with a moving seat that mimics a jeep ride (research, one source)
    # Driving: the sit-down cabinets whose DIP default (an upright or a mini upright) hides them
    "outrun": "sm",     # DIP "Moving" and "Up Cockpit": the deluxe sit-down with a motor that rotates and jolts the cabinet
    "toutrun": "sm",    # DIP "Moving" and "Cockpit"
    "pdrift": "sm",     # DIP "Moving": the deluxe on a hydraulic base
    "smgp": "sm",       # DIP "Deluxe" and "Cockpit": the deluxe seat moves with the play
}

# A lever the driver has and the cabinet did not (After Burner's port set is shared with After Burner II's, which added the lever).
NO_THROTTLE = {"aburner"}

ANALOG_Z = re.compile(r"IPT_AD_STICK_Z")
# A Z axis that is something else: Sega Strike Fighter's (a NAOMI board that borrows Airline Pilots' controls) is its rudder pedals.
NOT_A_THROTTLE = re.compile(r"rudder|pedal", re.I)


def throttle_of(text, ports):
    """{"name": the port's own word} for a game whose first player reads a Z axis that is a throttle lever, or None."""
    for e in entries(text, ports):
        if not ANALOG_Z.search(e):
            continue
        if re.search(r"PORT_PLAYER\(([2-9])\)", e):
            continue
        name = re.search(r'PORT_NAME\("([^"]*)"\)', e)
        word = name.group(1) if name else ""
        if NOT_A_THROTTLE.search(word):
            continue
        return {"name": word}
    return None


def source_path(folder, source):
    path = os.path.join(folder, source)
    if os.path.isfile(path):
        return path
    flat = os.path.join(folder, source.replace("/", "__"))
    return flat if os.path.isfile(flat) else ""


def fly_machines(xml_path):
    """{romset: {"source", "dips": [(group name, [values])]}} for every machine of a FLY or SEATING family in -listxml: a clone has its own
    controls (G-LOC's R-360 has three seats and no throttle), so it is read on its own."""
    out = {}
    for _ev, el in ET.iterparse(xml_path, events=("end",)):
        if el.tag != "machine":
            continue
        name = el.get("name")
        family = el.get("cloneof") or name
        if family in FLY or family in SEATING:
            dips = []
            for g in list(el.findall("dipswitch")) + list(el.findall("configuration")):
                gname = g.get("name") or ""
                if re.search(r"cabinet|cockpit|seat|machine type|moving", gname, re.I):
                    dips.append((gname, [v.get("name") or "" for v in list(g.findall("dipvalue")) + list(g.findall("confsetting"))]))
            out[name] = {"source": el.get("sourcefile", ""), "dips": dips, "family": family,
                         "description": el.findtext("description") or ""}
        el.clear()
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = [a for a in sys.argv[1:] if a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    folder, xml_path = args
    out_path = os.path.join(HERE, "cockpits.json")
    for o in opts:
        if o.startswith("--out="):
            out_path = o.split("=", 1)[1]
    machines = fly_machines(xml_path)
    throttles = {}
    missing = []
    for romset in sorted(machines):
        m = machines[romset]
        if m["family"] not in FLY:
            continue
        path = source_path(folder, m["source"])
        if not path:
            missing.append(romset)
            continue
        with open(path, errors="replace") as f:
            text = f.read()
        ports = None
        for g in mi.GAME_RE.finditer(text):
            if g.group(1) == romset:
                ports = g.group(4)
                break
        if ports is None:
            missing.append(romset)
            continue
        found = None if m["family"] in NO_THROTTLE else throttle_of(text, ports)
        if found is not None:
            throttles[romset] = found
        if "--report" in opts:
            print("%-10s %-28s throttle: %s" % (romset, m["source"], json.dumps(found) if found else "-"))
    with open(out_path, "w", newline="\n") as f:
        json.dump({"throttle": throttles}, f, indent=1, sort_keys=True)
        f.write("\n")
    print("%d flight romsets (%d families), %d with a throttle -> %s" % (
        sum(1 for m in machines.values() if m["family"] in FLY), len(FLY), len(throttles), out_path))
    if "--report" in opts:
        seat_words = re.compile(r"moving|cockpit|deluxe|sit|ride on|motion", re.I)
        for romset in sorted(SEATING):
            m = machines.get(romset)
            if m is None:
                continue
            named = [(g, [v for v in vals if seat_words.search(v)]) for g, vals in m["dips"]]
            named = [(g, vs) for g, vs in named if vs]
            print("%-10s %-4s %s" % (romset, SEATING[romset], ("DIP " + "; ".join("%s: %s" % (g, ", ".join(vs)) for g, vs in named)) if named else "(no DIP names a seat)"))
    if missing:
        print("not found in the sources (no throttle recorded): " + ", ".join(missing))


if __name__ == "__main__":
    main()
