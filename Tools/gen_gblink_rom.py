#!/usr/bin/env python3
"""Build the four Game Boy ROMs the link-cable probes drive.

A commercial game is a bad oracle for a cable. Getting Pokemon as far as a trade
means a scripted walk through a Pokemon Centre, and when it fails you learn that
something went wrong somewhere between the menu and the wire. These two do one
thing: swap a known byte, for ever, and paint the screen white while the byte
that came back is the right one. A photo of the two screens IS the assertion.

  master.gb  writes 0xA5 to SB, sets SC to 0x81 (start, internal clock), waits
             for the hardware to clear the start bit, and expects 0x5A back.
  slave.gb   writes 0x5A to SB, sets SC to 0x80 (start, external clock), and
             waits to be clocked by the other end; expects 0xA5.

Both then paint the screen white when the byte matched and dark grey when it did
not. The screen is one blank tile everywhere, so the palette IS the picture.
Black means the exchange has not completed even once -- which is also what a
machine with no cable in it shows, since a Game Boy waiting on an external clock
that never comes waits for ever, exactly as this does.

The _fast pair is the same exchange with SC bit 1 set, which is the Game Boy
Color's 262144 Hz clock: a transfer of 128 cycles against 4096. They carry the
CGB flag in their header, because that bit reads back as one on an original Game
Boy whatever is written and means nothing there.

Roles are split across two ROMs rather than chosen at run time because nothing a
Game Boy can see says which end of a cable it is on. A real game asks the player.

    python Tools/gen_gblink_rom.py

Writes RetroXR/Tools/gblink/link_{master,slave}.gb and link_{master,slave}_fast.gbc,
and printer.gb + printer_expected.png for the Game Boy Printer probe (see
build_printer below).

The header logo at 0x104 carries only its first four bytes, which is the
signature a loader matches to decide a file is a Game Boy ROM at all -- mGBA
refuses one without them. The other forty-four are the artwork and stay zero:
nothing reads them but a real boot ROM, and the probes turn that off.
"""
import os
import sys

# Hardware registers, as offsets from 0xFF00.
R_SB = 0x01
R_SC = 0x02
R_LY = 0x44
R_BGP = 0x47
R_LCDC = 0x40
R_BCPS = 0x68
R_BCPD = 0x69


class Asm(object):
    """Enough of a Game Boy assembler for two dozen instructions."""

    def __init__(self, org):
        self.org = org
        self.code = bytearray()
        self.labels = {}
        self.holes = []      # (offset, label, kind) kind in {"jr", "jp"}

    # -- position ---------------------------------------------------------
    def pc(self):
        return self.org + len(self.code)

    def label(self, name):
        self.labels[name] = self.pc()

    def db(self, *b):
        self.code += bytes(b)

    # -- instructions -----------------------------------------------------
    def di(self):                 self.db(0xF3)
    def nop(self):                self.db(0x00)
    def xor_a(self):              self.db(0xAF)
    def ld_a(self, n):            self.db(0x3E, n & 0xFF)
    def ld_b(self, n):            self.db(0x06, n & 0xFF)
    def ld_sp(self, nn):          self.db(0x31, nn & 0xFF, nn >> 8)
    def ld_bc(self, nn):          self.db(0x01, nn & 0xFF, nn >> 8)
    def ld_hl(self, nn):          self.db(0x21, nn & 0xFF, nn >> 8)
    def ld_hli_a(self):           self.db(0x22)
    def dec_bc(self):             self.db(0x0B)
    def dec_b(self):              self.db(0x05)
    def ld_a_b(self):             self.db(0x78)
    def or_c(self):               self.db(0xB1)
    def ldh_to(self, off):        self.db(0xE0, off & 0xFF)
    def ldh_from(self, off):      self.db(0xF0, off & 0xFF)
    def cp(self, n):              self.db(0xFE, n & 0xFF)
    def and_(self, n):            self.db(0xE6, n & 0xFF)
    def ld_c(self, n):            self.db(0x0E, n & 0xFF)
    def dec_c(self):              self.db(0x0D)
    def ld_de(self, nn):          self.db(0x11, nn & 0xFF, nn >> 8)
    def ld_a_hli(self):           self.db(0x2A)
    def ld_de_a(self):            self.db(0x12)
    def ld_a_de(self):            self.db(0x1A)
    def inc_de(self):             self.db(0x13)
    def inc_hl(self):             self.db(0x23)
    def dec_de(self):             self.db(0x1B)
    def ld_a_d(self):             self.db(0x7A)
    def or_e(self):               self.db(0xB3)
    def cp_hl(self):              self.db(0xBE)
    def ld_mem_a(self, nn):       self.db(0xEA, nn & 0xFF, nn >> 8)
    def ld_a_mem(self, nn):       self.db(0xFA, nn & 0xFF, nn >> 8)
    def push_bc(self):            self.db(0xC5)
    def pop_bc(self):             self.db(0xC1)
    def ret(self):                self.db(0xC9)

    def _rel(self, opcode, label):
        self.db(opcode)
        self.holes.append((len(self.code), label, "jr"))
        self.db(0x00)

    def jr(self, label):          self._rel(0x18, label)
    def jr_nz(self, label):       self._rel(0x20, label)
    def jr_z(self, label):        self._rel(0x28, label)

    def call(self, label):
        self.db(0xCD)
        self.holes.append((len(self.code), label, "jp"))
        self.db(0x00, 0x00)

    def jp(self, label):
        self.db(0xC3)
        self.holes.append((len(self.code), label, "jp"))
        self.db(0x00, 0x00)

    # -- link -------------------------------------------------------------
    def resolve(self):
        for off, name, kind in self.holes:
            if name not in self.labels:
                raise KeyError("undefined label " + name)
            target = self.labels[name]
            if kind == "jr":
                delta = target - (self.org + off + 1)
                if not -128 <= delta <= 127:
                    raise ValueError("jr out of range to " + name)
                self.code[off] = delta & 0xFF
            else:
                self.code[off] = target & 0xFF
                self.code[off + 1] = target >> 8
        return bytes(self.code)


def build(master, fast=False):
    a = Asm(0x150)

    a.di()
    a.ld_sp(0xFFFE)

    # The LCD has to be off before VRAM can be written from code that is not
    # timing its accesses, and it can only be turned off during vblank.
    a.label("waitvbl")
    a.ldh_from(R_LY)
    a.cp(0x90)
    a.jr_nz("waitvbl")
    a.xor_a()
    a.ldh_to(R_LCDC)

    # One blank tile, and a map that is nothing but that tile: every pixel on
    # screen is colour 0, so BGP's bottom two bits paint the whole picture.
    a.ld_hl(0x8000)
    a.ld_b(16)
    a.label("clrtile")
    a.xor_a()
    a.ld_hli_a()
    a.dec_b()
    a.jr_nz("clrtile")

    a.ld_hl(0x9800)
    a.ld_bc(0x0400)
    a.label("clrmap")
    a.xor_a()
    a.ld_hli_a()
    a.dec_bc()
    a.ld_a_b()
    a.or_c()
    a.jr_nz("clrmap")

    _shade(a, fast, BLACK)    # nothing has crossed yet
    a.ld_a(0x91)              # LCD on, BG on, tiles at 0x8000, map at 0x9800
    a.ldh_to(R_LCDC)

    mine = 0xA5 if master else 0x5A
    theirs = 0x5A if master else 0xA5

    a.label("loop")
    if master:
        # About 27 ms between bytes, which is a slow Game Boy game and a hundred
        # times the frontend's rendezvous horizon. Fast enough that a three
        # second probe sees dozens of exchanges.
        a.ld_bc(0x0400 if fast else 0x1000)
        a.label("delay")
        a.dec_bc()
        a.ld_a_b()
        a.or_c()
        a.jr_nz("delay")

    a.ld_a(mine)
    a.ldh_to(R_SB)
    # SC: bit 7 starts a transfer, bit 0 says this unit drives the clock, and
    # bit 1 picks the Game Boy Color's 262144 Hz rate over the Game Boy's 8192.
    sc = 0x81 if master else 0x80
    if fast:
        sc |= 0x02
    a.ld_a(sc)
    a.ldh_to(R_SC)

    # Poll the start bit rather than taking the interrupt: interrupts are off,
    # and a machine that is waiting to be clocked has nothing else to do anyway.
    a.label("wait")
    a.ldh_from(R_SC)
    a.and_(0x80)
    a.jr_nz("wait")

    a.ldh_from(R_SB)
    a.cp(theirs)
    a.jr_nz("bad")
    _shade(a, fast, WHITE)
    a.jr("loop")

    a.label("bad")
    _shade(a, fast, GREY)
    a.jr("loop")

    code = a.resolve()

    rom = bytearray(0x8000)
    rom[0x100:0x104] = bytes([0x00, 0xC3, 0x50, 0x01])   # nop; jp 0x150

    # The four bytes a loader matches to decide this file is a Game Boy ROM.
    #
    # They are the first four of the header logo, and they are the whole of what
    # mGBA's GBIsROM compares -- a file without them is not offered to the Game
    # Boy core at all, whatever its extension. The other forty-four are the
    # artwork and are left as zeros: nothing reads them but a real boot ROM, and
    # the probes turn that off.
    rom[0x104:0x108] = bytes([0xCE, 0xED, 0x66, 0x66])
    title = ("GBLINK " + ("MASTER" if master else "SLAVE")).ljust(16, "\0")[:16]
    rom[0x134:0x144] = title.encode("ascii")
    if fast:
        rom[0x143] = 0x80    # runs on a Game Boy Color, and on a Game Boy too
    rom[0x147] = 0x00        # ROM only
    rom[0x148] = 0x00        # 32 KiB
    rom[0x149] = 0x00        # no cartridge RAM
    rom[0x14B] = 0x33        # new licensee scheme

    checksum = 0
    for i in range(0x134, 0x14D):
        checksum = (checksum - rom[i] - 1) & 0xFF
    rom[0x14D] = checksum

    rom[0x150:0x150 + len(code)] = code
    return bytes(rom)


## The three shades, as a Game Boy sees them and as a Game Boy Color does.
##
## A DMG paints colour 0 through BGP's bottom two bits; a Game Boy Color ignores
## BGP entirely and takes the colour out of its own palette memory, so a ROM that
## runs on one has to say it twice or come up black on the other.
BLACK = (0xFF, 0x0000)
GREY = (0xAA, 0x39CE)
WHITE = (0x00, 0x7FFF)


def _shade(a, fast, shade):
    bgp, bgr15 = shade
    a.ld_a(bgp)
    a.ldh_to(R_BGP)
    if not fast:
        return
    a.ld_a(0x80)             # BCPS: index 0, auto-increment
    a.ldh_to(R_BCPS)
    a.ld_a(bgr15 & 0xFF)
    a.ldh_to(R_BCPD)
    a.ld_a(bgr15 >> 8)
    a.ldh_to(R_BCPD)


# ---------------------------------------------------------------------------
# The printer ROM
# ---------------------------------------------------------------------------
#
# printer.gb prints one known picture to a Game Boy Printer and checks every
# byte the printer said back. The bytes it sends are built here as one stream --
# INIT, nine DATA packets (the odd ones RLE-compressed), the empty DATA that
# closes the buffer, and PRINT -- and so are the replies a printer has to give:
# 0x81 for the first of each packet's two trailing bytes, its status for the
# second, 0x00 for everything else. The ROM first finds the printer the way the
# games do (status packets until one is answered 0x81), sends the stream a byte
# at a time, logs what came back, compares the log with the expected replies,
# then polls status until the printer reports 0x04 (done).
#
# Screen: black while it runs, WHITE when every reply was right and the print
# finished, GREY otherwise. With nothing on the cable no printer is ever found,
# so the control leg stays black and prints nothing.
#
# printer_expected.png is the paper the print must come out as: the picture
# with the 0x13 margins (one unit above, three below) in the printer core's
# greys, row for row.

PRINT_LINES = 144
PRINT_MARGINS = 0x13
MARGIN_LINES = 16          # gbprinter-libretro's GBP_MARGIN_LINES
GREYS = (255, 170, 85, 0)  # palette 0xE4 at exposure 0x40, the core's shade_grey

STREAM_AT = 0x1000         # where the stream lives in ROM
LOG_AT = 0xC000            # where the replies are logged, in WRAM
LOG_MAX = 0x1F00           # leaves the top of WRAM to the stack and verdict
VERDICT_AT = 0xDFF0
ACK_AT = 0xDFF1


def printer_colour(x, y):
    """The picture: asymmetric on both axes, so a flip or transpose shows."""
    if x < 24 and y < 6:
        return 3
    if x == 3:
        return 2
    if 100 <= x < 140 and 60 <= y < 70:
        return 1
    return ((x + 2 * y) // 5) & 3


def _tiles(lines):
    out = bytearray()
    for row in range(lines // 8):
        for tile in range(20):
            for line in range(8):
                lo = hi = 0
                for x in range(8):
                    c = printer_colour(tile * 8 + x, row * 8 + line)
                    lo |= (c & 1) << (7 - x)
                    hi |= ((c >> 1) & 1) << (7 - x)
                out += bytes((lo, hi))
    return bytes(out)


def _rle(data):
    """The printer's RLE: 0x80|n runs n+2 copies of the next byte, n alone is
    n+1 literal bytes."""
    out = bytearray()
    i = 0
    while i < len(data):
        run = 1
        while i + run < len(data) and data[i + run] == data[i] and run < 129:
            run += 1
        if run >= 2:
            out += bytes((0x80 | (run - 2), data[i]))
            i += run
        else:
            start = i
            while i < len(data) and i - start < 128:
                if i + 1 < len(data) and data[i + 1] == data[i]:
                    break
                i += 1
            out.append(i - start - 1)
            out += data[start:i]
    return bytes(out)


def printer_stream():
    """(bytes to send, replies expected) for the whole print."""
    send = bytearray()
    want = bytearray()

    def packet(cmd, body=b"", comp=0, status=0x00):
        n = len(body)
        head = bytes((cmd, comp, n & 0xFF, n >> 8))
        total = (sum(head) + sum(body)) & 0xFFFF
        pkt = b"\x88\x33" + head + body + bytes((total & 0xFF, total >> 8, 0, 0))
        send.extend(pkt)
        want.extend(bytes(len(pkt) - 2) + bytes((0x81, status)))

    packet(0x01)
    tiles = _tiles(PRINT_LINES)
    for k in range(0, len(tiles), 0x280):
        chunk = tiles[k:k + 0x280]
        if (k // 0x280) % 2:
            packet(0x04, _rle(chunk), comp=1, status=0x08)
        else:
            packet(0x04, chunk, status=0x08)
    packet(0x04, status=0x08)
    packet(0x02, bytes((1, PRINT_MARGINS, 0xE4, 0x40)), status=0x08)
    return bytes(send), bytes(want)


def build_printer():
    send, want = printer_stream()
    if len(send) > LOG_MAX:
        raise ValueError("stream too long for the reply log")
    want_at = STREAM_AT + len(send)
    poll = bytes((0x88, 0x33, 0x0F, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00))
    poll_at = want_at + len(want)

    a = Asm(0x150)
    a.di()
    a.ld_sp(0xFFFE)

    a.label("waitvbl")
    a.ldh_from(R_LY)
    a.cp(0x90)
    a.jr_nz("waitvbl")
    a.xor_a()
    a.ldh_to(R_LCDC)
    a.ld_hl(0x8000)
    a.ld_b(16)
    a.label("clrtile")
    a.xor_a()
    a.ld_hli_a()
    a.dec_b()
    a.jr_nz("clrtile")
    a.ld_hl(0x9800)
    a.ld_bc(0x0400)
    a.label("clrmap")
    a.xor_a()
    a.ld_hli_a()
    a.dec_bc()
    a.ld_a_b()
    a.or_c()
    a.jr_nz("clrmap")
    _shade(a, False, BLACK)
    a.ld_a(0x91)
    a.ldh_to(R_LCDC)

    # Find the printer first, as the games do: send a status packet until the
    # first trailing byte comes back 0x81. With nothing on the cable it never
    # does, and the screen stays black for ever -- which is the control.
    a.label("detect")
    a.call("status")
    a.ld_a_mem(ACK_AT)
    a.cp(0x81)
    a.jr_z("found")
    a.ld_bc(0x2000)
    a.label("detectwait")
    a.dec_bc()
    a.ld_a_b()
    a.or_c()
    a.jr_nz("detectwait")
    a.jr("detect")
    a.label("found")

    # Send the stream, logging every reply.
    a.ld_hl(STREAM_AT)
    a.ld_de(LOG_AT)
    a.ld_bc(len(send))
    a.label("stream")
    a.ld_a_hli()
    a.call("xfer")
    a.ld_de_a()
    a.inc_de()
    a.dec_bc()
    a.ld_a_b()
    a.or_c()
    a.jr_nz("stream")

    # Compare the log with what a printer must have said.
    a.xor_a()
    a.ld_mem_a(VERDICT_AT)
    a.ld_hl(want_at)
    a.ld_de(LOG_AT)
    a.ld_bc(len(want))
    a.label("check")
    a.ld_a_de()
    a.cp_hl()
    a.jr_z("same")
    a.ld_a(1)
    a.ld_mem_a(VERDICT_AT)
    a.label("same")
    a.inc_hl()
    a.inc_de()
    a.dec_bc()
    a.ld_a_b()
    a.or_c()
    a.jr_nz("check")

    # Poll status until the print is done (0x04), or give up.
    a.ld_de(0x0800)
    a.label("poll")
    a.call("status")
    a.cp(0x04)
    a.jr_z("printed")
    a.dec_de()
    a.ld_a_d()
    a.or_e()
    a.jr_nz("poll")
    a.jr("bad")

    a.label("printed")
    a.ld_a_mem(VERDICT_AT)
    a.cp(0x00)
    a.jr_nz("bad")
    _shade(a, False, WHITE)
    a.label("halt")
    a.jr("halt")
    a.label("bad")
    _shade(a, False, GREY)
    a.label("halt2")
    a.jr("halt2")

    # A status packet: the eight bytes of header and checksum, then the two
    # trailing bytes. The first's reply goes to ACK_AT, the second's is left in
    # A. HL and C are used.
    a.label("status")
    a.ld_hl(poll_at)
    a.ld_c(8)
    a.label("statusbyte")
    a.ld_a_hli()
    a.call("xfer")
    a.dec_c()
    a.jr_nz("statusbyte")
    a.xor_a()
    a.call("xfer")
    a.ld_mem_a(ACK_AT)
    a.xor_a()
    a.call("xfer")
    a.ret()

    # One byte out, one byte back, then a short pause as a game's send loop
    # leaves between bytes. A in, A out; BC kept.
    a.label("xfer")
    a.ldh_to(R_SB)
    a.ld_a(0x81)
    a.ldh_to(R_SC)
    a.label("xwait")
    a.ldh_from(R_SC)
    a.and_(0x80)
    a.jr_nz("xwait")
    a.ldh_from(R_SB)
    a.push_bc()
    a.ld_b(24)
    a.label("xpause")
    a.dec_b()
    a.jr_nz("xpause")
    a.pop_bc()
    a.ret()

    code = a.resolve()
    if 0x150 + len(code) > STREAM_AT:
        raise ValueError("code runs into the stream")

    rom = bytearray(0x8000)
    rom[0x100:0x104] = bytes([0x00, 0xC3, 0x50, 0x01])
    rom[0x104:0x108] = bytes([0xCE, 0xED, 0x66, 0x66])
    rom[0x134:0x144] = "GBLINK PRINTER".ljust(16, "\0").encode("ascii")
    rom[0x147] = 0x00
    rom[0x148] = 0x00
    rom[0x149] = 0x00
    rom[0x14B] = 0x33
    checksum = 0
    for i in range(0x134, 0x14D):
        checksum = (checksum - rom[i] - 1) & 0xFF
    rom[0x14D] = checksum
    rom[0x150:0x150 + len(code)] = code
    end = poll_at + len(poll)
    if end > len(rom):
        raise ValueError("stream does not fit in 32 KiB")
    rom[STREAM_AT:want_at] = send
    rom[want_at:poll_at] = want
    rom[poll_at:end] = poll
    return bytes(rom)


def printer_expected_png():
    """The paper, as an 8-bit greyscale PNG."""
    import struct
    import zlib
    before = (PRINT_MARGINS >> 4) * MARGIN_LINES
    after = (PRINT_MARGINS & 0x0F) * MARGIN_LINES
    rows = [bytes([255] * 160)] * before
    for y in range(PRINT_LINES):
        rows.append(bytes(GREYS[printer_colour(x, y)] for x in range(160)))
    rows += [bytes([255] * 160)] * after
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", 160, len(rows), 8, 0, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(os.path.dirname(here), "RetroXR", "Tools", "gblink")
    os.makedirs(out, exist_ok=True)
    for fast in (False, True):
        for master in (True, False):
            rom = build(master, fast)
            name = "link_%s%s.%s" % ("master" if master else "slave",
                                     "_fast" if fast else "", "gbc" if fast else "gb")
            path = os.path.join(out, name)
            with open(path, "wb") as fh:
                fh.write(rom)
            print("wrote %s (%d bytes)" % (path, len(rom)))
    for name, data in (("printer.gb", build_printer()),
                       ("printer_expected.png", printer_expected_png())):
        path = os.path.join(out, name)
        with open(path, "wb") as fh:
            fh.write(data)
        print("wrote %s (%d bytes)" % (path, len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
