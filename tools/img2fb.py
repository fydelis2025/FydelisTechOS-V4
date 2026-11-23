#!/usr/bin/env python3
import os
import glob
from PIL import Image

WALL_DIR = "assets/wallpapers"
OUT_H = "include/wallpaper.h"
W, H = 320, 200

os.makedirs(os.path.dirname(OUT_H), exist_ok=True)
imgs = [p for p in sorted(glob.glob(os.path.join(WALL_DIR, "*"))) if os.path.isfile(p)]

if imgs:
    img = Image.open(imgs[0]).convert("RGB").resize((W, H))
else:
    img = Image.new("RGB", (W, H))
    for y in range(H):
        for x in range(W):
            r = int(18 + (x / W) * 24)
            g = int(8 + (y / H) * 14)
            b = int(38 + ((x + y) / (W + H)) * 48)
            img.putpixel((x, y), (r, g, b))

pixels = list(img.getdata())

with open(OUT_H, "w", encoding="utf-8") as f:
    f.write("#ifndef WALLPAPER_H\n#define WALLPAPER_H\n\n#include <stdint.h>\n\n")
    f.write(f"#define WALLPAPER_W {W}\n#define WALLPAPER_H {H}\n\n")
    f.write(f"static const uint32_t wallpaper_pixels[{W * H}] = {{\n    ")
    for i, (r, g, b) in enumerate(pixels):
        val = 0xFF000000 | (r << 16) | (g << 8) | b
        f.write(f"0x{val:08X}U, ")
        if (i + 1) % 10 == 0 and (i + 1) < len(pixels):
            f.write("\n    ")
    f.write("\n};\n\n#endif /* WALLPAPER_H */\n")

print(f"[OK] Wallpaper gerado em {OUT_H}")
