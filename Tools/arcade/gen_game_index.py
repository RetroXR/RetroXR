#!/usr/bin/env python3
"""Build RetroXR/Scripts/Data/systems/arcade_game_table.gd from MAME's `-listxml`.

The cabinet adapts to the game inside it (docs/dev/arcade.md, "The cabinet follows the
game"): how many players, coins and buttons, what kind of control, which way the monitor
stands and what kind of cabinet the game was sold in. MAME's own machine list knows most of
that, but no core ships it and a 300 MB XML is no thing to carry, so this script boils it
down to one line per profile and writes it as a GDScript constant (the repo's way for a
generated table, see Tools/gen_n64_save_db.py).

    python Tools/arcade/gen_game_index.py path/to/mame0289.xml

The XML is `mame -listxml` (or the `mame0289lx.zip` a MAME release carries; give the
unzipped file). Only runnable machines that take a coin are kept: that is what an arcade
board is, and it leaves out the consoles and computers the same driver list holds.

A profile is `p<players>c<coins>b<buttons>w<ways>:<kinds>` and then, only where they are
not the default, `;`-separated attributes (a letter and a value):
  buttons   the most buttons one player's controls add up to,
  ways      the joystick's ways (8, 4, 2) or 0 for none,
  kinds     the controls present, sorted, joined by '+':
            joy twin stick paddle pedal gun touch dial ball btn other
            (`twin` is two sticks a player, `stick` MAME's analog joystick, `touch` a touch
            screen MAME files as a light gun, `paddle` + `pedal` a driving game),
  r<deg>    the main screen's rotation, 90/180/270 (90 and 270 stand the monitor on its side),
  s<n>      how many screens, 2 or more,
  g<n>      how many light guns (players with one),
  t<form>   the kind of cabinet the game came in, when it is not a plain upright:
            gun (guns in holsters), gunm (guns on mounts), rifle (a mounted rifle with a scope),
            race (a sit-down driving cockpit), stand (a stand-up driving cabinet), bike (a
            ride-on motorbike), dance (a 4-arrow dance stage), pump (a 5-panel one), music, odd,
  o         the driving cockpit has a roof,
  f         the gun game has a foot pedal,
  a         two players take turns on ONE panel (an alternating game whose upright had a
            single set of controls: MAME's Cabinet DIP offers a cocktail, the upright one),
  m<in>     the monitor's class in inches where it is not the 25" default (19 before 1985),
  v         the game reads a service / test switch (MAME's `<input service="yes">`: the TEST button
            inside the coin door, which toggles the game's own operator menu),
Everything in `t`, `o`, `f` and `a` that MAME does not say is a choice made here from
the lists below and a little general knowledge; docs/dev/arcade.md says which is which.

The names are the romset (zip) names, clones included: a clone has a zip of its own and
takes its parent's form. Each clone is tied to its parent in the line (`tokens_of`), so a clone's artwork
can be looked for under its parent's name as MAME does.
"""
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

KIND = {
    "joy": "joy", "doublejoy": "twin", "triplejoy": "twin",
    "stick": "stick",
    "paddle": "paddle",
    "pedal": "pedal",
    "lightgun": "gun",
    "dial": "dial", "positional": "dial",
    "trackball": "ball", "mouse": "ball",
    "only_buttons": "btn",
}

OUT = "RetroXR/Scripts/Data/systems/arcade_game_table.gd"
KEEP = {"description", "year", "input", "display", "dipswitch", "configuration"}

# Drivers whose "light gun" is a touch screen (bar-top quiz and card games, fruit machines with a touch
# panel): MAME files the touch panel as IPT_LIGHTGUN, and a gun cabinet is the wrong thing to draw.
TOUCH_DRIVERS = {
    "merit/meritm.cpp", "merit/mtouchxl.cpp", "williams/tmaster.cpp", "jpm/jpmimpct.cpp",
    "jpm/jpmsys5.cpp", "jpm/jpmsys5sw.cpp", "acorn/aristmk5.cpp", "igt/peplus.cpp", "amiga/cubo.cpp",
    "adp/adp.cpp", "pc/pcat_nit.cpp", "misc/magtouch.cpp", "misc/vlc.cpp", "namco/funcube.cpp",
    "misc/pntnpuzl.cpp", "misc/pntnpuzls.cpp", "misc/trivrus.cpp",
}
# Incredible Technologies' Eagle board: Golden Tee and Virtual Pool are touch and trackball,
# Big Buck Hunter and Carnival King have guns.
TOUCH_PREFIXES = ("gtfore", "virtpool")

# The cabinets that are not a plain upright, by PARENT romset (a clone takes its parent's).
# Guns on mounts (a swivelling machine gun, not a pistol on a cord): Operation Wolf's Uzi, Operation
# Thunderbolt, Beast Busters (three), Mechanized Attack, Line of Fire, Space Gun, Terminator 2,
# Revolution X, Dragon Gun's two dragons, The Lost World's rifles. Several are MAME `stick` games
# (a positional gun reads like an analog stick).
MOUNTED_GUN = {"opwolf", "othunder", "bbusters", "bbust2", "mechatt", "loffire", "spacegun", "term2",
               "revx", "dragngun", "lostwsga"}
# A rifle on a mount with a scope you look into (the scope is a second screen in Silent Scope).
RIFLE = {"sscope", "sscope2", "sscopex", "sscopefh", "golgo13", "g13knd", "g13jnr"}
# Gun games with a foot pedal (step on it to come out of cover).
GUN_PEDAL = {"timecris", "timecrs2", "crszone"}
# Ride-on motorbikes (and a quad, and a mountain bike): a seat you straddle and handlebars.
BIKE = {"hangon", "hangonjr", "shangon", "enduror", "fourtrax", "rachero", "gprider", "motofren",
        "scross", "suzuka8h", "suzuk8h2", "coolridr", "cybrcycc", "manxtt", "harley", "motoraid",
        "motoxgo", "radikalb", "downhill"}
# Stand-up driving cabinets (the wheel on an upright's panel, the pedals at its foot): Final Lap 1
# and 2, Pole Position. Other driving games are sit-down cockpits unless their Cabinet DIP's
# default says otherwise (below).
STAND_RACER = {"finallap", "finalap2", "polepos", "polepos2"}
# Cockpits with a roof over the seat: the Model 3 twins (an overhead marquee bridges the seats). A
# choice, not checked game by game.
ROOFED = {"scud", "lemans24", "daytona2", "dayto2pe", "srally2", "dirtdvls"}
# Unique cabinets, drawn as a plain upright until they get a module of their own: the list in
# docs/dev/arcade.md "Unusual cabinets". Time Traveler's hologram bowl, Panic Park's sliding levers,
# Prop Cycle's bicycle, the skis, the board, the boats, the fishing rod, the horses, a boxing bag.
ODD = {"timetrv", "panicprk", "propcycl", "alpinerd", "alpinr2b", "alpines", "alpinesa", "topskatr",
       "aquajet", "jetwave", "waverunr", "rapidrvr", "finfurl", "finfurl2", "skichamp", "bassdx",
       "getbass", "boxingm", "tokyowar", "cybsled", "starwars", "esb", "bzone", "redbaron",
       "punchout", "spnchout", "armwrest", "gunmania", "maletmad", "hammer", "luckywld", "rchase",
       "kick", "kickman", "dmx2m", "dmx2majp", "ppp", "ppd", "ppp11", "ppp2nd", "mamboagg",
       "desert", "magtruck", "eca", "jambo", "bigrun"}

DANCE_DESC = re.compile(r"dance dance revolution|dancing stage|dance 86\.4", re.I)
PUMP_DESC = re.compile(r"pump it up", re.I)
MUSIC_DESC = re.compile(r"beatmania|guitar ?freaks|drum ?mania|percussion freaks|pop'?n music|"
                        r"keyboardmania|taiko no tatsujin", re.I)

def default_value(group):
    """The name of a DIP switch's (or configuration's) factory setting, or ''."""
    for v in list(group.findall("dipvalue")) + list(group.findall("confsetting")):
        if v.get("default") == "yes":
            return v.get("name", "")
    return ""


def alternating(machine, players):
    """Two players taking turns on one set of controls: a Cabinet DIP that offers a cocktail (an
    alternating game's other cabinet) and leaves the upright as it shipped, one panel. An `Upright
    Controls` DIP says which outright (Single / Dual)."""
    if players != 2:
        return False
    cocktail = False
    for g in list(machine.findall("dipswitch")) + list(machine.findall("configuration")):
        name = (g.get("name") or "").lower()
        values = [(v.get("name") or "").lower() for v in list(g.findall("dipvalue")) + list(g.findall("confsetting"))]
        if name in ("upright controls", "controls") and "single" in values:
            return default_value(g).lower() == "single"
        if name in ("cabinet", "cabinet type") and any("cocktail" in v for v in values):
            default = default_value(g).lower()
            if "2 player" in default or "two player" in default or "dual" in default:
                return False
            cocktail = True
    return cocktail


def driving_cabinet(machine, name, year):
    """`race` (sit-down) or `stand` for a driving game: the curated list, then the Cabinet DIP's
    factory setting, then the era (an upright was the usual racer before 1988)."""
    if name in STAND_RACER:
        return "stand"
    for g in machine.findall("dipswitch"):
        if (g.get("name") or "").lower() not in ("cabinet", "cabinet type"):
            continue
        d = default_value(g).lower()
        if any(w in d for w in ("cockpit", "sit", "moving", "deluxe", "twin", "50 inch")):
            return "race"
        if any(w in d for w in ("upright", "stand", "mini")):
            return "stand"
    return "stand" if year and year < 1988 else "race"


def form_of(machine, parent, kinds, name_for_lists):
    desc = machine.findtext("description") or ""
    if name_for_lists in ODD:
        return "odd"
    if PUMP_DESC.search(desc):
        return "pump"
    if DANCE_DESC.search(desc):
        return "dance"
    if MUSIC_DESC.search(desc):
        return "music"
    if name_for_lists in RIFLE:
        return "rifle"
    if name_for_lists in MOUNTED_GUN:
        return "gunm"
    if "gun" in kinds:
        return "gun"
    if name_for_lists in BIKE:
        return "bike"
    if "pedal" in kinds and ({"paddle", "dial"} & kinds):
        year = machine.findtext("year") or ""
        y = int(year[:4]) if year[:4].isdigit() else 0
        return driving_cabinet(parent if parent is not None else machine, name_for_lists, y)
    return ""


def profile_of(machine, parent):
    inp = machine.find("input")
    if inp is None:
        return None
    coins = int(inp.get("coins", "0") or 0)
    if coins < 1:
        return None
    name = machine.get("name")
    family = machine.get("cloneof") or name
    source = machine.get("sourcefile", "")
    touch = source in TOUCH_DRIVERS or name.startswith(TOUCH_PREFIXES)
    players = int(inp.get("players", "1") or 1)
    buttons: dict[int, int] = defaultdict(int)
    kinds: set[str] = set()
    ways = 0
    guns = 0
    for c in inp.findall("control"):
        ctype = c.get("type", "")
        kind = KIND.get(ctype, "other")
        if kind == "gun" and touch:
            kind = "touch"
        if kind == "gun":
            guns += 1
        kinds.add(kind)
        # A control with no player belongs to the only player there is.
        buttons[int(c.get("player", "1") or 1)] += int(c.get("buttons", "0") or 0)
        if ctype in ("joy", "doublejoy", "triplejoy") and not ways:
            # "8", "4/8", "5 (half8)", "vertical2": the first number is the way count.
            m = re.search(r"\d+", c.get("ways", "8"))
            ways = int(m.group()) if m else 8
    key = "p%dc%db%dw%d:%s" % (
        min(players, 8), min(coins, 8), min(max(buttons.values(), default=0), 9), ways,
        "+".join(sorted(kinds)) or "none")
    attrs = []
    displays = machine.findall("display")
    if displays:
        rot = displays[0].get("rotate", "0")
        if rot in ("90", "180", "270"):
            attrs.append("r" + rot)
        if len(displays) > 1:
            attrs.append("s%d" % len(displays))
    if guns:
        attrs.append("g%d" % guns)
    form = form_of(machine, parent, kinds, family)
    if form:
        attrs.append("t" + form)
    if family in ROOFED and form == "race":
        attrs.append("o")
    if family in GUN_PEDAL:
        attrs.append("f")
    if alternating(machine if parent is None else parent, players) or alternating(machine, players):
        attrs.append("a")
    if inp.get("service") == "yes":
        attrs.append("v")
    year = machine.findtext("year") or ""
    if year[:4].isdigit() and int(year[:4]) < 1985 and displays and displays[0].get("type") != "vector":
        attrs.append("m19")
    return key + "".join(";" + a for a in attrs)


def tokens_of(names, parent_of):
    """The romsets of one line, each clone tied to its parent (MAME looks for a clone's artwork under its
    parent's name, ArcadeBezel likewise): a parent followed by its clones on the same line, joined by '='
    (`sf2=sf2ea=sf2eb`, no longer than the spaces they replace), and a clone whose parent is on another line
    naming it after '<' (`sf2ce<sf2`)."""
    here = set(names)
    children = defaultdict(list)
    for n in names:
        par = parent_of.get(n)
        if par in here:
            children[par].append(n)
    out = []
    for n in names:
        par = parent_of.get(n)
        if par in here:
            continue
        if par is not None:
            out.append("%s<%s" % (n, par))
        else:
            out.append("=".join([n] + children.get(n, [])))
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    # Two passes: a clone's cabinet DIPs often live only on its parent.
    machines = {}
    build = "?"
    for _, el in ET.iterparse(sys.argv[1], events=("end",)):
        if el.tag == "mame":
            build = el.get("build", build)
        if el.tag != "machine":
            continue
        if el.get("isdevice") != "yes" and el.get("isbios") != "yes" \
                and el.get("runnable", "yes") != "no":
            # Only what a profile reads is kept for the second pass (ROM lists and devices are most of the file).
            for child in list(el):
                if child.tag not in KEEP:
                    el.remove(child)
            machines[el.get("name")] = el
        else:
            el.clear()
    groups: dict[str, list[str]] = defaultdict(list)
    for name, el in machines.items():
        parent = machines.get(el.get("cloneof") or "")
        p = profile_of(el, parent)
        if p:
            groups[p].append(name)
    total = sum(len(v) for v in groups.values())
    parent_of = {n: el.get("cloneof") for n, el in machines.items() if el.get("cloneof") in machines}
    lines = []
    for p in sorted(groups, key=lambda k: (-len(groups[k]), k)):
        lines.append("%s %s" % (p, " ".join(tokens_of(sorted(groups[p]), parent_of))))
    with open(OUT, "w", newline="\n") as f:
        f.write("## Generated by Tools/arcade/gen_game_index.py from MAME's -listxml (%s).\n" % build)
        f.write("## Do not edit; re-run the script. One line per profile, then the romsets that have it.\n")
        f.write("## %d romsets, %d profiles. Read through ArcadeGameProfile.\n" % (total, len(groups)))
        f.write("class_name ArcadeGameTable\n\n")
        f.write('const MAME_BUILD := "%s"\n\n' % build)
        f.write('const TABLE := """\n' + "\n".join(lines) + '\n"""\n')
    print("%d romsets, %d profiles -> %s" % (total, len(groups), OUT))


if __name__ == "__main__":
    main()
