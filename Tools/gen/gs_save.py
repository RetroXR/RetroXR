"""Inspect, and optionally unlock Mystery Gift in, a Pokemon Gold/Silver save.

    python gs_save.py <save>                      # report only
    python gs_save.py <save> --unlock <out>       # write a patched COPY to <out>
    python gs_save.py <save> --unlock <out> --id 12345 --name RED

Never writes the input. Offsets are pokegold's (pret/pokegold symbols branch):
SRAM bank 0 is the file's first 0x2000 bytes and bank 1 the next.

  0x0BE2 sMysteryGiftItem           0x2000 sOptions
  0x0BE3 sMysteryGiftUnlocked       0x2008 sCheckValue1 (99)
  0x0BE4 sBackupMysteryGiftItem     0x2009 sGameData (wPlayerID first)
  0x0BE5 sNumDailyMysteryGiftPartnerIDs
  0x0BE6 sDailyMysteryGiftPartnerIDs (5 x 2)
                                    0x2D69 sChecksum (LE sum of 0x2009..0x2D68)
                                    0x2D6B sCheckValue2 (127)

The main menu offers MYSTERY GIFT when a save exists and
sNumDailyMysteryGiftPartnerIDs is not 0xFF; none of bank 0's Mystery Gift bytes
are under the checksum.
"""
import sys

GAME = 0x2009
CHK = 0x2D69
NAME = GAME + 2

CHARS = {0x50: "", 0x7F: " "}
for i in range(26):
    CHARS[0x80 + i] = chr(ord("A") + i)
    CHARS[0xA0 + i] = chr(ord("a") + i)
for i in range(10):
    CHARS[0xF6 + i] = str(i)


def decode(raw):
    out = ""
    for b in raw:
        if b == 0x50:
            break
        out += CHARS.get(b, "?")
    return out


def encode(text, width):
    inv = {v: k for k, v in CHARS.items() if v}
    raw = bytes(inv[c] for c in text) + b"\x50"
    return raw.ljust(width, b"\x50")[:width]


def checksum(data):
    return sum(data[GAME:CHK]) & 0xFFFF


def report(data, label):
    stored = data[CHK] | (data[CHK + 1] << 8)
    print("%s: %d bytes" % (label, len(data)))
    print("  check values  %d / %d (want 99 / 127)" % (data[0x2008], data[0x2D6B]))
    print("  checksum      stored %04X, computed %04X%s"
          % (stored, checksum(data), "" if stored == checksum(data) else "  MISMATCH"))
    print("  trainer       id %05d name '%s'"
          % ((data[GAME] << 8) | data[GAME + 1], decode(data[NAME:NAME + 11])))
    print("  mystery gift  item %02X unlocked %02X backup %02X partners %02X  ids %s"
          % (data[0x0BE2], data[0x0BE3], data[0x0BE4], data[0x0BE5],
             data[0x0BE6:0x0BF0].hex()))


def main():
    args = sys.argv[1:]
    src = args[0]
    data = bytearray(open(src, "rb").read())
    report(data, src)
    if "--unlock" not in args:
        return
    out = args[args.index("--unlock") + 1]
    data = data[:0x8000]
    # What the Goldenrod girl does (UnlockMysteryGift), then what the next daily
    # reset does (ResetDailyMysteryGiftLimitIfUnlocked).
    data[0x0BE2] = 0x00
    data[0x0BE3] = 0x00
    data[0x0BE4] = 0x00
    data[0x0BE5] = 0x00
    data[0x0BE6:0x0BF0] = b"\x00" * 10
    if "--id" in args:
        tid = int(args[args.index("--id") + 1])
        data[GAME] = tid >> 8
        data[GAME + 1] = tid & 0xFF
    if "--name" in args:
        data[NAME:NAME + 11] = encode(args[args.index("--name") + 1], 11)
    total = checksum(data)
    data[CHK] = total & 0xFF
    data[CHK + 1] = total >> 8
    open(out, "wb").write(data)
    report(data, out)


if __name__ == "__main__":
    main()
