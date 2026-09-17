"""Build RetroXR's table of N64 cartridges moulded in a colour other than grey.

Colours per region come from micro-64's workbook of coloured cartridges
(http://micro-64.com/database/colouredcarts.shtml); ROM identities come from
mupen64plus-libretro-nx's ROM database, the same source as gen_n64_save_db.py:

    python Tools/gen_n64_cart_colors.py
    python Tools/gen_n64_cart_colors.py --xlsx ColouredN64Cartridges.xlsx
    python Tools/gen_n64_cart_colors.py --check Z:/roms/n64

Each release is keyed by ROM MD5 in .z64 byte order (what RomM reports) and by
the header CRC pair plus the market its country byte names (what a local file in
any byte order can be read for without hashing it). The CRC pair alone is not
enough: it does not cover the country byte, and Ocarina of Time's USA and Japan
releases share one. A game absent from the table shipped in grey. --check hashes
the candidate ROMs in a folder and prints what each one resolves to.
"""

import argparse
import hashlib
import os
import re
import sys
import tempfile
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_n64_save_db import DEFAULT_INI, crc_key, read_entries, resolved  # noqa: E402

XLSX_URL = "http://micro-64.com/database/ColouredN64Cartridges.xlsx"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "RetroXR",
                   "Scripts", "Data", "n64_cart_colors_table.gd")

# Workbook title -> the database's GoodName title.
TITLES = {
    "007: The World Is Not Enough": "007 - The World is Not Enough",
    "Aidyn Chronicles: First Mage": "Aidyn Chronicles - The First Mage",
    "Army Men: Air Combat": "Army Men - Air Combat",
    "Army Men: Sarge's Heroes 2": "Army Men - Sarge's Heroes 2",
    "Bass Masters 2000": "Bassmasters 2000",
    "Hydro Thunder": "Hydro Thunder",
    "Legend of Zelda: Ocarina of Time": "Legend of Zelda, The - Ocarina of Time",
    "Road Rash": "Road Rash 64",
    "Rugrats in Paris: The Movie": "Rugrats in Paris - The Movie",
    "Scooby Doo! Classic Creep Capers": "Scooby-Doo! - Classic Creep Capers",
    "Tom Clancy's Rainbow Six": "Tom Clancy's Rainbow Six",
    "Turok 2: Seeds of Evil": "Turok 2 - Seeds of Evil",
    "Turok: Rage Wars": "Turok - Rage Wars",
    "Armorines: Project S.W.A.R.M.": "Armorines - Project S.W.A.R.M.",
    "Batman Beyond: Return of the Joker": "Batman Beyond - Return of the Joker",
    "BattleTanx Global Assault": "BattleTanx - Global Assault",
    "Donkey Kong 64": "Donkey Kong 64",
    "Earthworm Jim 3D": "Earthworm Jim 3D",
    "ECW: Hardcore Revolution": "ECW Hardcore Revolution",
    "Jeremy McGrath Supercross 2000": "Jeremy McGrath Supercross 2000",
    "NBA Jam 2000": "NBA Jam 2000",
    "Nuclear Strike 64": "Nuclear Strike 64",
    "Power Rangers Lightspeed Rescue": "Power Rangers - Lightspeed Rescue",
    "Rayman 2": "Rayman 2 - The Great Escape",
    "Rocket: Robot On Wheels": "Rocket - Robot on Wheels",
    "Tony Hawk Pro Skater": "Tony Hawk's Pro Skater",
    "Tony Hawk Pro Skater 2": "Tony Hawk's Pro Skater 2",
    "Turok 3: Shadow of Oblivion": "Turok 3 - Shadow of Oblivion",
    "WWF No Mercy": "WWF No Mercy",
    "WWF Wrestlemania 2000": "WWF WrestleMania 2000",
    "The Legend of Zelda: Majora's Mask": "Legend of Zelda, The - Majora's Mask",
    "Pokemon Stadium 2": "Pokemon Stadium 2",
    "Fighter Destiny 2": "Fighter Destiny 2",
    "Rally '99 (Rally 2000 NTSC)": "Rally Challenge 2000",
    "All-Star Baseball 2001": "All-Star Baseball 2001",
    "Battlezone: Rise of the Black Dogs": "Battlezone - Rise of the Black Dogs",
    "Madden NFL 2001": "Madden NFL 2001",
    "Madden NFL 2002": "Madden NFL 2002",
    "NFL Quarterback Club 2001": "NFL Quarterback Club 2001",
    "Spiderman": "Spider-Man",
    "Tony Hawks Pro Skater 3": "Tony Hawk's Pro Skater 3",
    "WCW Backstage Assault": "WCW Backstage Assault",
}

# Workbook colour word -> CartridgeShellPalette preset id.
SHELLS = {
    "grey": "grey", "gray": "grey", "black": "black", "blue": "blue",
    "yellow": "yellow", "red": "red", "green": "green", "gold": "gold",
    "gold & silver": "gold_silver",
}

# GoodName region code -> workbook market.
MARKETS = {"U": "us", "E": "eu", "G": "eu", "F": "eu", "S": "eu", "I": "eu",
           "A": "au", "J": "jp"}

# Builds that are not a retail cartridge of the release.
NOT_A_CARTRIDGE = re.compile(
    r"^(Beta|Kiosk Demo|Demo|Preview Demo|Debug Version|GC|VC|iQue|Manual|PD|Proto.*|.*Hack|\d{4}-\d\d-\d\d)$")
# Dump tags that are a different program: hacks, translations, trainers, pirates.
NOT_THE_DUMP = re.compile(r"^\[(h|T|t|p)")


def fetch_xlsx(path):
    if path:
        return path
    dest = os.path.join(tempfile.gettempdir(), "ColouredN64Cartridges.xlsx")
    urllib.request.urlretrieve(XLSX_URL, dest)
    return dest


def parse_cell(text):
    """{market: shell} for one workbook cell; "" is the column's own market."""
    text = (text or "").strip()
    if not text or text.lower() == "unreleased":
        return {}
    out = {}
    for part in text.split("/"):
        words = part.strip()
        market = ""
        if words.endswith(" AUS"):
            market, words = "au", words[:-4]
        elif words.endswith(" PAL"):
            market, words = "eu", words[:-4]
        if words.startswith("NFR "):
            continue
        shell = SHELLS.get(words.strip().lower())
        if shell is None:
            sys.exit("unknown colour %r in cell %r" % (words, text))
        # A coloured run and its grey reissue share one ROM; the colour is the release.
        if market in out and shell == "grey":
            continue
        out[market] = shell
    return out


def read_workbook(path):
    import openpyxl
    sheet = openpyxl.load_workbook(path, read_only=True).worksheets[0]
    releases = {}
    for row in sheet.iter_rows(values_only=True):
        title = row[0]
        if not title or title == "Game List" or title == "Worldwide Cartridge Colours":
            continue
        if title not in TITLES:
            sys.exit("no GoodName title for workbook row %r" % title)
        base = TITLES[title]
        for column, market in ((1, "us"), (2, "eu"), (3, "jp")):
            for sub, shell in parse_cell(row[column]).items():
                releases[(base, sub or market)] = shell
    return releases


def split_goodname(name):
    """(title, market, eligible) for a GoodName, market None when unrecognised."""
    m = re.match(r"^(.*?) \((.*)$", name)
    if not m:
        return name, None, False
    title = m.group(1)
    rest = "(" + m.group(2)
    parens = re.findall(r"\(([^)]*)\)", rest)
    brackets = re.findall(r"\[[^\]]*\]", rest)
    market = MARKETS.get(parens[0]) if parens else None
    eligible = not any(NOT_A_CARTRIDGE.match(p) for p in parens[1:]) \
        and not any(NOT_THE_DUMP.match(b) for b in brackets)
    return title, market, eligible


def shell_for(releases, title, market):
    if market == "au":
        return releases.get((title, "au"), releases.get((title, "eu")))
    return releases.get((title, market))


def build(entries, releases):
    by_md5, au_md5 = {}, {}
    votes, au_votes = {}, {}
    matched = set()
    for md5, e in entries.items():
        title, market, eligible = split_goodname(resolved(entries, e, "GoodName") or "")
        coloured = market is not None and (
            (title, market) in releases or (market == "eu" and (title, "au") in releases))
        if coloured and not eligible:
            continue
        shell = shell_for(releases, title, market) if coloured else None
        au = releases.get((title, "au")) if market == "eu" else None
        if coloured:
            matched.add((title, market))
            if au:
                matched.add((title, "au"))
        if shell and shell != "grey":
            by_md5[md5] = shell
        if au:
            au_md5[md5] = au
        k = crc_key(e, entries)
        if k and market:
            k = "%s:%s" % (k, "eu" if market == "au" else market)
            votes.setdefault(k, set()).add(shell if shell and shell != "grey" else "grey")
            au_votes.setdefault(k, set()).add(au or "")
    missing = sorted(r for r, s in releases.items() if s != "grey" and r not in matched)
    if missing:
        sys.exit("releases with no ROM in the database: %s" % missing)
    by_crc = {k: v.pop() for k, v in votes.items() if len(v) == 1 and "grey" not in v}
    au_crc = {k: v.pop() for k, v in au_votes.items() if len(v) == 1 and "" not in v}
    return by_md5, by_crc, au_md5, au_crc


def write_table(path, tables):
    out = ["## Generated by Tools/gen_n64_cart_colors.py from micro-64's coloured cartridge",
           "## workbook and mupen64plus-libretro-nx's ROM database. Do not edit; re-run",
           "## the script.",
           "class_name N64CartColorsTable", ""]
    docs = {
        "SHELL_MD5": "## ROM MD5 (.z64 byte order) -> CartridgeShellPalette preset id.",
        "SHELL_CRC": "## Header \"CRC1-CRC2:market\" -> preset id, where every dump under it agrees.",
        "AUSTRALIA_MD5": "## PAL ROMs whose Australian run was moulded apart from the rest of PAL.",
        "AUSTRALIA_CRC": "## The same, by \"CRC1-CRC2:eu\" header key.",
    }
    for name, table in tables.items():
        out.append(docs[name])
        out.append("const %s := {" % name)
        out.extend('\t"%s": "%s",' % (k, table[k]) for k in sorted(table))
        out.append("}")
        out.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))


def z64_bytes(data):
    head = data[:4]
    if head == b"\x37\x80\x40\x12":
        swapped = bytearray(len(data))
        swapped[0::2], swapped[1::2] = data[1::2], data[0::2]
        return bytes(swapped)
    if head == b"\x40\x12\x37\x80":
        out = bytearray(data)
        for i in range(0, len(out) - 3, 4):
            out[i:i + 4] = out[i:i + 4][::-1]
        return bytes(out)
    return data


# Header country byte (0x3E) -> market. Australia ('U') keys with PAL.
COUNTRIES = {"E": "us", "N": "us", "J": "jp", "U": "eu", "P": "eu", "X": "eu", "Y": "eu",
             "D": "eu", "F": "eu", "S": "eu", "I": "eu", "H": "eu", "W": "eu", "L": "eu"}


def header_crc(head):
    head = z64_bytes(head[:0x40])
    if len(head) < 0x40 or head[:4] != b"\x80\x37\x12\x40":
        return ""
    market = COUNTRIES.get(chr(head[0x3E]))
    if market is None:
        return ""
    return "%s-%s:%s" % (head[0x10:0x14].hex().upper(), head[0x14:0x18].hex().upper(), market)


def check(folder, tables, entries):
    """Every ROM whose header CRC is coloured or whose name carries a coloured
    title, hashed whole: prints what MD5 and CRC each resolve to, and fails when
    the two disagree."""
    by_md5, by_crc, au_md5, au_crc = tables
    names = {md5: resolved(entries, e, "GoodName") for md5, e in entries.items()}
    titles = [re.sub(r"[^a-z0-9]", "", t.split(" - ")[0].lower()) for t in TITLES.values()]
    rows, disagreements = [], 0
    for name in sorted(os.listdir(folder)):
        if os.path.splitext(name)[1].lower() not in (".z64", ".v64", ".n64"):
            continue
        path = os.path.join(folder, name)
        with open(path, "rb") as f:
            crc = header_crc(f.read(0x40))
        flat = re.sub(r"[^a-z0-9]", "", name.lower())
        if crc not in by_crc and not any(flat.startswith(t) for t in titles):
            continue
        with open(path, "rb") as f:
            md5 = hashlib.md5(z64_bytes(f.read())).hexdigest()
        shell_md5, shell_crc = by_md5.get(md5, "grey"), by_crc.get(crc, "grey")
        au = au_md5.get(md5, "")
        if shell_md5 != shell_crc or au != au_crc.get(crc, ""):
            disagreements += 1
        rows.append((shell_md5, shell_crc, au, name, names.get(md5, "(not in database)")))
    for shell_md5, shell_crc, au, name, good in rows:
        flag = "" if shell_md5 == shell_crc else "  <-- CRC says " + shell_crc
        print("%-12s %-7s %-72s %s%s" % (shell_md5, au, name, good, flag))
    coloured = sum(1 for r in rows if r[0] != "grey" or r[2])
    print("%d candidate ROMs, %d coloured, %d MD5/CRC disagreements" % (
        len(rows), coloured, disagreements))
    if disagreements:
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ini", default=DEFAULT_INI)
    parser.add_argument("--xlsx", help="local copy of the workbook (default: download)")
    parser.add_argument("--out", default=OUT)
    parser.add_argument("--check", metavar="ROM_DIR", help="hash a ROM folder and report")
    args = parser.parse_args()
    if not os.path.isfile(args.ini):
        sys.exit("no ROM database at %s" % args.ini)

    entries = read_entries(args.ini)
    releases = read_workbook(fetch_xlsx(args.xlsx))
    by_md5, by_crc, au_md5, au_crc = build(entries, releases)
    if args.check:
        check(args.check, (by_md5, by_crc, au_md5, au_crc), entries)
        return
    tables = {"SHELL_MD5": by_md5, "SHELL_CRC": by_crc,
              "AUSTRALIA_MD5": au_md5, "AUSTRALIA_CRC": au_crc}
    write_table(args.out, tables)
    for name, table in tables.items():
        print("%-14s %d" % (name, len(table)))


if __name__ == "__main__":
    main()
