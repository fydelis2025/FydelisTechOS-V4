#!/usr/bin/env python3
import os
import glob
from PIL import Image, ImageDraw, ImageFont

FONT_DIR = "assets/fontes"
OUT_H = "include/fontes_ui.h"
W, H = 12, 22

os.makedirs(os.path.dirname(OUT_H), exist_ok=True)
ttfs = sorted(glob.glob(os.path.join(FONT_DIR, "*.ttf")))

if ttfs:
    fonte = ImageFont.truetype(ttfs[0], 18)
else:
    try:
        fonte = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
    except Exception:
        fonte = ImageFont.load_default()

with open(OUT_H, "w", encoding="utf-8") as f:
    f.write("#ifndef FONTES_UI_H\n#define FONTES_UI_H\n\n#include <stdint.h>\n\n")
    f.write(f"#define FONTE_UI_W {W}\n#define FONTE_UI_H {H}\n\n")
    f.write(f"static const uint8_t fonte_ui_alpha[95][{W * H}] = {{\n")

    for code in range(32, 127):
        img = Image.new("L", (W, H), 0)
        draw = ImageDraw.Draw(img)
        draw.text((1, 2), chr(code), fill=255, font=fonte)
        dados = list(img.getdata())
        f.write("    { " + ", ".join(str(v) for v in dados) + " },\n")

    f.write("};\n\n#endif /* FONTES_UI_H */\n")

print(f"[OK] Fonte UI gerada em {OUT_H}")
