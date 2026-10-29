#!/usr/bin/env python3
"""Makes the textures (.tf) of the original game bigger with Real-ESRGAN (ours; the model is BSD-3-Clause).

The game folder is not touched: the new files go to --out with the same names; docs/textures.md says how to put
them in the game and how to bring the old ones back. The UV of the models do not depend on the size of a picture.

usage: tf_upscale.py <Textures dir> --out <dir> [--model RealESRGAN_x4plus.pth] [--scale 4] [--max 1024]
         [--only name ...] [--skip-small 32] [--types 0] [--no-dither]
  --only      the names of the files (without .tf, any case) or a pattern with * ; no --only: every file
  --types     the formats of the pictures that are done (0 = RGB565 colour; 1 and 2 have alpha: fonts, effects)
  --skip-small  a picture with the side below this is left (2x2 .. 16x16 are masks and fillers)
"""
import argparse
import fnmatch
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tf import read_tf, write_tf  # noqa: E402


def load_model(path, device):
    import torch
    from spandrel import ModelLoader
    m = ModelLoader().load_from_file(str(path)).to(device).eval()
    return m


def run_model(model, img, device, tile=256):
    """RGB PIL image -> RGB PIL image, scale of the model (x4); in tiles with an overlap so that a big picture fits."""
    import torch
    s = model.scale
    a = torch.from_numpy(np.asarray(img.convert("RGB"), np.float32) / 255).permute(2, 0, 1)[None].to(device)
    _, _, h, w = a.shape
    pad = 16
    out = torch.zeros(1, 3, h * s, w * s)
    with torch.no_grad():
        for y in range(0, h, tile):
            for x in range(0, w, tile):
                y0, x0, y1, x1 = max(y - pad, 0), max(x - pad, 0), min(y + tile + pad, h), min(x + tile + pad, w)
                r = model(a[:, :, y0:y1, x0:x1]).clamp(0, 1).cpu()
                cy0, cx0 = (y - y0) * s, (x - x0) * s
                ch, cw = min(tile, h - y) * s, min(tile, w - x) * s
                out[:, :, y * s:y * s + ch, x * s:x * s + cw] = r[:, :, cy0:cy0 + ch, cx0:cx0 + cw]
    return Image.fromarray((out[0].permute(1, 2, 0).numpy() * 255 + 0.5).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser(usage=__doc__)
    ap.add_argument("src", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--model", type=Path, default=Path("RealESRGAN_x4plus.pth"))
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--max", type=int, default=1024)
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--types", nargs="*", type=int, default=[0])
    ap.add_argument("--skip-small", type=int, default=32)
    ap.add_argument("--no-dither", action="store_true")
    a = ap.parse_args()

    import torch
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = load_model(a.model, device)
    files = sorted(a.src.rglob("*.tf"))
    if a.only:
        pats = [p.lower().removesuffix(".tf") for p in a.only]
        files = [f for f in files if any(fnmatch.fnmatch(f.stem.lower(), p) for p in pats)]
    t0, done, skipped = time.time(), 0, 0
    for f in files:
        out = a.out / f.relative_to(a.src)
        if out.exists():
            continue  # a run that stopped goes on from where it was
        tf = read_tf(f)
        if tf["fmt"] not in a.types or min(tf["w"], tf["h"]) < a.skip_small:
            skipped += 1
            continue
        w, h = tf["w"], tf["h"]
        k = min(a.scale, a.max // max(w, h))
        if k < 2:
            skipped += 1
            continue
        top = tf["mips"][0]
        rgb = run_model(model, top.convert("RGB"), device).resize((w * k, h * k), Image.LANCZOS)
        if tf["fmt"] != 0:  # the alpha is scaled by Lanczos (the model does not draw it)
            rgb = Image.merge("RGBA", (*rgb.split(), top.getchannel("A").resize((w * k, h * k), Image.LANCZOS)))
        else:
            rgb = rgb.convert("RGBA")
        extra = k.bit_length() - 1
        out.parent.mkdir(parents=True, exist_ok=True)
        write_tf(out, rgb, tf, mips=len(tf["mips"]) + extra, masks=len(tf["masks"]) + extra if tf["masks"] else 0,
                 dither=not a.no_dither)
        done += 1
        print(f"{f.name}: {w}x{h} -> {w * k}x{h * k} ({time.time() - t0:.0f} s)", flush=True)
    print(f"done {done}, skipped {skipped}")


if __name__ == "__main__":
    main()
