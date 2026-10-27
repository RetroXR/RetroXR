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
  c<rects>  where the screens stand in the frame MAME draws, for a game of two or more (layouts.py): each screen's `x,y,w,h` in the
            layout's own units, in screen order, joined by '/' (`c0,0,4,3/4.03,0,4,3` two side by side, `c0,0,4,3/0,-3.03,4,3` the second
            over the first). The frame is the first view that shows every screen, so these are also its shape,
  l<n>      the screen that is the scope's own, the LENS (Silent Scope: 1, hornet.cpp's `rscreen`, "for scope"): the cabinet shows it in the rifle's scope,
  g<n>      how many light guns (players with one),
  t<form>   the kind of cabinet the game came in, when it is not a plain upright:
            gun (guns in holsters), gunm (guns on mounts), rifle (a mounted rifle with a scope),
            race (a sit-down driving cockpit), fly (a sit-down flight cockpit: After Burner II), stand (a stand-up
            driving cabinet), bike (a ride-on motorbike), cycle (a ride-on bicycle: Prop Cycle), holo (a hologram window:
            Time Traveler), slot (two levers sliding in one slot: Panic Park), racegun (a driving cockpit of two seats with a gun
            each: Lucky & Wild), dance (a 4-arrow dance stage), pump (a 5-panel one), music, skate / snow / ski (a rider standing
            on a rocking skateboard, snowboard or pair of skis, a rail round the front: Top Skater, Alpine Surfer, Alpine Racer, Ski Super G), odd,
  o         the driving cockpit has a roof,
  q<flags>  what the game's SIT-DOWN version was built with, for a flight cockpit, a driving cockpit or a gun ride (cockpits.py SEATING, with where each comes
            from): `s` a seat, `c` a cabin round it, `m` a base that moves with the play (`qscm` After Burner II, `qsm` Out Run), `r` the R-360's rings in place of a
            cabin (`qsmr`: G-LOC R360, Wing War R360),
  z         the flight game reads a throttle lever (an `IPT_AD_STICK_Z` of its own in the driver, cockpits.py),
  y<style>  the controller is drawn as something other than a ball on a stick: `yyoke` a flight yoke, `yrod` a fishing rod with its reel (STYLE; `k` is retired: it was a boot time),
  h         the game's dial is a STEERING WHEEL, with no pedals (Bad Lands: MAME calls the wheel a dial, and the cabinet had a wheel a player),
  n<arrows> how many arrows a dancer's stage has when it is not four (`n6`: DDR Solo's six panels),
  i<name>   which rhythm game's own controller a `music` cabinet has (`ideck` beatmania's five keys and a turntable a player, `ipopn` pop'n music's nine
            buttons, `iguitar` GuitarFreaks' two guitars, `idrums` DrumMania's pads and bass pedal, `itaiko` a Taiko drum a player, `iconga` Mambo a Go-Go's three
            drums); a rhythm game of none of these has no `i` and is a plain panel,
  f         the gun game has a foot pedal,
  x<lever>  the driving game's gear lever, from the driver sources (shifters.py): `x3t` button 3 and MAME makes it a toggle, `x3h` button 3 held while
            the lever is high, `xs21` a sequential box (up on button 2, down on 1). A driving game with none has no lever,
  a         two players take turns on ONE panel (an alternating game whose upright had a
            single set of controls: MAME's Cabinet DIP offers a cocktail, the upright one),
  m<in>     the monitor's class in inches where it is not the 25" default (19 before 1985),
  v         the game reads a service / test switch (MAME's `<input service="yes">`: the TEST button
            inside the coin door, which toggles the game's own operator menu),
  b<class>  the game has a Timekeeper chip (a battery RAM and a clock) whose memory it checks and may reject (Silent Scope: BACKUP DATA ERROR): `bh` its default image is
            hand built or missing (baddump, nodump), `bg` a good dump, `bn` no image at all (docs/dev/arcade-backup-memory.md),
Everything in `t`, `o`, `f` and `a` that MAME does not say is a choice made here from
the lists below and a little general knowledge; docs/dev/arcade.md says which is which.

The names are the romset (zip) names, clones included: a clone has a zip of its own and
takes its parent's form. Each clone is tied to its parent in the line (`tokens_of`), so a clone's artwork
can be looked for under its parent's name as MAME does.
"""
import json
import os
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
# The sit-down cabinets: the flight sims and which versions of each game had a seat, a cabin and a moving base (cockpits.py: curated, with where
# each comes from), and the games whose driver reads a throttle lever, per ROMSET (cockpits.json, read out of MAME's driver sources).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cockpits import FLY, RING, SEATING  # noqa: E402
THROTTLES = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "cockpits.json")))["throttle"]
# The gear lever of a driving game, by PARENT romset: read out of MAME's driver sources by shifters.py (a button, whether MAME makes it a
# toggle, or a sequential box's up and down buttons). -listxml carries none of it.
SHIFTERS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "shifters.json")))
# Where the screens of a multi-screen game stand in the frame, by ROMSET: read out of MAME's drivers and layout files by layouts.py.
LAYOUTS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "layouts.json")))
# The screen that is a scope's own, by PARENT romset: every Silent Scope builds on hornet.cpp's `sscope` configuration, whose second screen
# is `rscreen` ("for scope", 15 kHz, 768 x 236). The first is the monitor.
SCOPE_SCREEN = {"sscope": 1, "sscope2": 1}
# A monitor the game's own cabinet is known to have had that is not the 25 inch default, by PARENT romset (the table's `m`). Each is a figure from the
# research, not from MAME (docs/dev/arcade-cabinets.md): Panic Park's dedicated cabinets had a 33 or a 50 inch screen (Namco System 23, Wikipedia);
# the 33 is the smaller of the two. Sega's Star Wars Arcade had a 50 inch rear-projection monitor housed separately (one listing, low): the biggest picture an upright's body holds.
MONITOR_CLASS = {"panicprk": 33, "swa": 50}
# Multi-screen romsets layouts.py did not meet (not a coin machine to it, or its driver was not in the sources): they get no `c` and the cabinet
# lays them out as it laid out any second screen, side by side.
MISSING_LAYOUT: list[str] = []
KEEP = {"description", "year", "input", "display", "dipswitch", "configuration"}
# The Timekeeper-class chips (a battery RAM and a clock in one: Konami's Hornet, Viper, System 573...): MAME keeps their memory in a file a game checks block by block and
# says BACKUP DATA ERROR about (Silent Scope). The machine's `b`: `h` if the default image the chip is seeded from is hand built or missing (`baddump`, `nodump`:
# the first start is from a memory the game may reject), `g` if it is a good dump, `n` if there is no image at all. A game of none carries no `b`.
# docs/dev/arcade-backup-memory.md.
TIMEKEEPERS = {"m48t02", "m48t35", "m48t37", "m48t58", "mk48t08", "mk48t12", "ds1643"}
TIMEKEEPER_REGIONS = TIMEKEEPERS | {"timekpr", "timekeeper"}

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
# Gun games MAME does not file as light guns, by PARENT romset: name -> (form, guns). Three kinds:
# a driver that declares no controls yet (Namco System 246's Time Crisis 3 and 4 and Vampire Night, Sega
# Lindbergh's House of the Dead 4 and EX, Ghost Squad Evolution, Let's Go Jungle, Primeval Hunt), the
# joystick panel a Chihiro, Naomi or Atomiswave game is given (House of the Dead III, Ghost Squad, Virtua Cop
# 3, Ninja Assault, Gun Survivor 2, Sports Shooting USA, Clay Challenge, Extreme Hunting), and the analog
# sticks a positional gun reads as (Alien3, Jurassic Park, Gunblade NY, Rail Chase 2: swivel mounts like
# Terminator 2's). Counts and cords-or-mounts are what the real cabinets had (docs/dev/arcade-cabinets.md);
# MAME's own `g` wins where it counts guns.
UNTYPED_GUNS = {
    "vnight": ("gun", 2), "timecrs3": ("gun", 2), "timecrs4": ("gun", 2),
    "hotd3": ("gun", 2), "ghostsqu": ("gun", 2), "vcop3": ("gun", 2),
    "hotd4": ("gun", 2), "hotdex": ("gun", 2), "ghostsev": ("gun", 2), "letsgoju": ("gun", 2),
    "primevah": ("gun", 2),
    "ninjaslt": ("gun", 2), "gunsur2": ("gun", 1),
    "sprtshot": ("gun", 2), "claychal": ("gun", 2), "xtrmhunt": ("gun", 2), "xtrmhnt2": ("gun", 2),
    "alien3": ("gunm", 2), "jpark": ("gunm", 2), "gunblade": ("gunm", 2), "rchase2": ("gunm", 2),
    "oceanhun": ("gunm", 2),
}
# Gun games with a foot pedal (step on it to come out of cover).
GUN_PEDAL = {"timecris", "timecrs2", "timecrs3", "timecrs4", "crszone"}
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
# A ride-on bicycle (a crank you pedal, handlebars you steer and tip), a hologram window (the picture floats in a
# dark stage in front of a mirror), two levers in one slot: the three the named-examples list asked to be built
# (docs/dev/arcade-cabinets.md).
CYCLE = {"propcycl"}
HOLO = {"timetrv"}
SLOT = {"panicprk"}
# A driving cockpit of two seats, a wheel and a pedal for the driver and a gun for each player (Lucky & Wild: Namco's driver and gunner).
RACEGUN = {"luckywld"}
# Driving games MAME does not describe with a paddle and a pedal, by PARENT romset: the form they came in. A Chihiro, Naomi, Hikaru or Triforce game is given the
# joystick panel of its board (the wheel is read through the JVS, which -listxml cannot see), a Lindbergh or System 246 game declares no controls at all, and
# Road Blasters' wheel is an analog stick: all were uprights with a stick. Each of these was a sit-down cockpit with a wheel, pedals and (for most) a gear
# lever, or, for the two old Atari ones, a stand-up with the wheel on its panel (docs/dev/arcade-cabinets.md). A game of this list that declares no controls gets a
# player and two coins, as UNTYPED_GUNS' do.
DRIVING_FORM = {
    # Sega Chihiro
    "outr2": "race", "outr2st": "race", "crtaxihr": "race", "wangmid": "race", "wangmid2": "race",
    # Sega Naomi, Hikaru, Lindbergh, Triforce
    "initd": "race", "initdexp": "race", "initdv2j": "race", "initdv3e": "race", "initdv3j": "race", "inidv3cy": "race",
    "clubkrt": "race", "clubk2k3": "race", "clubkprz": "race", "clubkpzb": "race", "clubkcyc": "race",
    "f355": "race", "f355twin": "race", "f355twn2": "race", "sgdrvsim": "race", "kingrt66": "race", "tokyobus": "race",
    "sgnascar": "race", "initiad4": "race", "outr2sdx": "race", "segartv": "race", "hummerxt": "race",
    "fzeroax": "race", "fzeroaxm": "race", "mkartagp": "race", "mkartag2": "race",
    # Namco System 246, Taito
    "wanganmd": "race", "wanganmr": "race", "acedriv3": "race", "rrvac": "race", "batlgr3": "race", "wgp": "race", "wgp2": "race",
    # Tatsumi's TX-1: a seated cockpit with three screens (the era made it a stand-up)
    "tx1": "race",
    # a ride-on motorbike
    "motogp": "bike",
    # Atari's wheel and pedal on an upright's panel
    "roadblst": "stand", "nitedrvr": "stand",
}
# A dial that is a steering wheel with no pedals: Bad Lands' (a wheel for each of two players, the gas a button).
WHEEL_DIAL = {"badlands"}
# Controls a driver's SHARED port set gives every game it runs, though no cabinet had them: (source file, kind) -> the families that really do. Taito F3's
# `f3` ports declare two paddle dials (DIAL.0 and .1, the Z/X and N/M keys) for all 35 of its games and only Arkanoid Returns reads them: with them every F3 game
# (Puzzle Bobble 2, Elevator Action Returns, Darius Gaiden, about a hundred romsets) was drawn with a spinner where its joystick was.
SPURIOUS = {("taito/taito_f3.cpp", "dial"): {"arkretrn"}}
# The converse, for one game: a control the shared port set gives it and its cabinet had none of, by FAMILY. Arkanoid Returns is a paddle and a button: the F3 board's joystick is
# declared for its menus and no spinner game wants a stick drawn beside the spinner (a dial and a joystick together is a rotary stick, `rotary`).
UNUSED = {"arkretrn": {"joy"}}
# A game MAME counts more players (and coins) than its cabinet had, by PARENT romset: (players, coins). The F3 board takes four whatever the game was; Darius Gaiden
# was a two-player upright (Taito's own, docs/dev/arcade-cabinets.md).
PLAYERS = {"dariusg": (2, 2), "dariusgx": (2, 2),
           # Alpine Surfer, Alpine Racer and Alpine Racer 2: one rider a machine (two linked machines race together), where MAME counts both riders.
           "alpines": (1, 1), "alpinerd": (1, 1), "alpinr2b": (1, 1),
           # Taiko no Tatsujin 7 to 11 (Namco System 246) declare no controls yet: the cabinet is the drum a player, two players, whatever the driver gets to.
           "taiko7": (2, 2), "taiko8": (2, 2), "taiko9": (2, 2), "taiko10": (2, 2), "taiko11": (2, 2)}
# Unique cabinets, drawn as a plain upright until they get a module of their own: the list in
# docs/dev/arcade-cabinets.md. The boats, a pair of skis (Ski Champ), the horses, a boxing bag.
ODD = {"aquajet", "jetwave", "waverunr", "rapidrvr", "finfurl", "finfurl2", "skichamp",
       "boxingm", "tokyowar", "cybsled", "bzone",
       "punchout", "spnchout", "armwrest", "gunmania", "maletmad", "hammer",
       "kick", "kickman", "dmx2m", "dmx2majp", "ppp", "ppd", "ppp11", "ppp2nd",
       "desert", "magtruck", "jambo", "bigrun"}

# A controller that is not a ball on a stick, by PARENT romset: the table's `y` (control style), drawn in place of the stick's ball. A flight yoke (Atari's Star Wars, The Empire Strikes
# Back and Red Baron: a U-shaped yoke with a handgrip each end), a fishing rod with a reel and a crank (Sega Bass Fishing and its clones). The game stays an upright: MAME gives the
# fishing game a paddle and a pedal, which would have made it a stand-up driving cabinet.
STYLE = {"starwars": "yoke", "esb": "yoke", "redbaron": "yoke", "bassdx": "rod"}
# A rider STANDING on a board: Sega's Top Skater (a skateboard deck), Namco's Alpine Surfer (a snowboard), Alpine Racer and its sequel and Sega's Ski Super G (a pair of skis), by PARENT romset: the vehicle,
# which is the form (`tskate`, `tsnow`, `tski`). The deck rocks about its long axis with the steering and the rider holds a rail round the front; MAME gives each of them a stick, a joystick or
# a pair of analog sticks and no seat, which drew a plain upright with a ball on a stick. Ski Champ, Water Ski and Surf Planet are not here: nothing found says what stood
# under their riders. One rig a cabinet, whatever the driver counts (PLAYERS: Namco's pair of linked machines is two cabinets).
BOARD = {"topskatr": "skate", "alpines": "snow", "alpinerd": "ski", "alpinr2b": "ski", "skisuprg": "ski"}

DANCE_DESC = re.compile(r"dance dance revolution|dancing stage|dance 86\.4", re.I)
PUMP_DESC = re.compile(r"pump it up", re.I)
MUSIC_DESC = re.compile(r"beatmania|guitar ?freaks|drum ?mania|percussion freaks|pop'?n music|"
                        r"keyboardmania|taiko no tatsujin|mambo a go-?go", re.I)
# Which controller a rhythm game has (the table's `i`): the first that matches the description. beatmania IIDX (a seven-key deck with effect buttons, its turntable a
# trackball to MAME), beatmania III and Keyboardmania have none yet and stay plain panels.
INSTRUMENT = (
    (re.compile(r"iidx|beatmania iii", re.I), ""),
    (re.compile(r"beatmania", re.I), "deck"),
    (re.compile(r"pop'?n music", re.I), "popn"),
    (re.compile(r"guitar ?freaks", re.I), "guitar"),
    (re.compile(r"drum ?mania|percussion freaks", re.I), "drums"),
    (re.compile(r"taiko no tatsujin", re.I), "taiko"),
    (re.compile(r"mambo a go-?go", re.I), "conga"),
)
# A dancer's stage has four arrows, a Solo cabinet's six (the up-left and up-right panels): `n6`.
SOLO_DESC = re.compile(r"\bsolo\b", re.I)

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
    # The sit-down version is the one the research names even when the Cabinet DIP is set to an upright as it ships (Out Run's "Mini Up").
    if "s" in SEATING.get(name, ""):
        return "race"
    for g in machine.findall("dipswitch"):
        if (g.get("name") or "").lower() not in ("cabinet", "cabinet type"):
            continue
        d = default_value(g).lower()
        if any(w in d for w in ("cockpit", "sit", "moving", "deluxe", "twin", "50 inch")):
            return "race"
        if any(w in d for w in ("upright", "stand", "mini")):
            return "stand"
    return "stand" if year and year < 1988 else "race"


def backup_class(machine):
    """`h`, `g`, `n` or '' (see TIMEKEEPERS): from the machine's own device list and ROM regions, which `-listxml` merges a parent's into a clone's."""
    if not {d.get("name") for d in machine.findall("device_ref")} & TIMEKEEPERS:
        return ""
    statuses = [r.get("status", "good") for r in machine.findall("rom")
                if (r.get("region") or "").lstrip(":").lower() in TIMEKEEPER_REGIONS]
    if not statuses:
        return "n"
    return "h" if any(st in ("baddump", "nodump") for st in statuses) else "g"


def screens_attr(romset):
    """`c<rects>` for a game of two or more screens, or "" when layouts.py did not meet the machine."""
    key = LAYOUTS["romsets"].get(romset)
    if key is None:
        return ""
    def num(v):
        return str(int(v)) if float(v) == int(v) else repr(float(v))
    return "c" + "/".join(",".join(num(v) for v in rect) for rect in LAYOUTS["layouts"][key]["rects"])


def shift_attr(shift):
    """The `x` attribute of a gear lever: `3t` (button 3, a toggle), `3h` (button 3, held while the lever is high) or `s21` (a sequential box:
    up on button 2, down on button 1). '' for what a lever of two positions cannot say (an H pattern) or a button a pad has not got."""
    if "button" in shift and 1 <= shift["button"] <= 6:
        return "%d%s" % (shift["button"], "t" if shift["toggle"] else "h")
    if "up" in shift and 1 <= shift["up"] <= 6 and 1 <= shift["down"] <= 6:
        return "s%d%d" % (shift["up"], shift["down"])
    return ""


def form_of(machine, parent, kinds, name_for_lists):
    desc = machine.findtext("description") or ""
    if name_for_lists in CYCLE:
        return "cycle"
    if name_for_lists in HOLO:
        return "holo"
    if name_for_lists in SLOT:
        return "slot"
    if name_for_lists in RACEGUN:
        return "racegun"
    if name_for_lists in FLY:
        return "fly"
    if name_for_lists in BOARD:
        return BOARD[name_for_lists]
    if name_for_lists in STYLE:
        return ""
    if name_for_lists in ODD:
        return "odd"
    if name_for_lists in DRIVING_FORM:
        return DRIVING_FORM[name_for_lists]
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
    if name_for_lists in UNTYPED_GUNS:
        return UNTYPED_GUNS[name_for_lists][0]
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
    name = machine.get("name")
    family = machine.get("cloneof") or name
    untyped = UNTYPED_GUNS.get(family)
    inp = machine.find("input")
    if inp is None:
        if untyped is None:
            return None
        inp = ET.SubElement(machine, "input")
    if untyped is not None:
        # A driver that declares no controls yet: the cabinet is the gun game it was, a player and a coin door to a gun.
        if int(inp.get("players", "0") or 0) < 1:
            inp.set("players", str(untyped[1]))
        if int(inp.get("coins", "0") or 0) < 1:
            inp.set("coins", str(untyped[1]))
    elif family in DRIVING_FORM or family in PLAYERS:
        # The same for a driving game or a rhythm game of a driver with no controls yet (System 246, Lindbergh, Triforce: an `<input>` that has no players or no
        # coins): one driver and two coins, or what PLAYERS says.
        if int(inp.get("players", "0") or 0) < 1:
            inp.set("players", str(PLAYERS.get(family, (1, 2))[0]))
        if int(inp.get("coins", "0") or 0) < 1:
            inp.set("coins", str(PLAYERS.get(family, (1, 2))[1]))
    coins = int(inp.get("coins", "0") or 0)
    if coins < 1:
        return None
    source = machine.get("sourcefile", "")
    touch = source in TOUCH_DRIVERS or name.startswith(TOUCH_PREFIXES)
    players = int(inp.get("players", "1") or 1)
    if family in PLAYERS:
        players, coins = PLAYERS[family]
    buttons: dict[int, int] = defaultdict(int)
    kinds: set[str] = set()
    ways = 0
    guns = 0
    for c in inp.findall("control"):
        ctype = c.get("type", "")
        kind = KIND.get(ctype, "other")
        spurious = SPURIOUS.get((source, kind))
        if spurious is not None and family not in spurious:
            continue
        if kind in UNUSED.get(family, ()):
            # The control is not drawn, but its buttons are the game's (the F3 joystick carries Arkanoid Returns' four).
            buttons[int(c.get("player", "1") or 1)] += int(c.get("buttons", "0") or 0)
            continue
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
            if screens_attr(name):
                attrs.append(screens_attr(name))
            elif family not in SCOPE_SCREEN:
                MISSING_LAYOUT.append(name)
            if family in SCOPE_SCREEN:
                attrs.append("l%d" % SCOPE_SCREEN[family])
    if not guns and untyped is not None:
        guns = untyped[1]
    if guns:
        attrs.append("g%d" % guns)
    form = form_of(machine, parent, kinds, family)
    if form:
        attrs.append("t" + form)
    desc = (machine.findtext("description") or "") + " " + ((parent.findtext("description") or "") if parent is not None else "")
    if family in WHEEL_DIAL:
        attrs.append("h")
    if family in STYLE:
        attrs.append("y" + STYLE[family])
    if form == "dance" and SOLO_DESC.search(desc):
        attrs.append("n6")
    if form == "music":
        for pattern, instrument in INSTRUMENT:
            if pattern.search(desc):
                if instrument:
                    attrs.append("i" + instrument)
                break
    if family in ROOFED and form == "race":
        attrs.append("o")
    # q: a seat (s), a cabin round it (c), a moving base (m): what the sit-down version of this game had (cockpits.py SEATING). Only a form that can
    # show it reads it: a flight cockpit, a driving cockpit, a gun ride's bench.
    if (form in ("fly", "race", "gun", "gunm") or not form) and SEATING.get(family):
        q = SEATING[family]
        if name in RING:
            # The R-360's rings stand where a canopy's panels would.
            q = q.replace("c", "") + "r"
        attrs.append("q" + q)
    # z: the game reads a throttle lever (a Z axis of its own, cockpits.json).
    if form == "fly" and name in THROTTLES:
        attrs.append("z")
    if family in GUN_PEDAL:
        attrs.append("f")
    if form in ("race", "stand") and shift_attr(SHIFTERS.get(family, {})):
        attrs.append("x" + shift_attr(SHIFTERS[family]))
    if alternating(machine if parent is None else parent, players) or alternating(machine, players):
        attrs.append("a")
    if inp.get("service") == "yes":
        attrs.append("v")
    if machine.get("bclass"):
        attrs.append("b" + machine.get("bclass"))
    year = machine.findtext("year") or ""
    if family in MONITOR_CLASS:
        attrs.append("m%d" % MONITOR_CLASS[family])
    elif year[:4].isdigit() and int(year[:4]) < 1985 and displays and displays[0].get("type") != "vector":
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
            # What the ROM lists and device list say is read before they go.
            el.set("bclass", backup_class(el))
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
    if MISSING_LAYOUT:
        print("%d multi-screen romsets have no layout in layouts.json (re-run layouts.py): %s" % (
            len(MISSING_LAYOUT), ", ".join(sorted(MISSING_LAYOUT)[:12])))


if __name__ == "__main__":
    main()
