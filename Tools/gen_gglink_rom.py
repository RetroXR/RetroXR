"""Two tiny Game Gear ROMs that talk over the Gear-to-Gear cable.

    python Tools/gen_gglink_rom.py     # into RetroXR/Tools/gglink/

Used by RetroXR/Tools/link/gg_link_probe.tscn. Both switch the EXT port's UART on
with its receive NMI ($05 = 0x38, 4800 bps) -- the way the commercial link games
use it -- and then paint the backdrop with what the NMI saw:

    black  no NMI has ever fired (a core with no link driver)
    blue   "the other Game Gear is not there" (bit 2 of $05)
    green  the right byte arrived
    red    a byte arrived and it was the wrong one

The master sends 0xA5 whenever its send buffer is free; the slave answers every
byte it receives with 0x5A from inside its NMI. So a cabled pair is green on both
screens, and each screen is green only because the OTHER machine's byte reached
it. The display is left switched off: the VDP then draws nothing but the
backdrop, which is the one colour these ROMs set.
"""

import os
import sys

BLACK, BLUE, GREEN, RED = 0x0000, 0x0F00, 0x00F0, 0x000F   # ----BBBBGGGGRRRR

MASTER_SENDS, SLAVE_SENDS = 0xA5, 0x5A


class Asm:
    """Just enough of a Z80 assembler: bytes, labels, and the jumps between them."""

    def __init__(self):
        self.rom = bytearray(0x8000)
        self.pc = 0
        self.labels = {}
        self.fixups = []

    def org(self, addr):
        self.pc = addr

    def label(self, name):
        self.labels[name] = self.pc

    def db(self, *data):
        for b in data:
            self.rom[self.pc] = b & 0xFF
            self.pc += 1

    def jr(self, opcode, name):
        self.db(opcode, 0)
        self.fixups.append(("rel", self.pc - 1, name))

    def abs16(self, opcode, name):
        self.db(opcode, 0, 0)
        self.fixups.append(("abs", self.pc - 2, name))

    def ld_de(self, value):
        self.db(0x11, value & 0xFF, value >> 8)

    def link(self):
        for kind, at, name in self.fixups:
            target = self.labels[name]
            if kind == "rel":
                off = target - (at + 1)
                assert -128 <= off <= 127, name
                self.rom[at] = off & 0xFF
            else:
                self.rom[at] = target & 0xFF
                self.rom[at + 1] = target >> 8


def build(master):
    a = Asm()
    JR, JR_NZ, JR_Z, CALL, JP = 0x18, 0x20, 0x28, 0xCD, 0xC3

    a.org(0x0000)
    a.db(0xF3)                  # di
    a.db(0xED, 0x56)            # im 1
    a.db(0x31, 0xF0, 0xDF)      # ld sp,$DFF0
    a.abs16(JP, "main")

    a.org(0x0038)
    a.db(0xFB, 0xED, 0x4D)      # ei ; reti  (never enabled)

    a.org(0x0066)               # NMI: the only place anything is decided
    a.db(0xF5, 0xD5)            # push af ; push de
    a.db(0xDB, 0x05)            # in a,($05)
    a.db(0xCB, 0x4F)            # bit 1,a     receive buffer full?
    a.jr(JR_NZ, "rx")
    a.db(0xCB, 0x57)            # bit 2,a     far end missing?
    a.jr(JR_Z, "done")
    a.ld_de(BLUE)
    a.abs16(CALL, "setcol")
    a.jr(JR, "done")
    a.label("rx")
    a.db(0xDB, 0x04)            # in a,($04)
    a.db(0xFE, SLAVE_SENDS if master else MASTER_SENDS)   # cp expected
    a.jr(JR_NZ, "bad")
    a.ld_de(GREEN)
    a.abs16(CALL, "setcol")
    if not master:
        a.db(0x3E, SLAVE_SENDS, 0xD3, 0x03)                # ld a,n ; out ($03),a
    a.jr(JR, "done")
    a.label("bad")
    a.ld_de(RED)
    a.abs16(CALL, "setcol")
    a.label("done")
    a.db(0xD1, 0xF1)            # pop de ; pop af
    a.db(0xED, 0x45)            # retn

    a.org(0x0100)
    a.label("main")
    a.db(0x3E, 0x00, 0xD3, 0xBF, 0x3E, 0x87, 0xD3, 0xBF)  # VDP reg 7 = 0 (backdrop = CRAM 16)
    a.db(0x3E, 0x00, 0xD3, 0xBF, 0x3E, 0x81, 0xD3, 0xBF)  # VDP reg 1 = 0 (display off)
    a.ld_de(BLACK)
    a.abs16(CALL, "setcol")
    a.db(0x3E, 0x38, 0xD3, 0x05)                          # $05 = UART on, NMI on receive
    a.label("loop")
    if master:
        a.db(0x01, 0x00, 0x20)  # ld bc,$2000   (about 60 ms)
        a.label("delay")
        a.db(0x0B, 0x78, 0xB1)  # dec bc ; ld a,b ; or c
        a.jr(JR_NZ, "delay")
        a.db(0xDB, 0x05, 0xCB, 0x47)                      # in a,($05) ; bit 0,a
        a.jr(JR_NZ, "loop")                               # still sending
        a.db(0x3E, MASTER_SENDS, 0xD3, 0x03)              # out ($03),a
    a.jr(JR, "loop")

    # DE = colour, into CRAM 0 and 16 (the backdrop, whichever the VDP picks).
    a.label("setcol")
    for addr in (0x00, 0x20):
        a.db(0x3E, addr, 0xD3, 0xBF, 0x3E, 0xC0, 0xD3, 0xBF)
        a.db(0x7B, 0xD3, 0xBE, 0x7A, 0xD3, 0xBE)          # ld a,e ; out ; ld a,d ; out
    a.db(0xC9)

    a.link()
    a.rom[0x7FF0:0x7FF8] = b"TMR SEGA"
    a.rom[0x7FFF] = 0x7C        # Game Gear, international, 32 KB
    return bytes(a.rom)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "RetroXR", "Tools", "gglink")
    os.makedirs(out, exist_ok=True)
    for name, master in (("link_master.gg", True), ("link_slave.gg", False)):
        path = os.path.join(out, name)
        with open(path, "wb") as f:
            f.write(build(master))
        print("wrote", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
