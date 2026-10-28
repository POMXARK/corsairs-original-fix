/* Draws the FPS counter, the messages and the frame-time graph inside the game, with the debug font of ENGINE.exe (original Sea Dogs, 2000).
 *
 * The frame of the game is: the core draws the scene, then FUN_0040a2a0 flips the screen (Realize_Layers, 0x4205c0).
 * capture.ps1 puts this code into the process of the game and points the call at 0x420c0a to hook(): it prints the two
 * strings that capture.ps1 keeps in the data page, draws the graph into the back buffer and goes on to the flip. No imports
 * and no relocations: every address is a constant, the engine does not move (base 0x400000), the cave is placed at a fixed address.
 *
 * data page (0x7E000000): int fps_x, fps_y, msg_x, msg_y; char fps[48] at +0x10; char msg[60] at +0x40; int frames at +0x7C;
 *   an empty string draws nothing.
 *   +0x80 graph on (0/1), +0x84 graph x, +0x88 graph y (pixels)
 *   +0x8C TSC cycles per millisecond (the hook measures it against GetTickCount in the first second), +0x90 ring index,
 *   +0x94 TSC of the last frame, +0x98 TSC and +0x9C tick at the start of the calibration
 *   +0x100 unsigned short ring[256]: the frame times in tenths of a millisecond
 * Build: ./build_overlay.sh  ->  overlay.bin (the code, loaded at 0x7E001000).
 */
typedef void (__attribute__((cdecl)) *TextFn)(void *font, int x, int y, const char *text);
typedef void (__attribute__((fastcall)) *FlipFn)(void *dev);
typedef unsigned (__attribute__((thiscall)) *LockFn)(void *dev, int *pitch);   /* FUN_0040b4e0: the pixels of the back buffer, 0 if locked */
typedef void (__attribute__((fastcall)) *UnlockFn)(void *dev);                  /* FUN_0040b540 */
typedef unsigned (__attribute__((stdcall)) *TickFn)(void);

#define DATA ((volatile int *)0x7E000000)
#define RING ((volatile unsigned short *)0x7E000100)
#define BARS 240                 /* frames in the graph, 2 pixels each */
#define GRAPH_H 120              /* 3 pixels per millisecond: 40 ms at the top */

static void fill(unsigned short *base, int pitch, int sw, int sh, int x, int y, int w, int h, unsigned short c)
{
    int i, j;
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > sw) w = sw - x;
    if (y + h > sh) h = sh - y;
    for (j = 0; j < h; j++) {
        unsigned short *row = (unsigned short *)((char *)base + (y + j) * pitch) + x;
        for (i = 0; i < w; i++) row[i] = c;
    }
}

static unsigned short rgb(int f565, int r, int g, int b)
{
    if (f565) return (unsigned short)(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
    return (unsigned short)(((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3));
}

__attribute__((fastcall)) void hook(void *dev)
{
    volatile unsigned text_addr = 0x40E860;   /* FUN_0040e860(font, x, y, format, ...): the debug text of the engine */
    volatile unsigned flip_addr = 0x40A2A0;   /* FUN_0040a2a0: the end of the frame, the flip */
    volatile unsigned font_addr = 0x7C77A8;   /* DAT_007c77a8: the font object */
    volatile unsigned lock_addr = 0x40B4E0;
    volatile unsigned unlock_addr = 0x40B540;
    volatile unsigned tick_iat = 0x431050;    /* the import GetTickCount of ENGINE.exe */
    const char *fps = (const char *)(DATA + 4);
    const char *msg = (const char *)(DATA + 16);
    TextFn text = (TextFn)text_addr;
    unsigned now = __builtin_ia32_rdtsc();
    unsigned last = (unsigned)DATA[0x94 / 4];
    unsigned cpm = (unsigned)DATA[0x8C / 4];

    DATA[31] = DATA[31] + 1;                  /* how many frames came here: capture.ps1 logs it */
    DATA[0x94 / 4] = (int)now;
    if (cpm < 10) {                           /* the first second: cycles per millisecond */
        unsigned tick = (*(TickFn *)tick_iat)();
        if (!DATA[0x9C / 4]) { DATA[0x98 / 4] = (int)now; DATA[0x9C / 4] = (int)tick; }
        else if (tick - (unsigned)DATA[0x9C / 4] >= 1000)
            DATA[0x8C / 4] = (int)(((unsigned)(now - (unsigned)DATA[0x98 / 4])) / (tick - (unsigned)DATA[0x9C / 4]));
    } else {
        unsigned ms10 = (now - last) / (cpm / 10);
        unsigned idx = (unsigned)DATA[0x90 / 4];
        if (ms10 > 9999) ms10 = 9999;
        RING[idx & 255] = (unsigned short)ms10;
        DATA[0x90 / 4] = (int)(idx + 1);
    }

    if (*fps) text((void *)font_addr, DATA[0], DATA[1], fps);
    if (*msg) text((void *)font_addr, DATA[2], DATA[3], msg);

    if (DATA[0x80 / 4] && cpm >= 10) {
        int pitch = 0;
        unsigned short *base = (unsigned short *)((LockFn)lock_addr)(dev, &pitch);
        if (base && pitch > 0) {
            int sw = *(volatile int *)((char *)dev + 0x9c3f0), sh = *(volatile int *)((char *)dev + 0x9c3f4);
            int f565 = *(volatile int *)((char *)dev + 0x9c370);   /* 1: green mask 0x7e0 (565), 0: 555 */
            int gx = DATA[0x84 / 4], gy = DATA[0x88 / 4];
            unsigned idx = (unsigned)DATA[0x90 / 4];
            int i;
            fill(base, pitch, sw, sh, gx, gy, BARS * 2 + 4, GRAPH_H + 4, rgb(f565, 8, 8, 8));
            fill(base, pitch, sw, sh, gx + 2, gy + 2 + GRAPH_H - 50, BARS * 2, 1, rgb(f565, 110, 110, 110));    /* 16.7 ms: 60 FPS */
            fill(base, pitch, sw, sh, gx + 2, gy + 2 + GRAPH_H - 100, BARS * 2, 1, rgb(f565, 110, 110, 110));   /* 33.3 ms: 30 FPS */
            for (i = 0; i < BARS; i++) {
                unsigned ms10 = RING[(idx - BARS + i) & 255];
                int h = (int)(ms10 * 3 / 10);
                unsigned short c;
                if (h < 1) continue;
                if (h > GRAPH_H) h = GRAPH_H;
                c = ms10 <= 167 ? rgb(f565, 60, 220, 60) : ms10 <= 333 ? rgb(f565, 240, 200, 40) : rgb(f565, 240, 60, 60);
                fill(base, pitch, sw, sh, gx + 2 + i * 2, gy + 2 + GRAPH_H - h, 2, h, c);
            }
            ((UnlockFn)unlock_addr)(dev);
        }
    }
    ((FlipFn)flip_addr)(dev);
}
