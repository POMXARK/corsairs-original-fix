"""Reader and writer of the .tf textures of the original game (Sea Dogs / Corsairs), ours, from the open description
of the format (AlexKimov/seadogs-file-formats, TF.bt) and from the files themselves.

A file is: a header of 16 bytes, a 16-bit picture with its mip maps, then (when masks > 0) a palette of 256 RGBA and
8-bit copies of the picture with their own mip maps.
  header: u32 signature (0x3D34A, 0 or 0x50198), u8 unknown, u8 format, u8 mips, u8 masks, u32 width, u32 height
  format: 0 = RGB565, 1 = 1555 (alpha in the top bit), 2 = 4444 (checked against pictures, see docs/textures.md)
"""
import struct
from pathlib import Path

import numpy as np
from PIL import Image

HEADER = "<IBBBBII"
FORMATS = {0: "565", 1: "1555", 2: "4444"}


def _level(w, h, i):
    return max(w >> i, 1), max(h >> i, 1)


def decode16(raw, fmt, w, h):
    a = np.frombuffer(raw, "<u2").reshape(h, w).astype(np.uint32)
    if fmt == 0:
        r, g, b, al = (a >> 11) & 31, (a >> 5) & 63, a & 31, np.full_like(a, 255)
        r, g, b = (r * 255 + 15) // 31, (g * 255 + 31) // 63, (b * 255 + 15) // 31
    elif fmt == 1:
        r, g, b, al = (a >> 10) & 31, (a >> 5) & 31, a & 31, np.where(a >> 15, 255, 0)
        r, g, b = (r * 255 + 15) // 31, (g * 255 + 15) // 31, (b * 255 + 15) // 31
    else:
        r, g, b, al = (a >> 8) & 15, (a >> 4) & 15, a & 15, (a >> 12) & 15
        r, g, b, al = r * 17, g * 17, b * 17, al * 17
    return Image.fromarray(np.stack([r, g, b, al], -1).astype(np.uint8), "RGBA")


def encode16(img, fmt, dither=False):
    """dither: a little noise of the size of one step before the rounding to 5/6 bits, so that a smooth gradient of a
    bigger picture does not turn into bands (the original pictures are already 16-bit: they are not dithered)."""
    a = np.asarray(img.convert("RGBA"), np.float32)
    if dither and fmt == 0:
        step = np.array([255 / 31, 255 / 63, 255 / 31, 0], np.float32)
        a = a + (np.random.default_rng(1).random(a.shape[:2] + (1,), dtype=np.float32) - 0.5) * step
    a = np.clip(np.rint(a), 0, 255).astype(np.uint32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    if fmt == 0:
        out = ((r * 31 + 127) // 255 << 11) | ((g * 63 + 127) // 255 << 5) | ((b * 31 + 127) // 255)
    elif fmt == 1:
        out = ((al >= 128).astype(np.uint32) << 15) | ((r * 31 + 127) // 255 << 10) | ((g * 31 + 127) // 255 << 5) | ((b * 31 + 127) // 255)
    else:
        out = ((al + 8) // 17 << 12) | ((r + 8) // 17 << 8) | ((g + 8) // 17 << 4) | ((b + 8) // 17)
    return out.astype("<u2").tobytes()


def read_tf(path):
    """-> dict(head, mips: [PIL RGBA], masks: [(indices array)], palette bytes)"""
    d = Path(path).read_bytes()
    sig, unk, fmt, nm, nk, w, h = struct.unpack_from(HEADER, d)
    pos, mips = 16, []
    for i in range(nm):
        lw, lh = _level(w, h, i)
        mips.append(decode16(d[pos:pos + lw * lh * 2], fmt, lw, lh))
        pos += lw * lh * 2
    pal, masks = b"", []
    if nk:
        pal, pos = d[pos:pos + 1024], pos + 1024
        for i in range(nk):
            lw, lh = _level(w, h, i)
            masks.append(np.frombuffer(d[pos:pos + lw * lh], np.uint8).reshape(lh, lw))
            pos += lw * lh
    assert pos == len(d), f"{path}: {len(d) - pos} bytes left"
    return dict(sig=sig, unk=unk, fmt=fmt, w=w, h=h, mips=mips, masks=masks, palette=pal)


def mip_chain(img, count):
    out = [img]
    for i in range(1, count):
        out.append(img.resize(_level(img.width, img.height, i), Image.BOX))
    return out


def write_tf(path, img, like, mips=None, masks=None, dither=False):
    """Writes img (RGBA, any size) in the format of `like` (the dict of read_tf): the same number of mips and masks
    as the original, but not more levels than the picture has sizes."""
    w, h = img.size
    fmt = like["fmt"]
    levels = len(like["mips"]) if mips is None else mips
    levels = min(levels, max(w, h).bit_length())
    nk = min(len(like["masks"]), levels) if masks is None else masks
    chain = mip_chain(img, levels)
    body = b"".join(encode16(m, fmt, dither) for m in chain)
    if nk:
        pal_img = img.convert("RGB").quantize(256, Image.MEDIANCUT, dither=Image.NONE)
        pal = np.asarray(pal_img.getpalette()[:768], np.uint8).reshape(-1, 3)
        pal = np.concatenate([pal, np.zeros((256 - len(pal), 3), np.uint8)])
        alpha = np.full((256, 1), 255, np.uint8)
        body += np.concatenate([pal, alpha], 1).tobytes()
        for m in chain[:nk]:
            body += np.asarray(m.convert("RGB").quantize(palette=pal_img, dither=Image.NONE), np.uint8).tobytes()
    head = struct.pack(HEADER, like["sig"], like["unk"], fmt, levels, nk, w, h)
    Path(path).write_bytes(head + body)
