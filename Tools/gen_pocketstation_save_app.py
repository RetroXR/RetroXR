"""Make a PocketStation app that SAVES, and the game save it saves into: the fixture for
proving a PocketStation run's writes reach the card (Tools/cores/pocketstation_play_probe).

    python Tools/gen_pocketstation_save_app.py <out dir>

Writes <out>/rxr_save_test.mcs (a one-block app, MCX0) and <out>/rxr_game_save.mcs (a
one-block PS1 game save). Put on a blank card in that order (the probe's --saves=), the app
is block 1 and the game save block 2. Started from the PocketStation's menu, the app:

    fills RAM 0x400..0x47F with i ^ 0x5A
    calls the kernel's flash frame write (SWI 0x10, r0 = frame, r1 = buffer) up to ten times
        until it returns 0, at frame 2*64 + 8 = the game save's data at block offset 0x400:
        the way a real app writes its game's save (Pokket docs/app-notes.md, "The write path")
    paints the top half of the LCD black when the write succeeded, the bottom half when it
        did not, and waits

Everything here is written from the Title Sector layout in Pokket's docs/app-notes.md; no
byte of another app is used. The ARM code is assembled by the few encoders below.
"""
import os
import struct
import sys

GAME_BLOCK = 2
FRAME = GAME_BLOCK * 64 + 8
PATTERN = bytes((i ^ 0x5A) for i in range(128))
ENTRY = 0x02000300
APP_NAME = "BAPKTMPRXRSAVETEST01"   # byte 6 must be 'P' for the BIOS to list it
GAME_NAME = "BISLPS-99999GAMESAVE"

MOV, MVN, ADD, SUB, EOR, ORR, CMP = 0xD, 0xF, 0x4, 0x2, 0x1, 0xC, 0xA


def dp_imm(op, s, rn, rd, value):
    """A data-processing instruction with an immediate, as imm8 ROR 2*rot."""
    for rot in range(16):
        sh = 2 * rot
        imm = ((value << sh) | (value >> (32 - sh))) & 0xFFFFFFFF if sh else value
        if imm < 0x100:
            return 0xE2000000 | (op << 21) | (s << 20) | (rn << 16) | (rd << 12) | (rot << 8) | imm
    raise ValueError("immediate %#x not encodable" % value)


class Asm:
    def __init__(self):
        self.code, self.labels, self.fixups = [], {}, []

    def label(self, name):
        self.labels[name] = len(self.code)

    def w(self, word):
        self.code.append(word)

    def b(self, cond, name):
        self.fixups.append((len(self.code), cond, name))
        self.code.append(0)

    def assemble(self):
        for at, cond, name in self.fixups:
            self.code[at] = (cond << 28) | 0x0A000000 | ((self.labels[name] - (at + 2)) & 0xFFFFFF)
        return b"".join(struct.pack("<I", x) for x in self.code)


def routine():
    a = Asm()
    a.w(dp_imm(MOV, 0, 0, 2, 0x400))              # mov r2, #0x400
    a.w(dp_imm(MOV, 0, 0, 3, 0))                  # mov r3, #0
    a.label("fill")
    a.w(dp_imm(EOR, 0, 3, 4, 0x5A))               # eor r4, r3, #0x5A
    a.w(0xE7C00000 | (2 << 16) | (4 << 12) | 3)   # strb r4, [r2, r3]
    a.w(dp_imm(ADD, 0, 3, 3, 1))                  # add r3, r3, #1
    a.w(dp_imm(CMP, 1, 3, 0, 0x80))               # cmp r3, #0x80
    a.b(0x1, "fill")                              # bne fill
    a.w(dp_imm(MOV, 0, 0, 6, 10))                 # mov r6, #10
    a.label("try")
    a.w(dp_imm(MOV, 0, 0, 0, FRAME))              # mov r0, #FRAME
    a.w(0xE1A01002)                               # mov r1, r2
    a.w(0xEF000010)                               # svc #0x10
    a.w(dp_imm(CMP, 1, 0, 0, 0))                  # cmp r0, #0
    a.b(0x0, "ok")                                # beq ok
    a.w(dp_imm(SUB, 1, 6, 6, 1))                  # subs r6, r6, #1
    a.b(0x1, "try")                               # bne try
    a.w(dp_imm(MOV, 0, 0, 9, 16))                 # mov r9, #16: failed, bottom half
    a.b(0xE, "draw")
    a.label("ok")
    a.w(dp_imm(MOV, 0, 0, 9, 0))                  # mov r9, #0: saved, top half
    a.label("draw")
    a.w(dp_imm(MOV, 0, 0, 7, 0x0D000000))         # mov r7, #LCD_MODE
    a.w(0xE5900000 | (7 << 16) | (8 << 12))       # ldr r8, [r7]
    a.w(dp_imm(ORR, 0, 8, 8, 0x40))               # orr r8, r8, #0x40: display on
    a.w(0xE5800000 | (7 << 16) | (8 << 12))       # str r8, [r7]
    a.w(dp_imm(ADD, 0, 7, 7, 0x100))              # add r7, r7, #0x100: VRAM
    a.w(dp_imm(MVN, 0, 0, 8, 0))                  # mvn r8, #0
    a.w(dp_imm(MOV, 0, 0, 10, 16))                # mov r10, #16
    a.label("row")
    a.w(0xE7800000 | (7 << 16) | (8 << 12) | (2 << 7) | 9)   # str r8, [r7, r9, lsl #2]
    a.w(dp_imm(ADD, 0, 9, 9, 1))                  # add r9, r9, #1
    a.w(dp_imm(SUB, 1, 10, 10, 1))                # subs r10, r10, #1
    a.b(0x1, "row")                               # bne row
    a.label("hang")
    a.b(0xE, "hang")                              # b hang
    return a.assemble()


def sjis_fullwidth(text):
    out = bytearray()
    for ch in text:
        if ch == " ":
            out += b"\x81\x40"
        elif "A" <= ch <= "Z":
            out += bytes([0x82, 0x60 + ord(ch) - ord("A")])
        elif "0" <= ch <= "9":
            out += bytes([0x82, 0x4F + ord(ch) - ord("0")])
    return bytes(out)


def app_body():
    body = bytearray(0x2000)
    body[0:2] = b"SC"
    body[2] = 0x11                     # one icon frame, no animation
    body[3] = 1                        # blocks: the BIOS's browse screen reads it
    title = sjis_fullwidth("RXR SAVE TEST")
    body[4:4 + len(title)] = title
    body[0x52:0x56] = b"MCX0"
    body[0x56] = 1                     # 1 in every real app (pk_timing_bench header.s)
    struct.pack_into("<I", body, 0x5C, ENTRY)        # ARM entry, bit 0 clear
    # The browse screen's icon: a flags word, a FLASH1 pointer, a 32x32 1bpp bitmap.
    struct.pack_into("<I", body, 0x100, 0x00010001)
    struct.pack_into("<I", body, 0x104, 0x02000180)
    for row in range(32):
        bits = 0xFFFFFFFF if row in (0, 31) else 0x80000001
        if 12 <= row <= 19:
            bits |= 0x0FF00FF0                        # two bars: a "saved" mark
        struct.pack_into("<I", body, 0x180 + row * 4, bits)
    code = routine()
    at = ENTRY - 0x02000000
    body[at:at + len(code)] = code
    return bytes(body)


def dir_frame(name, size):
    f = bytearray(0x80)
    f[0] = 0x51
    struct.pack_into("<I", f, 4, size)
    struct.pack_into("<H", f, 8, 0xFFFF)
    raw = name.encode("ascii")
    f[0x0A:0x0A + len(raw)] = raw
    x = 0
    for b in f[:0x7F]:
        x ^= b
    f[0x7F] = x
    return bytes(f)


def game_body():
    body = bytearray(0x2000)
    body[0:2] = b"SC"
    body[2] = 0x11
    body[3] = 1
    title = sjis_fullwidth("RXR GAME SAVE")
    body[4:4 + len(title)] = title
    return bytes(body)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "rxr_save_test.mcs"), "wb") as f:
        f.write(dir_frame(APP_NAME, 0x2000) + app_body())
    with open(os.path.join(out, "rxr_game_save.mcs"), "wb") as f:
        f.write(dir_frame(GAME_NAME, 0x2000) + game_body())
    print("wrote %s: the app writes frame %d (block %d +0x400), pattern %s..."
          % (out, FRAME, GAME_BLOCK, PATTERN[:8].hex()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
