#!/usr/bin/env python3
"""Find a driver whose SHARED port set gives every game of it a control no cabinet had.

Taito F3's `f3` ports declare two paddle dials (DIAL.0 and DIAL.1) for all 35 of its games, and only Arkanoid Returns reads them: with them every F3 game was drawn with a spinner
where its joystick was (docs/dev/arcade-cabinets.md, "The audit"). `-listxml` cannot say which games really have a control, but a rare control (a dial, a trackball, a light gun,
a paddle, a pedal, an analog stick, a keypad) that EVERY parent game of a driver carries is a suspect: this lists them.

    python Tools/arcade/shared_controls.py path/to/mame0289.xml

Read the list by hand. A driver whose games are all one kind is fine (Exidy 440's and American Laser Games' guns, the pinball keypads, Hard Drivin's gear stick); one whose games are
not is a shared port set, and its control belongs in `SPURIOUS` in `gen_game_index.py`. The 2026-10-26 run found Taito F3's dial and nothing else.
"""
import collections
import sys
import xml.etree.ElementTree as ET

RARE = ("dial", "trackball", "lightgun", "paddle", "pedal", "stick", "doublejoy", "positional", "mouse", "keyboard", "keypad")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    by_driver = collections.defaultdict(list)
    for _ev, el in ET.iterparse(sys.argv[1], events=("end",)):
        if el.tag != "machine":
            continue
        inp = el.find("input")
        if el.get("isdevice") != "yes" and el.get("isbios") != "yes" and el.get("runnable", "yes") != "no" and not el.get("cloneof") \
                and inp is not None and int(inp.get("coins", "0") or 0) >= 1:
            by_driver[el.get("sourcefile", "")].append((el.get("name"), {c.get("type") for c in inp.findall("control")}))
        el.clear()
    rows = []
    for source, games in by_driver.items():
        if len(games) < 5:
            continue
        for kind in RARE:
            have = [g[0] for g in games if kind in g[1]]
            if len(have) / len(games) >= 0.9 and len(have) >= 5:
                rows.append((len(have), source, kind, len(games), have[:6]))
    for row in sorted(rows, reverse=True):
        print("%4d of %-4d %-34s %-10s %s" % (row[0], row[3], row[1], row[2], " ".join(row[4])))


if __name__ == "__main__":
    main()
