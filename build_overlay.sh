#!/usr/bin/env bash
# overlay/overlay.c -> overlay.bin: raw code for the cave at 0x3F001000 in ENGINE.exe (clang, no linker: no relocations in the code)
set -eu
cd "$(dirname "$0")"
clang -target i686-unknown-linux-gnu -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -mno-sse -fno-asynchronous-unwind-tables -c overlay/overlay.c -o /tmp/overlay.o
if llvm-objdump -r /tmp/overlay.o | grep -q "R_386_"; then echo "relocations in overlay.o"; llvm-objdump -r /tmp/overlay.o; exit 1; fi
[ "$(llvm-nm /tmp/overlay.o | awk '$3=="fast_tick"{print $1}')$(llvm-nm /tmp/overlay.o | awk '$3=="hook"{print $1}')" = 0000000000000100 ] || { echo "fast_tick must be at 0 and hook at 0x100"; exit 1; }
[ "$(llvm-nm /tmp/overlay.o | awk '$3=="cursor_fix"{print $1}')" = 00000080 ] || { echo "cursor_fix must be at 0x80"; exit 1; }
[ "$(llvm-nm /tmp/overlay.o | awk '$3=="move_fix"{print $1}')" = 000000c0 ] || { echo "move_fix must be at 0xC0"; exit 1; }
[ "$(llvm-nm /tmp/overlay.o | awk '$3=="blt_fix"{print $1}')" = 00001000 ] || { echo "blt_fix must be at 0x1000"; exit 1; }
[ "$(llvm-nm /tmp/overlay.o | awk '$3=="cursor_get"{print $1}')" = 00002000 ] || { echo "cursor_get must be at 0x2000"; exit 1; }
llvm-objcopy -O binary --only-section=.text /tmp/overlay.o overlay.bin
llvm-objdump -d -M intel /tmp/overlay.o | sed -n 1,60p
echo "overlay.bin: $(stat -c %s overlay.bin) bytes"
