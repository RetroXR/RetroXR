#!/usr/bin/env python3
"""Film the welcome page's upload clip: a ROM uploaded through the Web File Manager.

    "$godot" --headless --path RetroXR res://Tools/net/web_upload_probe.tscn -- --scratch=<dir> &
    python Tools/art/film_web_upload.py --scratch <dir> --rom RetroXR/Tools/room/roms/brix.nes
    python Tools/art/encode_welcome_clip.py <dir>/frames --name upload_clip

web_upload_probe serves a SCRATCH data folder with the real WebFileServer (PIN 1234);
this drives Chromium (Playwright) through it the way a player does, with a cursor
and captions drawn over the page because a recording shows neither: the address,
the PIN, media > roms > nes, "choose files", the upload, the file in the list. It
checks the file reached the scratch folder, writes the film as <scratch>/frames/
f_00000.png ... at 30 fps, then writes <scratch>/stop so the server quits.

The frames are Chromium's own screencast, not Playwright's recorder, whose lossy VP8
would soften the page's small text before Theora softened it again. The
screencast sends a lossless PNG, stamped with its time, whenever the page
repaints; they are laid on a 30 fps timeline here, each held until the next.

Needs `python -m pip install playwright` and `python -m playwright install chromium`.
"""

import argparse
import base64
import os
import shutil
import sys
import time

from playwright.sync_api import sync_playwright

# The page is laid out at 960 x 540, a phone's width more than a desktop's, so the
# welcome page, which shows the clip 1280 wide, draws its 14 px text a third larger
# than a desktop browser would. Filmed at that size: the screencast's frames are
# CSS pixels whatever the device scale, so a larger scale only resamples.
SIZE = {"width": 960, "height": 540}
FPS = 30
PIN = "1234"

# A cursor and a caption bar, drawn by the page itself: a recording has neither.
OVERLAY = """
(() => {
  const add = () => {
    if (document.getElementById('__cur')) return;
    const c = document.createElement('div');
    c.id = '__cur';
    c.style.cssText = 'position:fixed;left:480px;top:450px;width:18px;height:18px;margin:-9px 0 0 -9px;'
      + 'border-radius:50%;background:#5ef2ff;border:2px solid rgba(0,0,0,.6);z-index:99999;pointer-events:none;'
      + 'transition:transform .15s';
    document.body.appendChild(c);
    const b = document.createElement('div');
    b.id = '__cap';
    b.style.cssText = 'position:fixed;left:50%;bottom:16px;transform:translateX(-50%);padding:8px 18px;'
      + 'background:rgba(10,10,25,.82);color:#f2f2ff;font:600 20px system-ui,sans-serif;border-radius:8px;'
      + 'z-index:99998;pointer-events:none;white-space:nowrap';
    b.textContent = window.__capText || '';
    b.style.display = b.textContent ? 'block' : 'none';
    document.body.appendChild(b);
    const a = document.createElement('div');
    a.id = '__addr';
    a.style.cssText = 'position:fixed;left:0;right:0;top:0;height:28px;background:#2b2b33;color:#ddd;'
      + 'font:14px system-ui,sans-serif;display:flex;align-items:center;padding-left:12px;z-index:99997;'
      + 'pointer-events:none;border-bottom:1px solid #000';
    a.textContent = '\\u{1F512}  ' + location.origin + '/';
    document.body.appendChild(a);
    document.body.style.paddingTop = '34px';
  };
  document.addEventListener('mousemove', e => {
    const c = document.getElementById('__cur');
    if (c) { c.style.left = e.clientX + 'px'; c.style.top = e.clientY + 'px'; }
  }, true);
  document.addEventListener('mousedown', () => {
    const c = document.getElementById('__cur'); if (c) c.style.transform = 'scale(.7)';
  }, true);
  document.addEventListener('mouseup', () => {
    const c = document.getElementById('__cur'); if (c) c.style.transform = 'scale(1)';
  }, true);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add); else add();
})();
"""


class Screencast:
    """Chromium's screencast: a PNG per repaint, kept with its swap time."""

    def __init__(self, ctx, page):
        self.frames: list[tuple[float, bytes]] = []
        self.cdp = ctx.new_cdp_session(page)
        self.cdp.on("Page.screencastFrame", self._frame)
        self.cdp.send("Page.startScreencast", {"format": "png", "everyNthFrame": 1,
                                               "maxWidth": SIZE["width"], "maxHeight": SIZE["height"]})

    def _frame(self, params):
        # Acked at once: Chromium sends no further frame until it is.
        self.cdp.send("Page.screencastFrameAck", {"sessionId": params["sessionId"]})
        self.frames.append((float(params["metadata"]["timestamp"]), base64.b64decode(params["data"])))

    def stop(self):
        self.cdp.send("Page.stopScreencast")

    def write(self, out_dir, until: float) -> int:
        """Lays the frames on a FPS timeline up to `until` (epoch seconds), each held
        until the next, as f_00000.png ... Returns how many were written."""
        shutil.rmtree(out_dir, ignore_errors=True)
        os.makedirs(out_dir)
        frames = sorted(self.frames, key=lambda f: f[0])
        if not frames:
            return 0
        t0 = frames[0][0]
        count = int((until - t0) * FPS) + 1
        k = 0
        for i in range(count):
            t = t0 + i / FPS
            while k + 1 < len(frames) and frames[k + 1][0] <= t:
                k += 1
            with open(os.path.join(out_dir, "f_%05d.png" % i), "wb") as f:
                f.write(frames[k][1])
        return count


class Film:
    """Moves and clicks as a hand would, waiting through Playwright so the
    screencast's frames keep being received while nothing is said."""

    def __init__(self, page):
        self.page = page
        self.x, self.y = 480.0, 450.0

    def say(self, text):
        print(f"[webfilm] {text}")
        self.page.evaluate("""t => { window.__capText = t; const b = document.getElementById('__cap');
            if (b) { b.textContent = t; b.style.display = t ? 'block' : 'none'; } }""", text)

    def move_to(self, selector, seconds=0.8):
        box = self.page.locator(selector).first.bounding_box()
        if box is None:
            raise RuntimeError(f"nothing at {selector}")
        tx, ty = box["x"] + min(box["width"] / 2, 60), box["y"] + box["height"] / 2
        steps = max(1, int(seconds * FPS))
        for i in range(1, steps + 1):
            k = i / steps
            k = k * k * (3 - 2 * k)
            self.page.mouse.move(self.x + (tx - self.x) * k, self.y + (ty - self.y) * k)
            self.hold(1 / FPS)
        self.x, self.y = tx, ty

    def press(self):
        self.page.mouse.down()
        self.hold(0.12)
        self.page.mouse.up()

    def click(self, selector, seconds=0.8):
        self.move_to(selector, seconds)
        self.hold(0.2)
        self.press()

    def hold(self, seconds):
        self.page.wait_for_timeout(seconds * 1000)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scratch", required=True)
    ap.add_argument("--rom", required=True)
    ap.add_argument("--url", default="http://localhost:8080")
    args = ap.parse_args()
    rom = os.path.abspath(args.rom)
    ok = False
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        ctx = browser.new_context(viewport=SIZE)
        ctx.add_init_script(OVERLAY)
        page = ctx.new_page()
        film = Film(page)
        cast = None
        try:
            page.goto(args.url)
            page.wait_for_selector("#pin")
            film.say("1  OPTIONS > File Server: switch on the Web File Manager, open its address")
            cast = Screencast(ctx, page)
            film.hold(2.4)
            film.say("2  Type the PIN shown under the address")
            film.click("#pin", 0.9)
            page.keyboard.type(PIN, delay=320)
            film.hold(0.4)
            film.click("button[type=submit]", 0.7)
            page.wait_for_selector('[data-nav="media"]')
            film.hold(1.0)
            film.say("3  media > roms > the game's system")
            film.click('[data-nav="media"]', 0.9)
            page.wait_for_selector('[data-nav="media/roms"]')
            film.hold(0.9)
            film.click('[data-nav="media/roms"]', 0.9)
            page.wait_for_selector('[data-nav="media/roms/nes"]')
            film.hold(0.9)
            film.click('[data-nav="media/roms/nes"]', 0.9)
            # Inside a folder the list always has its ".." row, which points back up.
            page.wait_for_selector('td.nm.dn[data-nav="media/roms"]')
            film.hold(1.0)
            film.say("4  choose files, or drop them on the page")
            film.move_to("label.pk >> nth=0", 0.9)
            film.hold(0.3)
            with page.expect_file_chooser() as chooser:
                film.press()
            chooser.value.set_files(rom)
            name = os.path.basename(rom)
            page.wait_for_selector(f"td.nm:has-text('{name}')", timeout=30000)
            film.say("5  Done: open its system under SPAWN to play it")
            film.hold(3.0)
            landed = os.path.join(args.scratch, "data", "roms", "nes", name)
            ok = os.path.exists(landed) and os.path.getsize(landed) == os.path.getsize(rom)
            print(f"[webfilm] uploaded to the scratch folder: {ok} ({landed})")
        finally:
            end = time.time()
            if cast is not None:
                cast.stop()
                out = os.path.join(args.scratch, "frames")
                n = cast.write(out, end)
                print(f"[webfilm] {len(cast.frames)} repaints -> {n} frames ({n / FPS:.1f} s) in {out}")
                if n == 0:
                    ok = False
            ctx.close()
            browser.close()
            open(os.path.join(args.scratch, "stop"), "w").close()
    print("[webfilm] PASS" if ok else "[webfilm] FAIL the file never reached the scratch folder, or nothing was filmed")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
