// Stereoscopic 3DS homebrew test for the azahar render_3d patch.
//
// Enables the 3DS's stereoscopic 3D and paints the LEFT eye red and the RIGHT
// eye blue (distinct solid colors), plus the bottom screen green. When azahar
// runs with citra_render_3d = "side-by-side", the top-screen output frame ends
// up as [ left-eye | right-eye ] = [ red | blue ], which a per-eye VR shader
// samples by half. The RetroXR probe just asserts the two halves differ.
#include <3ds.h>

static void fill(u8* fb, int px, u8 b, u8 g, u8 r) {
    for (int i = 0; i < px; i++) { fb[i*3+0] = b; fb[i*3+1] = g; fb[i*3+2] = r; }
}

int main(int argc, char** argv) {
    gfxInitDefault();
    gfxSet3D(true); // stereoscopic 3D on

    while (aptMainLoop()) {
        u16 w, h;
        // Framebuffers are GSP_BGR8_OES (3 bytes/px). With 3D on the top screen
        // exposes separate GFX_LEFT and GFX_RIGHT buffers.
        u8* left  = gfxGetFramebuffer(GFX_TOP, GFX_LEFT,  &w, &h);
        u8* right = gfxGetFramebuffer(GFX_TOP, GFX_RIGHT, &w, &h);
        fill(left,  w * h, 0,   0,   255); // left eye  -> red   (R=255)
        fill(right, w * h, 255, 0,   0);   // right eye -> blue  (B=255)

        u16 bw, bh;
        u8* bot = gfxGetFramebuffer(GFX_BOTTOM, GFX_LEFT, &bw, &bh);
        fill(bot, bw * bh, 0, 255, 0);     // bottom -> green

        gfxFlushBuffers();
        gfxSwapBuffers();
        gspWaitForVBlank();

        hidScanInput();
        if (hidKeysDown() & KEY_START) break;
    }
    gfxExit();
    return 0;
}
