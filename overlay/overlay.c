/* Draws the FPS counter and the messages inside the game, with the debug font of ENGINE.exe (original Sea Dogs, 2000).
 *
 * The frame of the game is: the core draws the scene, then FUN_0040a2a0 flips the screen (Realize_Layers, 0x4205c0).
 * capture.ps1 puts this code into the process of the game and points the call at 0x420c0a to hook(): it prints the two
 * strings that capture.ps1 keeps in the data page and goes on to the flip. No imports and no relocations: every address is
 * a constant, the engine does not move (base 0x400000), the cave is placed at a fixed address.
 *
 * data page (0x7E000000): int fps_x, fps_y, msg_x, msg_y; char fps[48] at +0x10; char msg[64] at +0x40; int frames at +0x7C; an empty string draws nothing.
 * Build: ./build_overlay.sh  ->  overlay.bin (the code, loaded at 0x7E001000).
 */
typedef void (__attribute__((cdecl)) *TextFn)(void *font, int x, int y, const char *text);
typedef void (__attribute__((fastcall)) *FlipFn)(void *dev);

#define DATA ((volatile int *)0x7E000000)

__attribute__((fastcall)) void hook(void *dev)
{
    volatile unsigned text_addr = 0x40E860;   /* FUN_0040e860(font, x, y, format, ...): the debug text of the engine */
    volatile unsigned flip_addr = 0x40A2A0;   /* FUN_0040a2a0: the end of the frame, the flip */
    volatile unsigned font_addr = 0x7C77A8;   /* DAT_007c77a8: the font object */
    const char *fps = (const char *)(DATA + 4);
    const char *msg = (const char *)(DATA + 16);
    TextFn text = (TextFn)text_addr;
    DATA[31] = DATA[31] + 1;                  /* how many frames came here: capture.ps1 logs it */
    if (*fps) text((void *)font_addr, DATA[0], DATA[1], fps);
    if (*msg) text((void *)font_addr, DATA[2], DATA[3], msg);
    ((FlipFn)flip_addr)(dev);
}
