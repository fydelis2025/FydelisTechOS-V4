#!/usr/bin/env python3
import os
import glob
import cairosvg
from PIL import Image
import io

SVG_DIR = "assets/icones"
OUT_H = "include/icones.h"
TAM = 20

os.makedirs(SVG_DIR, exist_ok=True)
os.makedirs(os.path.dirname(OUT_H), exist_ok=True)

# Garante que os icones essenciais do sistema e do Systray existam
icones_padrao = {
    "fydelis_f.svg": '''<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
  <rect x="1" y="1" width="18" height="18" rx="4" fill="#281352" stroke="#00F5D4" stroke-width="1.6"/>
  <path d="M6 5h8v2.5H8.8v2.2h4.4v2.4H8.8V15H6V5z" fill="#00F5D4"/>
</svg>''',
    "bluetooth.svg": '''<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
  <path d="M6 6l8 8-4 4V2l4 4-8 8" fill="none" stroke="#00F5D4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''',
    "audio.svg": '''<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
  <polygon points="3,8 7,8 12,4 12,16 7,12 3,12" fill="#C77DFF"/>
  <path d="M14.5 7.5a4 4 0 0 1 0 5M16.5 5.5a7 7 0 0 1 0 9" fill="none" stroke="#00F5D4" stroke-width="1.6" stroke-linecap="round"/>
</svg>''',
    "disco.svg": '''<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">
  <rect x="3" y="4" width="14" height="12" rx="2" fill="#281352" stroke="#C77DFF" stroke-width="1.6"/>
  <line x1="3" y1="12" x2="17" y2="12" stroke="#C77DFF" stroke-width="1.4"/>
  <circle cx="14" cy="14" r="1.2" fill="#00FF9C"/>
</svg>'''
}

for nome_svg, conteudo_svg in icones_padrao.items():
    caminho_svg = os.path.join(SVG_DIR, nome_svg)
    if not os.path.exists(caminho_svg):
        with open(caminho_svg, "w", encoding="utf-8") as sf:
            sf.write(conteudo_svg)

svgs = sorted(glob.glob(os.path.join(SVG_DIR, "*.svg")))

with open(OUT_H, "w", encoding="utf-8") as f:
    f.write("#ifndef ICONES_H\n#define ICONES_H\n\n#include <stdint.h>\n\n")
    f.write(f"#define ICONE_TAM {TAM}\n\n")

    for caminho in svgs:
        nome = os.path.splitext(os.path.basename(caminho))[0].replace("-", "_")
        png_bytes = cairosvg.svg2png(url=caminho, output_width=TAM, output_height=TAM)
        img = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
        pixels = list(img.getdata())

        f.write(f"static const uint32_t icone_{nome}[{TAM * TAM}] = {{\n    ")
        for i, (r, g, b, a) in enumerate(pixels):
            argb = (a << 24) | (r << 16) | (g << 8) | b
            f.write(f"0x{argb:08X}U, ")
            if (i + 1) % 10 == 0 and (i + 1) < len(pixels):
                f.write("\n    ")
        f.write("\n};\n\n")

    f.write("#endif /* ICONES_H */\n")

print(f"[OK] {len(svgs)} icones convertidos para {OUT_H}")
