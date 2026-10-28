#!/usr/bin/env python3
"""Rewrite the firmware block of RetroXR/libretro-core-info-retroxr/mame_libretro.info (and mamearcade's) from MAME's `-listxml`.

The BIOS page lists a core's firmware from its .info. MAME's vendored .info declares none, and the
fifteen sets the overlay began with (neogeo, qsound, pgm...) were typed by hand: System 246, 256 and
573, the whole of NAOMI and the Capcom, Taito and Sony boards were simply not on the page. What a game
wants is MAME's own information, so this reads it from there.

    python Tools/arcade/gen_mame_bios.py path/to/mame0289.xml          # rewrites every overlay in place
    python Tools/arcade/gen_mame_bios.py path/to/mame0289.xml --check  # prints the block, writes nothing
    python Tools/arcade/gen_mame_bios.py --sync                        # no XML: copies mame's block to the others

The XML is `mame -listxml` (or the unzipped `mame0289lx.zip` a MAME release carries; 320 MB, streamed).

Two cores are current MAME: `mame` (the desktop's) and `mamearcade` ("MAME (Git)", the arcade half alone, which is
the one a Quest runs -- its .info says Android cannot take the whole set). They are the same code, so they take
the same list, and a player with only the Quest's core used to see the FinalBurn Neo sets and no MAME ones: a core
with nothing to declare is silent on the page. An overlay REPLACES the vendored entry, so `mamearcade`'s is made
here, whole, from the vendored one (TARGETS).

What goes on the list:

  BIOS sets   every `isbios` machine that a coin-taking game names as its `romof` (directly or through
              its parent), plus the few arcade boards whose drivers take no coin yet and so look like
              nothing to that rule (System 246/256 -- Taiko no Tatsujin 7 on, Tekken 4 --, Lindbergh,
              Triforce...: ALLOW). Consoles, toys and computers that happen to share a driver
              file with a BIOS are left out (EXCLUDE).
  device sets a device with ROMs of its own (QSound's DSP, the Namco I/O MCUs, Sega's JVS board, the
              YM2413's patch ROM...) that at least DEVICE_MIN coin-taking games use. A split MAME
              set ships each of these as a zip of its own, named for the device, or for the device it
              is merged with (`qsound_hle` takes `qsound.zip`). The long tail is a computer's keyboard
              or a disk drive and no arcade game names it, so it is not here.

The first fifteen entries are the hand-written ones, in their order and with their words (HAND), so
what a player already knew keeps its place; the rest follow, BIOS sets by the games that want them,
then device sets by the same. Every entry is optional: only the games on that hardware want it.
"""
import argparse
import collections
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "RetroXR"
OVERLAY_DIR = ROOT / "libretro-core-info-retroxr"
VENDORED_DIR = ROOT / "libretro-core-info"

# Every current-MAME build, the first being the one the block is read back from (--sync).
TARGETS = ["mame_libretro.info", "mamearcade_libretro.info"]
INFO = OVERLAY_DIR / TARGETS[0]

# MAME looks in the ROM folder, SYSTEMDIR/mame/bios and SYSTEMDIR/mame/roms (the overlay's notes).
FOLDER = "mame/bios"

# The sets the overlay began with, in order, with the words a player already read.
HAND = {
    "neogeo": "Neo Geo MVS/AES BIOS - every Neo Geo game (KOF, Metal Slug, Fatal Fury...)",
    "qsound": "Capcom QSound DSP - CPS-1 QSound games (Cadillacs and Dinosaurs, Punisher...) and every CPS-2 game",
    "pgm": "PolyGame Master BIOS",
    "skns": "Super Kaneko Nova System BIOS",
    "stvbios": "Sega ST-V BIOS",
    "cchip": "Taito C-Chip internal ROM",
    "nmk004": "NMK004 sound CPU internal ROM",
    "ym2608": "YM2608 internal ROM",
    "decocass": "DECO Cassette System BIOS",
    "bubsys": "Konami Bubble System BIOS",
    "isgsm": "ISG Selection Master BIOS",
    "midssio": "Midway SSIO sound board internal ROM",
    "namcoc69": "Namco C69 internal ROM",
    "namcoc70": "Namco C70 internal ROM",
    "namcoc75": "Namco C75 internal ROM",
}

# The sets a player looks for by name: the board's family in words, then games to name it by, as MAME's
# shortnames. The titles come from MAME's own description of each (so none is typed from memory), and a
# shortname that is not one of the BIOS's games stops the run.
NOTES = {
    "sys573": ("Konami System 573", ["ddr2m", "gtfrk10m", "drmn", "dsem"]),
    "sys246": ("Namco System 246 (PlayStation 2 based)", ["taiko7", "tekken4", "soulclb2", "timecrs3"]),
    "sys256": ("Namco System 256 (PlayStation 2 based)", ["gdvsgd", "kinniku", "tekken51", "timecrs4"]),
    "naomi": ("Sega NAOMI", ["vtenis2c", "mvsc2", "crzytaxi", "pstone2", "samba", "zombrvn"]),
    "naomi2": ("Sega NAOMI 2", ["vf4", "vf4evo", "clubk2k3"]),
    "naomigd": ("Sega NAOMI GD-ROM games", ["cvs2", "puyofev", "ggxxrl"]),
    "awbios": ("Sammy Atomiswave", ["mslug6", "kofxi", "ggisuka", "dolphin"]),
    "chihiro": ("Sega Chihiro (Xbox based)", ["outr2st", "vcop3", "ghostsqu", "wangmid2"]),
    "kviper": ("Konami Viper", ["sscopex", "mocapb", "wcombat", "thrild2"]),
    "kpython2": ("Konami Python 2 (PlayStation 2 based)", ["ddrsn2a", "dance864", "gtrfrkv2a", "drmnv2a"]),
    "konamigx": ("Konami System GX", ["sexyparo", "rungun2", "soccerss", "le2"]),
    "konamigv": ("Konami GV (PlayStation based)", ["simpbowl", "btchamp", "hyperath", "kdeadeye"]),
    "gq863": ("Konami Twinkle", ["bmiidx", "bmiidx3", "bmiidx6"]),
    "coh1000c": ("Capcom ZN-1", ["sfexp", "starglad"]),
    "coh3002c": ("Capcom ZN-2", ["sfex2p", "rvschool", "strider2", "techromn"]),
    "playch10": ("Nintendo PlayChoice-10", ["pc_smb", "pc_duckh", "pc_mtoid", "pc_grdus"]),
    "nss": ("Nintendo Super System", ["nss_smw", "nss_fzer", "nss_con3"]),
    "megatech": ("Sega Mega-Tech", ["mt_sonic", "mt_aftrb", "mt_astrm"]),
    "megaplay": ("Sega Mega Play", ["mp_gaxe2", "mp_gunhe", "mp_col3"]),
    "atarisy1": ("Atari System 1", ["marble", "peterpak", "indytemp", "roadblst"]),
    "hng64": ("SNK Hyper Neo Geo 64", ["fatfurwa", "sams64", "bbust2", "buriki"]),
    "hikaru": ("Sega Hikaru", ["airtrix", "braveff", "pharrier", "swracer"]),
    "taitotz": ("Taito Type Zero", ["batlgear", "raizpin", "landhigh"]),
    "lindbios": ("Sega Lindbergh (PC based)", ["hotd4", "initiad4", "abclimax", "outr2sdx"]),
    "triforce": ("Sega Triforce (GameCube based)", ["vs4", "fzeroax", "mkartagp", "avalnc13"]),
    "segasp": ("Sega System SP (Spider)", ["dinoking", "bingogal", "kazaaan"]),
}

# Machines that are `isbios` and share a driver with arcade games, but are no arcade board's BIOS.
EXCLUDE = {
    "3dobios": "a 3DO console",
    "miuchiz": "a toy",
    "slvrball": "a pinball machine's controller board",
    "su2000": "a PC",
    "tourvis": "a PC Engine bootleg console",
    "sfcbox": "the Super Famicom Box, a hotel console",
}

# Arcade boards whose drivers take no coin yet (so no coin-taking game names the BIOS), by hand.
ALLOW = {"sys246", "sys256", "lindbios", "triforce", "kpython", "systemy2", "alg3do"}

# A device set is listed once at least this many coin-taking games use it.
DEVICE_MIN = 20


def load(path):
    """Every machine, reduced to what this needs. Streamed: the XML is 320 MB."""
    machines = {}
    for _, el in ET.iterparse(path, events=("end",)):
        if el.tag != "machine":
            continue
        inp = el.find("input")
        try:
            coins = int(inp.get("coins") or 0) if inp is not None else 0
        except ValueError:
            coins = 0
        machines[el.get("name")] = {
            "isbios": el.get("isbios") == "yes",
            "isdevice": el.get("isdevice") == "yes",
            "runnable": el.get("runnable") != "no",
            "cloneof": el.get("cloneof"),
            "romof": el.get("romof"),
            "desc": el.findtext("description") or "",
            "mfr": el.findtext("manufacturer") or "",
            # [name, status, merge] of each ROM that has a name at all
            "roms": [[r.get("name"), r.get("status") or "good", r.get("merge") or ""] for r in el.findall("rom") if r.get("name")],
            "devrefs": [d.get("name") for d in el.findall("device_ref")],
            "coins": coins,
        }
        el.clear()
    return machines


def bios_chain(machines, name):
    """The BIOS sets a game names through its romof chain."""
    out, seen, cur = [], set(), machines[name]["romof"]
    while cur and cur not in seen and cur in machines:
        seen.add(cur)
        if machines[cur]["isbios"]:
            out.append(cur)
        cur = machines[cur]["romof"]
    return out


def real_roms(machine):
    return [r for r in machine["roms"] if r[1] != "nodump"]


def device_zip(machines, name):
    """The zip a device's ROMs live in: its own, or its parent's when every ROM is merged into it
    (`qsound_hle` has `dl-1425.bin` merge="dl-1425.bin" and romof qsound)."""
    cur, seen = name, set()
    while True:
        v = machines[cur]
        parent = v["romof"]
        roms = real_roms(v)
        if parent and parent in machines and parent not in seen and roms and all(r[2] for r in roms):
            seen.add(cur)
            cur = parent
        else:
            return cur


def title(desc):
    """A game's name without the version brackets MAME adds."""
    prev = None
    while prev != desc:
        prev = desc
        desc = re.sub(r"\s*\([^)]*\)\s*$", "", desc)
    return desc.strip()


def examples(machines, games, n=3):
    """The best known games among `games`: the parents with the most clones, a good proxy for a famous title."""
    clones = collections.Counter(machines[g]["cloneof"] for g in games if machines[g]["cloneof"])
    parents = [g for g in games if not machines[g]["cloneof"]] or games
    parents.sort(key=lambda g: (-clones[g], g))
    seen, out = set(), []
    for g in parents:
        t = title(machines[g]["desc"])
        if t not in seen:
            seen.add(t)
            out.append(t)
        if len(out) == n:
            break
    return out


def count(n):
    return "%d game%s" % (n, "" if n == 1 else "s")


def clean(text):
    return text.replace('"', "'").replace("|", "/")


def build(machines):
    arcade = {k: v for k, v in machines.items() if v["runnable"] and not v["isdevice"] and not v["isbios"]}
    coin_games = {k for k, v in arcade.items() if v["coins"] > 0}

    wanted = collections.defaultdict(list)
    for g in arcade:
        for b in bios_chain(machines, g):
            wanted[b].append(g)
    bios = []
    for b, games in wanted.items():
        if b in EXCLUDE or b in HAND:
            continue
        if not (b in ALLOW or any(g in coin_games for g in games)):
            continue
        bios.append((b, games))
    bios.sort(key=lambda x: (-len(x[1]), x[0]))

    users = collections.defaultdict(set)
    for g in coin_games:
        for d in set(machines[g]["devrefs"]):
            dev = machines.get(d)
            if dev and dev["isdevice"] and real_roms(dev):
                users[device_zip(machines, d)].add(g)
    devices = [(z, sorted(gs)) for z, gs in users.items() if len(gs) >= DEVICE_MIN and z not in HAND and z not in wanted]
    devices.sort(key=lambda x: (-len(x[1]), x[0]))

    rows = []
    for name, text in HAND.items():
        rows.append((name, text))
    for b, games in bios:
        v = machines[b]
        if b in NOTES:
            family, names = NOTES[b]
            for n in names:
                if n not in games:
                    sys.exit("NOTES[%s]: %s is not one of the BIOS's games in this MAME" % (b, n))
            text = "%s - %s - %s" % (family, ", ".join(title(machines[n]["desc"]) for n in names), count(len(games)))
        else:
            text = "%s (%s) - %s, e.g. %s" % (title(v["desc"]), v["mfr"], count(len(games)), ", ".join(examples(machines, games)))
        rows.append((b, clean(text)))
    for z, games in devices:
        v = machines[z]
        text = "%s device ROM - used by %s, e.g. %s" % (title(v["desc"]), count(len(games)), ", ".join(examples(machines, games)))
        rows.append((z, clean(text)))
    return rows, len(bios), len(devices)


def block(rows):
    lines = ["firmware_count = %d" % len(rows)]
    for i, (name, text) in enumerate(rows):
        lines.append('firmware%d_desc = "%s/%s.zip (%s)"' % (i, FOLDER, name, text))
        lines.append('firmware%d_path = "%s/%s.zip"' % (i, FOLDER, name))
        lines.append('firmware%d_opt = "true"' % i)
    return "\n".join(lines) + "\n"


def rewrite(text, new_block):
    """Replace every firmware line with the block, after the `# Firmware` comment."""
    kept = [ln for ln in text.splitlines() if not re.match(r"firmware(_count|\d+_(desc|path|opt))\s*=", ln)]
    out, done = [], False
    for ln in kept:
        out.append(ln)
        if ln.strip() == "# Firmware" and not done:
            out.append(new_block.rstrip("\n"))
            done = True
    if not done:
        sys.exit("no '# Firmware' line in the overlay")
    return "\n".join(out) + "\n"


# The overlay of a core that has none yet: the vendored entry whole (an overlay replaces it), under a comment that says why it is
# here. The BIOS note is MAME's own wording for the same code (the desktop build's vendored entry says the sets may also sit in
# SYSTEMDIR/mame/bios, the arcade build's was never updated and says only the ROM folder).
SEED_HEADER = """# Arcade (MAME/Arcade), retroXR build -- the Quest's MAME.
#
# Overrides the vendored libretro-core-info entry of the same name, as mame_libretro.info does for the desktop's build
# (read that one's comment): a whole copy of the vendored entry with the BIOS and device ROM sets MAME looks for added,
# so they show on this core's BIOS list too. The two builds are one code base. The sets sit under SYSTEMDIR/mame/bios,
# which note [3] now says as the desktop build's entry does (the vendored copy of this one was never updated).
# The firmware block is GENERATED by Tools/arcade/gen_mame_bios.py, the same as the desktop build's. Do not edit it by hand.
"""
OLD_BIOS_NOTE = "[3] The BIOS files must be inside the ROM directory.|"
NEW_BIOS_NOTE = "[3] The BIOS files can be inside the ROM directory|[^] or 'SYSTEMDIR\\mame\\bios' or 'SYSTEMDIR\\mame\\roms' directory.|"


def seed(name):
    """The text of `name`'s overlay when it does not exist yet: the vendored entry, with a `# Firmware` line to hold the block."""
    vendored = (VENDORED_DIR / name).read_text(encoding="utf-8")
    if OLD_BIOS_NOTE not in vendored:
        sys.exit("%s: the BIOS note is not the one this script rewords" % name)
    lines = []
    for ln in vendored.replace(OLD_BIOS_NOTE, NEW_BIOS_NOTE).splitlines():
        if ln.startswith("database_match_archive_member"):
            lines += ["# Firmware"]
        lines.append(ln)
    return SEED_HEADER + "\n".join(lines) + "\n"


def write_all(new_block):
    """Put `new_block` in every target, making an overlay that is not there yet."""
    for name in TARGETS:
        path = OVERLAY_DIR / name
        text = path.read_text(encoding="utf-8") if path.exists() else seed(name)
        path.write_text(rewrite(text, new_block), encoding="utf-8", newline="\n")


def current_block():
    """The firmware lines of the first target, as `block` writes them."""
    lines = [ln for ln in INFO.read_text(encoding="utf-8").splitlines() if re.match(r"firmware(_count|\d+_(desc|path|opt))\s*=", ln)]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("xml", nargs="?", help="MAME's -listxml output (not needed with --sync)")
    ap.add_argument("--check", action="store_true", help="print the block and write nothing")
    ap.add_argument("--sync", action="store_true", help="no XML: copy %s's block into the other targets" % TARGETS[0])
    args = ap.parse_args()

    if args.sync:
        write_all(current_block())
        print("synced %s" % ", ".join(TARGETS), file=sys.stderr)
        return
    if not args.xml:
        ap.error("the MAME -listxml file is needed (or --sync)")
    machines = load(args.xml)
    rows, n_bios, n_dev = build(machines)
    new_block = block(rows)
    if args.check:
        sys.stdout.write(new_block)
    else:
        write_all(new_block)
    print("%d sets: %d hand-written, %d BIOS, %d device" % (len(rows), len(HAND), n_bios, n_dev), file=sys.stderr)


if __name__ == "__main__":
    main()
