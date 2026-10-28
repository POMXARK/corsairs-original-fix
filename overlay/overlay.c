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
 *   +0x400.. char fmt[4][32] at +0x400, +0x420, +0x440, +0x460 (framerate, frametime, 1% low, 0.1% low) and +0x480 (the scale, ms): formats of the text function, written by capture.ps1
 *   +0x100 unsigned short ring[256]: the frame times in tenths of a millisecond
 *   +0xB0 the real GetTickCount, +0xB4 ms of fast_tick(), +0xB8 TSC of that ms, +0xBC 1 = fast_tick is ready (capture.ps1 then points the IAT slot 0x431050 at it), +0xC0 ms of the last sync
 *   +0xA0 key repeat on (0/1, capture.ps1 writes 1 while the game is the window in front); +0x500 unsigned hold[256]: GetTickCount of the key press (0 = up)
 * Build: ./build_overlay.sh  ->  overlay.bin (the code, loaded at 0x7E001000).
 */
typedef void (__attribute__((cdecl)) *TextFn)(void *font, int x, int y, const char *fmt, ...);
typedef void (__attribute__((fastcall)) *FlipFn)(void *dev);
typedef unsigned (__attribute__((thiscall)) *LockFn)(void *dev, int *pitch);   /* FUN_0040b4e0: the pixels of the back buffer, 0 if locked */
typedef void (__attribute__((fastcall)) *UnlockFn)(void *dev);                  /* FUN_0040b540 */
typedef unsigned (__attribute__((stdcall)) *TickFn)(void);
typedef short (__attribute__((stdcall)) *KeyFn)(int vk);                             /* GetAsyncKeyState */
typedef unsigned (__attribute__((thiscall)) *QueueFn)(void *q, unsigned msg, unsigned wparam, unsigned lparam);   /* FUN_0041eba0: the queue of the input messages of the frame */

#define DATA ((volatile int *)0x7E000000)
#define RING ((volatile unsigned short *)0x7E000100)
#define BARS 240                 /* frames in the graph, 2 pixels each */
#define HOLD ((volatile unsigned *)0x7E000500)
#define REPEAT_AFTER 150         /* ms of a held key before the first repeat that we send (Windows: 250..1000) */
#define REPEAT_EVERY 30          /* ms between our repeats */
#define GRAPH_H 100              /* the height of the graph, its scale follows the worst frame */

/* FUN_00426370 of ENGINE.exe takes the time of the frame from GetTickCount, whose step is 15.6 ms on Windows: at 100+ fps the frames get 0, 0, 16, 0, 16 ms and the
 * movement is jerky. This is the replacement of that import: the same milliseconds, counted by the TSC (the cycles per ms are measured by the hook), every second pulled back to the real tick. */
__attribute__((stdcall)) unsigned fast_tick(void)
{
    unsigned now = __builtin_ia32_rdtsc();
    unsigned cpm = (unsigned)DATA[0x8C / 4];
    int dt = (int)(now - (unsigned)DATA[0xB8 / 4]);
    if (cpm >= 10 && dt >= (int)cpm) {
        unsigned d = (unsigned)dt / cpm;
        DATA[0xB4 / 4] = (int)((unsigned)DATA[0xB4 / 4] + d);
        DATA[0xB8 / 4] = (int)((unsigned)DATA[0xB8 / 4] + d * cpm);
    }
    return (unsigned)DATA[0xB4 / 4];
}

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

__attribute__((fastcall, aligned(256))) void hook(void *dev)   /* at +0x100 of the code: fast_tick is at +0, the call site points at +0x100 */
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

    if (DATA[0x80 / 4] && cpm >= 10) {   /* the block like the OSD of RivaTuner: the numbers, then a line graph of the frame time */
        unsigned idx = (unsigned)DATA[0x90 / 4];
        unsigned mx = 0, m2 = 0, m3 = 0, sum = 0, n = 0, lastv = RING[(idx - 1) & 255];
        int gx = DATA[0x84 / 4], gy = DATA[0x88 / 4], i;
        void *font = (void *)font_addr;
        for (i = 0; i < BARS; i++) {
            unsigned v = RING[(idx - BARS + i) & 255];
            if (!v) continue;
            sum += v; n++;
            if (v > mx) { m3 = m2; m2 = mx; mx = v; } else if (v > m2) { m3 = m2; m2 = v; } else if (v > m3) m3 = v;
        }
        if (n) {
            unsigned avg = sum / n;
            unsigned top = (mx / 100 + 1) * 100;      /* the scale of the graph: the worst frame up to 10 ms, not under 20 ms */
            int pitch = 0, py = 0, f565 = 0;
            unsigned short *base;
            if (top < 200) top = 200;
            text(font, gx, gy, (const char *)(DATA + 0x400 / 4), (int)(10000 / avg));
            text(font, gx, gy + 18, (const char *)(DATA + 0x420 / 4), lastv / 10, lastv % 10);
            text(font, gx, gy + 36, (const char *)(DATA + 0x440 / 4), (int)(10000 / (n >= 100 ? m3 : mx)));
            text(font, gx, gy + 54, (const char *)(DATA + 0x460 / 4), (int)(10000 / mx));
            text(font, gx + BARS * 2 - 70, gy + 54, (const char *)(DATA + 0x480 / 4), (int)(top / 10));
            base = (unsigned short *)((LockFn)lock_addr)(dev, &pitch);
            if (base && pitch > 0) {
                int sw = *(volatile int *)((char *)dev + 0x9c3f0), sh = *(volatile int *)((char *)dev + 0x9c3f4);
                int top_y = gy + 76, prev = -1;
                f565 = *(volatile int *)((char *)dev + 0x9c370);   /* 1: green mask 0x7e0 (565), 0: 555 */
                fill(base, pitch, sw, sh, gx, top_y, BARS * 2 + 4, GRAPH_H + 4, rgb(f565, 10, 10, 10));
                fill(base, pitch, sw, sh, gx + 2, top_y + 2 + GRAPH_H / 2, BARS * 2, 1, rgb(f565, 70, 70, 70));
                for (i = 0; i < BARS; i++) {
                    unsigned v = RING[(idx - BARS + i) & 255];
                    int y = GRAPH_H - (int)(v * GRAPH_H / top), y0, y1;
                    if (!v) continue;
                    if (y < 0) y = 0;
                    if (y > GRAPH_H - 1) y = GRAPH_H - 1;
                    y0 = prev < 0 ? y : (prev < y ? prev : y);
                    y1 = prev < 0 ? y : (prev < y ? y : prev);
                    fill(base, pitch, sw, sh, gx + 2 + i * 2, top_y + 2 + y0, 2, y1 - y0 + 1, v > 333 ? rgb(f565, 240, 70, 70) : v > 167 ? rgb(f565, 240, 200, 50) : rgb(f565, 90, 230, 90));
                    prev = y;
                }
                ((UnlockFn)unlock_addr)(dev);
            }
            py = 0; (void)py;
        }
    }
    if (cpm >= 10) {   /* the fine tick: start it, then every second compare it with the real one */
        TickFn real = (TickFn)(unsigned)DATA[0xB0 / 4];
        if (!DATA[0xBC / 4]) {
            real = *(TickFn *)tick_iat;
            DATA[0xB0 / 4] = (int)(unsigned)real;
            DATA[0xB4 / 4] = (int)real();
            DATA[0xB8 / 4] = (int)now;
            DATA[0xC0 / 4] = DATA[0xB4 / 4];
            DATA[0xBC / 4] = 1;
        } else if ((unsigned)DATA[0xB4 / 4] - (unsigned)DATA[0xC0 / 4] >= 1000) {
            int diff = (int)((unsigned)DATA[0xB4 / 4] - real());   /* the real tick is up to 16 ms behind the true time */
            DATA[0xC0 / 4] = DATA[0xB4 / 4];
            if (diff < 0) { DATA[0xB4 / 4] = (int)real(); DATA[0xB8 / 4] = (int)now; }
            else if (diff > 20) DATA[0xB8 / 4] = (int)((unsigned)DATA[0xB8 / 4] + (unsigned)(diff - 8) * cpm);
        }
    }
    if (DATA[0xA0 / 4]) {   /* the game reads the keys from WM_KEYDOWN only (the typematic of Windows: a pause, and only the last key repeats): a key that is held is queued again, as the window procedure 0x417c80 does */
        volatile unsigned key_iat = 0x4311A0;   /* the import GetAsyncKeyState */
        volatile unsigned queue_addr = 0x41EBA0;
        volatile unsigned queue_obj = 0x77DD28;
        unsigned tick = (*(TickFn *)tick_iat)();
        int vk;
        if (!tick) tick = 1;
        for (vk = 8; vk < 0x5B; vk++) {
            if (!(vk == 0x20 || (vk >= 0x25 && vk <= 0x28) || (vk >= 0x41 && vk <= 0x5A))) continue;
            if (!((*(KeyFn *)key_iat)(vk) & 0x8000)) { HOLD[vk] = 0; continue; }
            if (!HOLD[vk]) { HOLD[vk] = tick; continue; }
            if (tick - HOLD[vk] >= REPEAT_AFTER) {
                ((QueueFn)queue_addr)((void *)queue_obj, 0x100, (unsigned)vk, 0x40000001u);   /* WM_KEYDOWN, repeat count 1, bit 30: was down */
                HOLD[vk] = tick - (REPEAT_AFTER - REPEAT_EVERY);
            }
        }
    }
    ((FlipFn)flip_addr)(dev);
}
